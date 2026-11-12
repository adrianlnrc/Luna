-- Assessor (PRD RF-15, RF-16, RF-17): custo e valor, franquia, exportacao e exclusao. Idempotente. NAO aplicado em producao.
SET search_path = agente, public;

-- ---------- 1) uso de IA ligado a execucao ----------
CREATE OR REPLACE FUNCTION f_ai_log_run(p_user bigint, p_run bigint, p_kind text, p_model text, p_in integer, p_out integer,
                                        p_extra_usd numeric DEFAULT 0, p_est boolean DEFAULT false) RETURNS bigint
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE v_id bigint;
BEGIN
  INSERT INTO ai_usage (user_id, day, kind, model, tokens_in, tokens_out, estimated, extra_usd, run_id)
  VALUES (p_user, f_fin_today(p_user), coalesce(nullif(p_kind, ''), 'texto'), coalesce(p_model, ''),
          greatest(coalesce(p_in, 0), 0), greatest(coalesce(p_out, 0), 0), coalesce(p_est, false), coalesce(p_extra_usd, 0), p_run)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- custo em reais de uma linha de ai_usage (mesma conta do /custo)
CREATE OR REPLACE FUNCTION f_ai_usage_brl(u ai_usage) RETURNS numeric
LANGUAGE sql STABLE SET search_path = agente, public AS $$
  SELECT (coalesce(u.tokens_in * p.usd_per_1m_in + u.tokens_out * p.usd_per_1m_out, 0) / 1000000.0 + coalesce(u.extra_usd, 0))
         * coalesce(p.usd_brl, (SELECT max(usd_brl) FROM ai_pricing), 5.5)
    FROM (SELECT 1) one LEFT JOIN ai_pricing p ON p.model = u.model
$$;

-- ---------- 2) franquia ----------
CREATE OR REPLACE FUNCTION f_quota_state(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE pl plans%ROWTYPE; q usage_quota%ROWTYPE; v_mes date := date_trunc('month', f_fin_today(p_user))::date; v_msgs int;
BEGIN
  SELECT p.* INTO pl FROM plans p JOIN users u ON u.plan_id = p.id WHERE u.id = p_user;
  SELECT * INTO q FROM usage_quota WHERE user_id = p_user AND mes = v_mes;
  SELECT msgs INTO v_msgs FROM usage_daily WHERE user_id = p_user AND dia = f_fin_today(p_user);
  RETURN jsonb_build_object('mes', v_mes, 'analises', coalesce(q.analises, 0), 'analises_web', coalesce(q.analises_web, 0),
    'limite_analises', pl.analises_mes, 'limite_web', pl.analises_web_mes, 'msgs_hoje', coalesce(v_msgs, 0), 'limite_msgs', pl.msgs_dia,
    'tem_analise', coalesce(q.analises, 0) < pl.analises_mes,
    'tem_web', coalesce(q.analises, 0) < pl.analises_mes AND coalesce(q.analises_web, 0) < pl.analises_web_mes);
END $$;

-- conta uma mensagem do dia; ok=false quando passou do teto diario (protecao contra abuso)
CREATE OR REPLACE FUNCTION f_quota_msg(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE v_msgs int; v_lim int;
BEGIN
  INSERT INTO usage_daily (user_id, dia, msgs) VALUES (p_user, f_fin_today(p_user), 1)
  ON CONFLICT (user_id, dia) DO UPDATE SET msgs = usage_daily.msgs + 1 RETURNING msgs INTO v_msgs;
  SELECT p.msgs_dia INTO v_lim FROM plans p JOIN users u ON u.plan_id = p.id WHERE u.id = p_user;
  RETURN jsonb_build_object('ok', v_msgs <= v_lim, 'msgs', v_msgs, 'limite', v_lim);
END $$;

-- ---------- 3) execucoes ----------
CREATE OR REPLACE FUNCTION f_run_open(p_user bigint, p_origem text, p_canal text DEFAULT 'telegram') RETURNS bigint
LANGUAGE sql SET search_path = agente, public AS $$
  INSERT INTO assessor_runs (user_id, origem, canal) VALUES (p_user, p_origem, coalesce(nullif(p_canal, ''), 'telegram')) RETURNING id
$$;

-- Fecha a execucao: grava os dados, soma o custo (ai_usage da execucao) e desconta a franquia.
-- A revisao da semana e o Vigia nao descontam (PRD RF-09).
CREATE OR REPLACE FUNCTION f_run_close(p_user bigint, p_run bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE r assessor_runs%ROWTYPE; v_custo numeric; v_mes date := date_trunc('month', f_fin_today(p_user))::date;
        v_analise boolean := coalesce((p->>'analise')::boolean, false); v_web boolean := coalesce((p->>'com_web')::boolean, false);
BEGIN
  SELECT coalesce(sum(f_ai_usage_brl(a)), 0) INTO v_custo FROM ai_usage a WHERE a.run_id = p_run AND a.user_id = p_user;
  UPDATE assessor_runs SET
    modelo = coalesce(p->>'modelo', modelo), passos = coalesce((p->>'passos')::int, passos),
    ferramentas = coalesce((SELECT array_agg(x) FROM jsonb_array_elements_text(p->'ferramentas') x), ferramentas),
    gravacoes = coalesce((p->>'gravacoes')::int, gravacoes), propostas = coalesce((p->>'propostas')::int, propostas),
    com_web = v_web, analise = v_analise, degradado = coalesce((p->>'degradado')::boolean, false),
    limite = p->>'limite', duracao_ms = (p->>'duracao_ms')::int,
    resultado = CASE WHEN p->>'resultado' IN ('respondido', 'acao_confirmada', 'aceito', 'ignorado', 'rejeitado', 'erro')
                     THEN p->>'resultado' ELSE resultado END,
    custo_brl = v_custo
  WHERE id = p_run AND user_id = p_user RETURNING * INTO r;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false); END IF;
  IF v_analise AND r.origem = 'pergunta' AND NOT r.degradado THEN
    INSERT INTO usage_quota (user_id, mes, analises, analises_web) VALUES (p_user, v_mes, 1, CASE WHEN v_web THEN 1 ELSE 0 END)
    ON CONFLICT (user_id, mes) DO UPDATE SET analises = usage_quota.analises + 1,
                                             analises_web = usage_quota.analises_web + CASE WHEN v_web THEN 1 ELSE 0 END;
  END IF;
  RETURN jsonb_build_object('ok', true, 'id', r.id, 'custo_brl', v_custo, 'resultado', r.resultado);
END $$;

-- Transicoes de resultado depois do fechamento. Uma acao confirmada nunca e rebaixada.
CREATE OR REPLACE FUNCTION f_run_result(p_user bigint, p_run bigint, p_resultado text) RETURNS text
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE v_cur text; v_new text;
BEGIN
  SELECT resultado INTO v_cur FROM assessor_runs WHERE id = p_run AND user_id = p_user;
  IF NOT FOUND OR p_resultado NOT IN ('respondido', 'acao_confirmada', 'aceito', 'ignorado', 'rejeitado', 'erro') THEN RETURN v_cur; END IF;
  v_new := CASE
    WHEN p_resultado = 'acao_confirmada' THEN 'acao_confirmada'
    WHEN v_cur = 'acao_confirmada' THEN v_cur
    WHEN p_resultado = 'aceito' THEN 'aceito'
    WHEN v_cur = 'aceito' THEN v_cur
    ELSE p_resultado END;
  UPDATE assessor_runs SET resultado = v_new WHERE id = p_run AND user_id = p_user;
  RETURN v_new;
END $$;

-- Propostas sem resposta em 24 h contam como ignoradas (so quando a execucao ficou em "respondido").
CREATE OR REPLACE FUNCTION f_runs_expire(p_user bigint) RETURNS integer
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE n int;
BEGIN
  UPDATE pending_actions SET status = 'expirada', resolvido_em = now()
   WHERE user_id = p_user AND status = 'pendente' AND expira_em <= now();
  WITH upd AS (
    UPDATE assessor_runs r SET resultado = 'ignorado'
     WHERE r.user_id = p_user AND r.resultado = 'respondido' AND r.propostas > 0 AND r.criado_em < now() - interval '24 hours'
       AND NOT EXISTS (SELECT 1 FROM pending_actions pa WHERE pa.run_id = r.id AND pa.status IN ('pendente', 'executando', 'executada'))
    RETURNING 1)
  SELECT count(*) INTO n FROM upd;
  RETURN n;
END $$;

-- ---------- 4) o que o usuario ve: franquia e valor ----------
CREATE OR REPLACE FUNCTION f_value_line(p_user bigint) RETURNS text
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE q jsonb := f_quota_state(p_user); v_ini timestamptz; v_acoes int;
        tz text := (SELECT timezone FROM users WHERE id = p_user);
BEGIN
  v_ini := ((q->>'mes')::date::timestamp AT TIME ZONE coalesce(tz, 'America/Sao_Paulo'));
  SELECT coalesce((SELECT sum(gravacoes) FROM assessor_runs WHERE user_id = p_user AND criado_em >= v_ini), 0)
       + (SELECT count(*) FROM pending_actions WHERE user_id = p_user AND status = 'executada' AND resolvido_em >= v_ini)
    INTO v_acoes;
  RETURN (q->>'analises') || ' de ' || (q->>'limite_analises') || ' análises no mês · ' || v_acoes
         || CASE WHEN v_acoes = 1 THEN ' ação concluída' ELSE ' ações concluídas' END;
END $$;

-- historico de decisoes para o contexto do agente (ate 10 linhas, 30 dias)
CREATE OR REPLACE FUNCTION f_decisions_txt(p_user bigint) RETURNS text
LANGUAGE sql STABLE SET search_path = agente, public AS $$
  SELECT coalesce(string_agg('- ' || linha, E'\n' ORDER BY quando DESC), '') FROM (
    SELECT quando, linha FROM (
      SELECT pa.criado_em AS quando,
             to_char(pa.criado_em AT TIME ZONE u.timezone, 'DD/MM') || ': propus "' || left(pa.resumo, 110) || '" -> '
             || CASE pa.status WHEN 'executada' THEN 'confirmou' WHEN 'cancelada' THEN 'recusou' WHEN 'expirada' THEN 'nao respondeu'
                               WHEN 'pendente' THEN 'aguardando' ELSE pa.status END AS linha
        FROM pending_actions pa JOIN users u ON u.id = pa.user_id
       WHERE pa.user_id = p_user AND pa.criado_em > now() - interval '30 days' AND pa.resumo <> ''
      UNION ALL
      SELECT l.enviado_em,
             to_char(l.enviado_em AT TIME ZONE u.timezone, 'DD/MM') || ': avisei "' || left(l.texto, 110) || '" -> '
             || CASE coalesce(l.resposta, '') WHEN 'aceito' THEN 'aceitou' WHEN 'agora_nao' THEN 'disse agora nao'
                               WHEN 'silenciado' THEN 'pediu para nao avisar mais' WHEN 'ignorado' THEN 'ignorou' ELSE 'sem resposta' END
        FROM insights_log l JOIN users u ON u.id = l.user_id
       WHERE l.user_id = p_user AND l.enviado_em > now() - interval '30 days'
    ) todos ORDER BY quando DESC LIMIT 10) ult
$$;

-- padrao de recusa: 3 propostas parecidas recusadas em 30 dias (mesma ferramenta e acao) -> sugestao de criterio
CREATE OR REPLACE FUNCTION f_refusal_pattern(p_user bigint) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = agente, public AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('ferramenta', ferramenta, 'acao', acao, 'recusas', n, 'exemplos', ex)), '[]'::jsonb) FROM (
    SELECT ferramenta, acao, count(*) AS n, jsonb_agg(left(resumo, 100) ORDER BY id DESC) AS ex
      FROM pending_actions
     WHERE user_id = p_user AND status = 'cancelada' AND origem IN ('agente', 'vigia', 'revisao') AND criado_em > now() - interval '30 days'
     GROUP BY ferramenta, acao HAVING count(*) >= 3) x
$$;

-- ---------- 5) visoes internas (margem, confirmacao, regras, modelo) ----------
CREATE OR REPLACE VIEW v_assessor_margem AS
  SELECT u.id AS user_id, u.name, m.mes,
         coalesce(c.custo_brl, 0) AS custo_ia_brl, coalesce(r.execucoes, 0) AS execucoes, coalesce(r.analises, 0) AS analises,
         coalesce(r.acoes_uteis, 0) AS acoes_uteis,
         CASE WHEN coalesce(r.acoes_uteis, 0) > 0 THEN round(coalesce(c.custo_brl, 0) / r.acoes_uteis, 4) END AS custo_por_acao_util
    FROM users u
    CROSS JOIN LATERAL (SELECT DISTINCT date_trunc('month', day)::date AS mes FROM ai_usage a WHERE a.user_id = u.id) m
    LEFT JOIN LATERAL (SELECT sum(f_ai_usage_brl(a)) AS custo_brl FROM ai_usage a
                        WHERE a.user_id = u.id AND date_trunc('month', a.day)::date = m.mes) c ON true
    LEFT JOIN LATERAL (SELECT count(*) AS execucoes, count(*) FILTER (WHERE analise) AS analises,
                              count(*) FILTER (WHERE resultado IN ('acao_confirmada', 'aceito')) + coalesce(sum(gravacoes), 0) AS acoes_uteis
                         FROM assessor_runs x WHERE x.user_id = u.id AND date_trunc('month', x.criado_em)::date = m.mes) r ON true;

CREATE OR REPLACE VIEW v_assessor_confirmacao AS
  SELECT user_id, date_trunc('month', criado_em)::date AS mes, count(*) AS propostas,
         count(*) FILTER (WHERE status = 'executada') AS confirmadas,
         count(*) FILTER (WHERE status = 'cancelada') AS recusadas,
         count(*) FILTER (WHERE status = 'expirada') AS expiradas,
         round(count(*) FILTER (WHERE status = 'executada')::numeric / greatest(count(*), 1) * 100, 1) AS taxa_confirmacao
    FROM pending_actions GROUP BY 1, 2;

CREATE OR REPLACE VIEW v_insight_regras AS
  SELECT user_id, regra, count(*) AS enviados,
         count(*) FILTER (WHERE resposta = 'aceito') AS aceitos,
         count(*) FILTER (WHERE resposta IN ('agora_nao', 'silenciado')) AS rejeitados,
         count(*) FILTER (WHERE resposta = 'ignorado') AS ignorados,
         round(count(*) FILTER (WHERE resposta = 'aceito')::numeric / greatest(count(*), 1) * 100, 1) AS taxa_aceite
    FROM insights_log WHERE via <> 'revisao' GROUP BY 1, 2;

CREATE OR REPLACE VIEW v_custo_modelo AS
  SELECT a.user_id, date_trunc('month', a.day)::date AS mes, a.model, count(*) AS chamadas,
         sum(a.tokens_in) AS tokens_in, sum(a.tokens_out) AS tokens_out, sum(f_ai_usage_brl(a)) AS custo_brl
    FROM ai_usage a GROUP BY 1, 2, 3;

-- ---------- 6) exportacao e exclusao (LGPD) ----------
-- Dinamicas de proposito: toda tabela do schema com coluna user_id entra sozinha, inclusive as futuras.
CREATE OR REPLACE FUNCTION f_user_tables() RETURNS TABLE (tabela text)
LANGUAGE sql STABLE SET search_path = agente, public AS $$
  SELECT c.table_name::text FROM information_schema.columns c
    JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE'
   WHERE c.table_schema = 'agente' AND c.column_name = 'user_id' ORDER BY 1
$$;

CREATE OR REPLACE FUNCTION f_user_export(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE out jsonb; r record; j jsonb;
BEGIN
  SELECT jsonb_build_object('exportado_em', now(), 'usuario', to_jsonb(u)) INTO out FROM users u WHERE u.id = p_user;
  IF out IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'usuario'); END IF;
  FOR r IN SELECT tabela FROM f_user_tables() WHERE tabela NOT LIKE '\_bak%' AND tabela NOT IN ('oauth_states') LOOP
    IF r.tabela = 'oauth_tokens' THEN  -- nunca exporta o token; so os metadados
      SELECT coalesce(jsonb_agg(jsonb_build_object('provedor', provedor, 'escopos', escopos, 'criado_em', criado_em, 'revogado_em', revogado_em)), '[]')
        INTO j FROM oauth_tokens WHERE user_id = p_user;
    ELSE
      EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) FROM agente.%I t WHERE t.user_id = $1', r.tabela) INTO j USING p_user;
    END IF;
    out := out || jsonb_build_object(r.tabela, j);
  END LOOP;
  SELECT coalesce(jsonb_agg(to_jsonb(m)), '[]') INTO j FROM contact_group_members m JOIN contact_groups g ON g.id = m.group_id WHERE g.user_id = p_user;
  out := out || jsonb_build_object('contact_group_members', j);
  SELECT coalesce(jsonb_agg(to_jsonb(d)), '[]') INTO j FROM fin_goal_deposits d JOIN fin_goals g ON g.id = d.goal_id WHERE g.user_id = p_user;
  out := out || jsonb_build_object('fin_goal_deposits', j);
  RETURN out;
END $$;

CREATE OR REPLACE FUNCTION f_user_purge(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE r record; pend text[]; nxt text[]; pass int := 0; n bigint; total bigint := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user) THEN RETURN jsonb_build_object('ok', false, 'error', 'usuario'); END IF;
  DELETE FROM contact_group_members m USING contact_groups g WHERE g.id = m.group_id AND g.user_id = p_user;
  DELETE FROM fin_goal_deposits d USING fin_goals g WHERE g.id = d.goal_id AND g.user_id = p_user;
  SELECT array_agg(tabela) INTO pend FROM f_user_tables();
  -- as chaves estrangeiras entre tabelas do usuario nao tem todas ON DELETE CASCADE: repete ate esvaziar
  WHILE coalesce(array_length(pend, 1), 0) > 0 AND pass < 12 LOOP
    pass := pass + 1; nxt := '{}';
    FOR r IN SELECT unnest(pend) AS tabela LOOP
      BEGIN
        EXECUTE format('DELETE FROM agente.%I WHERE user_id = $1', r.tabela) USING p_user;
        GET DIAGNOSTICS n = ROW_COUNT; total := total + n;
      EXCEPTION WHEN foreign_key_violation THEN nxt := nxt || r.tabela;
      END;
    END LOOP;
    pend := nxt;
  END LOOP;
  IF coalesce(array_length(pend, 1), 0) > 0 THEN
    RAISE EXCEPTION 'f_user_purge: nao consegui apagar %', pend;
  END IF;
  DELETE FROM users WHERE id = p_user;
  RETURN jsonb_build_object('ok', true, 'linhas', total);
END $$;
