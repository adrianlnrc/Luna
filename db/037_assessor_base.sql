-- Assessor (PRD-ASSESSOR.md, etapa 1): tabelas base do servico em codigo.
-- Idempotente. NAO aplicado em producao. Nao altera o comportamento do workflow do n8n.
SET search_path = agente, public;

-- ---------- 1) usuarios: plano, papel e revisao da semana ----------
CREATE TABLE IF NOT EXISTS plans (
  id               text PRIMARY KEY,
  nome             text NOT NULL,
  analises_mes     integer NOT NULL,
  analises_web_mes integer NOT NULL,
  msgs_dia         integer NOT NULL
);
INSERT INTO plans (id, nome, analises_mes, analises_web_mes, msgs_dia) VALUES
  ('base', 'Plano base', 100, 20, 300)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE users ADD COLUMN IF NOT EXISTS plan_id text NOT NULL DEFAULT 'base' REFERENCES plans(id);
ALTER TABLE users ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'ativo' CHECK (status IN ('ativo', 'encerrado'));
ALTER TABLE users ADD COLUMN IF NOT EXISTS papel text NOT NULL DEFAULT 'cliente' CHECK (papel IN ('dono', 'cliente'));
ALTER TABLE users ADD COLUMN IF NOT EXISTS revisao_dia integer NOT NULL DEFAULT 0 CHECK (revisao_dia BETWEEN 0 AND 6); -- 0 = domingo
ALTER TABLE users ADD COLUMN IF NOT EXISTS revisao_hora time NOT NULL DEFAULT '19:00';
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_review_on date;
ALTER TABLE users ADD COLUMN IF NOT EXISTS debug_trace boolean NOT NULL DEFAULT false;
-- quem ja usa o agente antes do servico e dono
UPDATE users SET papel = 'dono' WHERE onboarded_at IS NOT NULL AND created_at < '2026-11-12' AND papel = 'cliente';

-- ---------- 2) identidade por canal ----------
CREATE TABLE IF NOT EXISTS user_channels (
  user_id    bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  canal      text   NOT NULL,
  id_externo text   NOT NULL,
  criado_em  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (canal, id_externo)
);
CREATE INDEX IF NOT EXISTS user_channels_user ON user_channels (user_id);
INSERT INTO user_channels (user_id, canal, id_externo)
  SELECT id, 'telegram', telegram_id::text FROM users
ON CONFLICT DO NOTHING;

-- ---------- 3) aceite ----------
CREATE TABLE IF NOT EXISTS user_consents (
  id          bigserial PRIMARY KEY,
  user_id     bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  tipo        text   NOT NULL CHECK (tipo IN ('politica', 'saude')),
  versao      text   NOT NULL,
  aceito_em   timestamptz NOT NULL DEFAULT now(),
  revogado_em timestamptz
);
CREATE INDEX IF NOT EXISTS user_consents_user ON user_consents (user_id, tipo);
-- os donos atuais ja estavam cientes (README, "Privacidade"): aceite herdado, versao 'pre-servico'
INSERT INTO user_consents (user_id, tipo, versao)
  SELECT u.id, t.tipo, 'pre-servico' FROM users u CROSS JOIN (VALUES ('politica'), ('saude')) t(tipo)
   WHERE u.papel = 'dono' AND NOT EXISTS (SELECT 1 FROM user_consents c WHERE c.user_id = u.id AND c.tipo = t.tipo);

CREATE OR REPLACE FUNCTION f_consent_ok(p_user bigint, p_tipo text) RETURNS boolean
LANGUAGE sql STABLE SET search_path = agente, public AS $$
  SELECT EXISTS (SELECT 1 FROM user_consents WHERE user_id = p_user AND tipo = p_tipo AND revogado_em IS NULL)
$$;

CREATE OR REPLACE FUNCTION f_consent_set(p_user bigint, p_tipo text, p_versao text, p_aceita boolean) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
BEGIN
  IF p_tipo NOT IN ('politica', 'saude') THEN RETURN jsonb_build_object('ok', false, 'error', 'tipo_invalido'); END IF;
  IF p_aceita THEN
    IF NOT f_consent_ok(p_user, p_tipo) THEN
      INSERT INTO user_consents (user_id, tipo, versao) VALUES (p_user, p_tipo, coalesce(nullif(p_versao, ''), '1'));
    END IF;
  ELSE
    UPDATE user_consents SET revogado_em = now() WHERE user_id = p_user AND tipo = p_tipo AND revogado_em IS NULL;
  END IF;
  RETURN jsonb_build_object('ok', true, 'tipo', p_tipo, 'aceito', p_aceita);
END $$;

-- ---------- 4) convites do piloto ----------
CREATE TABLE IF NOT EXISTS invite_codes (
  codigo    text PRIMARY KEY,
  criado_em timestamptz NOT NULL DEFAULT now(),
  usado_por bigint REFERENCES users(id) ON DELETE SET NULL,
  usado_em  timestamptz
);

-- ---------- 5) Google por usuario ----------
CREATE TABLE IF NOT EXISTS oauth_tokens (
  user_id       bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provedor      text   NOT NULL DEFAULT 'google',
  escopos       text   NOT NULL DEFAULT '',
  token_cifrado text   NOT NULL,          -- JSON {access_token, refresh_token} cifrado pelo servico; a chave fica fora do banco
  expira_em     timestamptz,
  criado_em     timestamptz NOT NULL DEFAULT now(),
  renovado_em   timestamptz,
  revogado_em   timestamptz,
  PRIMARY KEY (user_id, provedor)
);
CREATE TABLE IF NOT EXISTS oauth_states (
  state     text PRIMARY KEY,
  user_id   bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  criado_em timestamptz NOT NULL DEFAULT now(),
  usado_em  timestamptz
);

-- ---------- 6) execucoes do assessor (custo e valor) ----------
CREATE TABLE IF NOT EXISTS assessor_runs (
  id          bigserial PRIMARY KEY,
  user_id     bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  origem      text   NOT NULL CHECK (origem IN ('pergunta', 'vigia', 'revisao')),
  modelo      text   NOT NULL DEFAULT '',
  passos      integer NOT NULL DEFAULT 0,
  ferramentas text[]  NOT NULL DEFAULT '{}',
  gravacoes   integer NOT NULL DEFAULT 0,
  propostas   integer NOT NULL DEFAULT 0,
  com_web     boolean NOT NULL DEFAULT false,
  analise     boolean NOT NULL DEFAULT false,   -- conta na franquia
  degradado   boolean NOT NULL DEFAULT false,   -- respondeu sem laco por falta de franquia
  custo_brl   numeric(12,6) NOT NULL DEFAULT 0,
  canal       text   NOT NULL DEFAULT 'telegram',
  resultado   text   NOT NULL DEFAULT 'respondido'
              CHECK (resultado IN ('respondido', 'acao_confirmada', 'aceito', 'ignorado', 'rejeitado', 'erro')),
  limite      text,                              -- passos | tempo | gravacoes | NULL
  duracao_ms  integer,
  criado_em   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS assessor_runs_user ON assessor_runs (user_id, criado_em DESC);
ALTER TABLE ai_usage ADD COLUMN IF NOT EXISTS run_id bigint REFERENCES assessor_runs(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS ai_usage_run ON ai_usage (run_id);

-- ---------- 7) acoes pendentes (propostas) ----------
CREATE TABLE IF NOT EXISTS pending_actions (
  id         bigserial PRIMARY KEY,
  user_id    bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  run_id     bigint REFERENCES assessor_runs(id) ON DELETE SET NULL,
  ferramenta text   NOT NULL,
  acao       text   NOT NULL,
  args       jsonb  NOT NULL DEFAULT '{}',
  nivel      integer NOT NULL CHECK (nivel BETWEEN 0 AND 3),
  origem     text   NOT NULL DEFAULT 'agente' CHECK (origem IN ('pedido', 'agente', 'vigia', 'revisao')),
  resumo     text   NOT NULL DEFAULT '',
  status     text   NOT NULL DEFAULT 'pendente'
             CHECK (status IN ('pendente', 'executando', 'executada', 'cancelada', 'expirada', 'falhou')),
  resultado  jsonb,
  criado_em  timestamptz NOT NULL DEFAULT now(),
  expira_em  timestamptz NOT NULL DEFAULT now() + interval '30 minutes',
  resolvido_em timestamptz
);
CREATE INDEX IF NOT EXISTS pending_actions_user ON pending_actions (user_id, status, id DESC);

-- Transicao atomica pendente -> executando. Clique duplo e proposta vencida nao executam.
CREATE OR REPLACE FUNCTION f_pending_claim(p_user bigint, p_id bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE pa pending_actions%ROWTYPE;
BEGIN
  UPDATE pending_actions SET status = 'expirada', resolvido_em = now()
   WHERE id = p_id AND user_id = p_user AND status = 'pendente' AND expira_em <= now();
  UPDATE pending_actions SET status = 'executando'
   WHERE id = p_id AND user_id = p_user AND status = 'pendente' AND expira_em > now()
  RETURNING * INTO pa;
  IF FOUND THEN
    RETURN jsonb_build_object('ok', true, 'id', pa.id, 'ferramenta', pa.ferramenta, 'acao', pa.acao, 'args', pa.args,
                              'nivel', pa.nivel, 'origem', pa.origem, 'run_id', pa.run_id);
  END IF;
  SELECT * INTO pa FROM pending_actions WHERE id = p_id AND user_id = p_user;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'motivo', 'inexistente', 'text', 'Não achei essa proposta.'); END IF;
  RETURN jsonb_build_object('ok', false, 'motivo', pa.status, 'text',
    CASE pa.status WHEN 'expirada' THEN 'Essa proposta expirou. Se ainda quiser, me peça de novo.'
                   WHEN 'cancelada' THEN 'Essa proposta já tinha sido cancelada.'
                   ELSE 'Essa proposta já foi resolvida.' END);
END $$;

CREATE OR REPLACE FUNCTION f_pending_finish(p_user bigint, p_id bigint, p_ok boolean, p_resultado jsonb) RETURNS void
LANGUAGE sql SET search_path = agente, public AS $$
  UPDATE pending_actions SET status = CASE WHEN p_ok THEN 'executada' ELSE 'falhou' END, resultado = p_resultado, resolvido_em = now()
   WHERE id = p_id AND user_id = p_user AND status = 'executando'
$$;

CREATE OR REPLACE FUNCTION f_pending_cancel(p_user bigint, p_id bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE v_run bigint;
BEGIN
  UPDATE pending_actions SET status = 'cancelada', resolvido_em = now()
   WHERE id = p_id AND user_id = p_user AND status = 'pendente' RETURNING run_id INTO v_run;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'text', 'Essa proposta já foi resolvida.'); END IF;
  RETURN jsonb_build_object('ok', true, 'run_id', v_run, 'text', 'Ok, não fiz nada.');
END $$;

-- ---------- 8) franquia ----------
CREATE TABLE IF NOT EXISTS usage_quota (
  user_id      bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  mes          date   NOT NULL,           -- primeiro dia do mes, no fuso do usuario
  analises     integer NOT NULL DEFAULT 0,
  analises_web integer NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, mes)
);
CREATE TABLE IF NOT EXISTS usage_daily (
  user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  dia     date   NOT NULL,
  msgs    integer NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, dia)
);

-- ---------- 9) modelo por papel ----------
CREATE TABLE IF NOT EXISTS ai_model_roles (
  papel    text PRIMARY KEY CHECK (papel IN ('simples', 'cruzada', 'visao', 'transcricao', 'revisao_semanal', 'forte')),
  modelo   text NOT NULL,
  provedor text NOT NULL DEFAULT 'openai'
);
INSERT INTO ai_model_roles (papel, modelo) VALUES
  ('simples', 'gpt-6-luna'), ('cruzada', 'gpt-6-luna'), ('visao', 'gpt-6-luna'),
  ('transcricao', 'gpt-transcribe'), ('revisao_semanal', 'gpt-6-luna'), ('forte', 'gpt-6.1-sol')
ON CONFLICT (papel) DO NOTHING;

-- API de busca propria do servico (preco por chamada; ajuste quando o fornecedor for escolhido: PRD, pendencia 7)
INSERT INTO ai_pricing (model, usd_per_1m_in, usd_per_1m_out, usd_brl, source, usd_per_call)
  SELECT 'tool:busca', 0, 0, (SELECT usd_brl FROM ai_pricing WHERE model = 'gpt-6-luna'),
         'estimativa inicial: mesmo valor de tool:web_search; ajustar ao contratar a API de busca', 0.01
ON CONFLICT (model) DO NOTHING;

-- ---------- 10) memoria: tipo criterio ----------
ALTER TABLE user_memory DROP CONSTRAINT IF EXISTS user_memory_tipo_check;
ALTER TABLE user_memory ADD CONSTRAINT user_memory_tipo_check CHECK (tipo IN ('habito', 'preferencia', 'fato', 'relacao', 'criterio'));

-- f_mem_add: criterios ficam fora da deteccao de duplicata e do teto de 40 fatos
CREATE OR REPLACE FUNCTION agente.f_mem_add(p_user bigint, p_texto text, p_tipo text DEFAULT 'fato', p_origem text DEFAULT 'ia') RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  v_txt text := left(btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')), 200);
  v_norm text; v_cur text; v_tipo text := f_mem_tipo(p_tipo); d user_memory%ROWTYPE; v_id bigint; v_ev int := 0; v_cap constant int := 40;
BEGIN
  IF NOT f_mem_sw(p_user, 'mem_enabled') THEN
    RETURN jsonb_build_object('ok', false, 'disabled', true, 'text', '');
  END IF;
  v_norm := f_norm(v_txt);
  IF length(v_norm) < 3 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vazio', 'text', '');
  END IF;
  DELETE FROM user_memory WHERE user_id = p_user AND NOT ativo AND coalesce(ultimo_uso, criado_em) < now() - interval '30 days';

  SELECT * INTO d FROM user_memory m
   WHERE m.user_id = p_user AND m.ativo AND m.tipo <> 'criterio'
     AND (m.norm = v_norm
          OR (length(v_norm) >= 10 AND length(m.norm) >= 10 AND (position(v_norm IN m.norm) > 0 OR position(m.norm IN v_norm) > 0))
          OR (SELECT count(*) FROM (SELECT unnest(string_to_array(m.norm, ' ')) INTERSECT SELECT unnest(string_to_array(v_norm, ' '))) i)::numeric
             / greatest((SELECT count(*) FROM (SELECT unnest(string_to_array(m.norm, ' ')) UNION SELECT unnest(string_to_array(v_norm, ' '))) u), 1) >= 0.8)
   ORDER BY m.id LIMIT 1;
  IF FOUND THEN
    UPDATE user_memory SET ultimo_uso = now(),
           texto = CASE WHEN length(v_txt) > length(texto) AND position(norm IN v_norm) > 0 THEN v_txt ELSE texto END,
           norm  = CASE WHEN length(v_txt) > length(texto) AND position(norm IN v_norm) > 0 THEN v_norm ELSE norm END
     WHERE id = d.id RETURNING id, texto INTO v_id, v_cur;
    RETURN jsonb_build_object('ok', true, 'duplicate', true, 'id', v_id, 'text', 'Já estava anotado: ' || v_cur);
  END IF;

  -- um fato que foi esquecido e volta a ser dito: reativa a linha antiga em vez de criar outra
  SELECT id INTO v_id FROM user_memory WHERE user_id = p_user AND NOT ativo AND norm = v_norm ORDER BY id DESC LIMIT 1;
  IF v_id IS NOT NULL THEN
    UPDATE user_memory SET ativo = true, texto = v_txt, tipo = v_tipo, origem = left(coalesce(p_origem, 'ia'), 30), ultimo_uso = now() WHERE id = v_id;
  ELSE
    INSERT INTO user_memory(user_id, texto, norm, tipo, origem) VALUES (p_user, v_txt, v_norm, v_tipo, left(coalesce(p_origem, 'ia'), 30)) RETURNING id INTO v_id;
  END IF;

  WITH over AS (
    SELECT id FROM user_memory WHERE user_id = p_user AND ativo AND tipo <> 'criterio' AND id <> v_id
     ORDER BY usos DESC, coalesce(ultimo_uso, criado_em) DESC, criado_em DESC OFFSET v_cap - 1)
  UPDATE user_memory SET ativo = false WHERE id IN (SELECT id FROM over);
  GET DIAGNOSTICS v_ev = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'duplicate', false, 'id', v_id, 'evicted', v_ev, 'tipo', v_tipo, 'text', 'Anotei: ' || v_txt);
END $$;

-- f_mem_relevant_txt: criterios nao entram na busca por palavras (vao sempre, por f_crit_txt)
CREATE OR REPLACE FUNCTION agente.f_mem_relevant_txt(p_user bigint, p_msg text, p_max int DEFAULT 8) RETURNS text
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE toks text[] := f_mem_tokens(p_msg); res text; ids bigint[]; v_max int := greatest(coalesce(p_max, 8), 1);
BEGIN
  IF NOT f_mem_sw(p_user, 'mem_enabled') THEN RETURN ''; END IF;
  WITH sc AS (
    SELECT m.id, m.texto, m.criado_em, m.ultimo_uso,
           (SELECT count(*) FROM unnest(toks) t WHERE strpos(' ' || m.norm || ' ', ' ' || t) > 0) AS s
      FROM user_memory m WHERE m.user_id = p_user AND m.ativo AND m.tipo <> 'criterio'),
  matched AS (SELECT * FROM sc WHERE s > 0 ORDER BY s DESC, greatest(criado_em, coalesce(ultimo_uso, criado_em)) DESC, id DESC LIMIT v_max),
  recent  AS (SELECT * FROM sc WHERE s = 0 ORDER BY greatest(criado_em, coalesce(ultimo_uso, criado_em)) DESC, id DESC
               LIMIT least(4, greatest(v_max - (SELECT count(*) FROM matched), 0))),
  u AS (SELECT 0 AS grp, row_number() OVER (ORDER BY s DESC, id DESC) AS ord, id, texto FROM matched
        UNION ALL
        SELECT 1, row_number() OVER (ORDER BY id DESC), id, texto FROM recent)
  SELECT string_agg('- ' || texto, E'\n' ORDER BY grp, ord), array_agg(id) FILTER (WHERE grp = 0) INTO res, ids FROM u;
  IF ids IS NOT NULL THEN
    UPDATE user_memory SET ultimo_uso = now(), usos = usos + 1 WHERE id = ANY (ids);
  END IF;
  RETURN coalesce(res, '');
END $$;

-- f_mem_list: rotulo do tipo criterio
CREATE OR REPLACE FUNCTION agente.f_mem_list(p_user bigint, p_filtro text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE
  fl text := f_norm(p_filtro); vp boolean := false; vl boolean := false; vm boolean := false; v_tipo text; v_q text;
  t text := ''; r record; n int; items jsonb := '[]'::jsonb; np int := 0; nl int := 0; nm int := 0; sec text;
BEGIN
  IF fl IN ('', 'tudo', 'todos', 'todas', 'tudo tudo') THEN vp := true; vl := true; vm := true;
  ELSIF fl IN ('pessoa', 'pessoas', 'contato', 'contatos', 'grupo', 'grupos') THEN vp := true;
  ELSIF fl IN ('lugar', 'lugares', 'local', 'locais') THEN vl := true;
  ELSIF fl IN ('memoria', 'memorias', 'anotacoes', 'anotacao') THEN vm := true;
  ELSIF fl IN ('habito', 'habitos', 'preferencia', 'preferencias', 'fato', 'fatos', 'relacao', 'relacoes', 'parentesco') THEN vm := true; v_tipo := f_mem_tipo(fl);
  ELSE vp := true; vl := true; vm := true; v_q := fl;
  END IF;

  IF vp THEN
    sec := '';
    FOR r IN SELECT c.name, c.email, c.relation FROM contacts c
              WHERE c.user_id = p_user AND (v_q IS NULL OR f_norm(c.name || ' ' || c.email || ' ' || c.relation || ' ' || array_to_string(c.aliases, ' ')) LIKE '%' || v_q || '%')
              ORDER BY c.favorite DESC, c.name LOOP
      np := np + 1;
      sec := sec || E'\n- ' || f_ct_disp(r.name) || CASE WHEN r.relation <> '' THEN ' (' || r.relation || ')' ELSE '' END || CASE WHEN r.email <> '' THEN ' - ' || r.email ELSE '' END;
    END LOOP;
    IF v_q IS NULL OR np > 0 THEN t := t || 'Pessoas (' || np || '):' || CASE WHEN np = 0 THEN E'\n- nenhuma' ELSE sec END || E'\n\n'; END IF;
  END IF;
  IF vl THEN
    sec := '';
    FOR r IN SELECT p.name, p.address FROM places p
              WHERE p.user_id = p_user AND (v_q IS NULL OR f_norm(p.name || ' ' || p.address || ' ' || array_to_string(p.aliases, ' ')) LIKE '%' || v_q || '%')
              ORDER BY p.name LOOP
      nl := nl + 1;
      sec := sec || E'\n- ' || f_ct_disp(r.name) || ': ' || CASE WHEN r.address <> '' THEN r.address ELSE 'sem endereço ainda' END;
    END LOOP;
    IF v_q IS NULL OR nl > 0 THEN t := t || 'Lugares (' || nl || '):' || CASE WHEN nl = 0 THEN E'\n- nenhum' ELSE sec END || E'\n\n'; END IF;
  END IF;
  IF vm THEN
    sec := '';
    FOR r IN SELECT m.id, m.tipo, m.texto FROM user_memory m
              WHERE m.user_id = p_user AND m.ativo AND (v_tipo IS NULL OR m.tipo = v_tipo) AND (v_q IS NULL OR m.norm LIKE '%' || v_q || '%')
              ORDER BY m.tipo, m.id LOOP
      nm := nm + 1;
      items := items || jsonb_build_array(jsonb_build_object('id', r.id, 'tipo', r.tipo, 'texto', r.texto));
      sec := sec || E'\n- #' || r.id || ' ' || r.texto || ' (' || CASE r.tipo WHEN 'habito' THEN 'hábito' WHEN 'preferencia' THEN 'preferência' WHEN 'relacao' THEN 'relação' WHEN 'criterio' THEN 'critério' ELSE 'fato' END || ')';
    END LOOP;
    IF v_q IS NULL OR nm > 0 THEN
      t := t || 'Memória' || CASE WHEN v_tipo IS NOT NULL THEN ' (' || v_tipo || ')' ELSE '' END || ' (' || nm || '):'
             || CASE WHEN nm = 0 THEN E'\n- nada ainda' ELSE sec END || E'\n\n';
    END IF;
  END IF;
  t := btrim(t, E'\n ');
  IF t = '' THEN t := 'Não achei nada com "' || btrim(p_filtro) || '".'; END IF;
  IF vm AND nm > 0 THEN t := t || E'\n\nPara apagar um fato: "esquece o #' || (items->0->>'id') || '" ou "esquece que ...".'; END IF;
  RETURN jsonb_build_object('text', t, 'total', np + nl + nm, 'pessoas', np, 'lugares', nl, 'memoria', nm, 'items', items,
                            'switches', f_mem_switches(p_user));
END $$;

-- Criterios de decisao: poucos (teto 15), sempre no contexto do agente.
CREATE OR REPLACE FUNCTION agente.f_crit_add(p_user bigint, p_texto text, p_origem text DEFAULT 'pedido') RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  v_txt text := left(btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')), 200);
  v_norm text; v_id bigint; n int; v_cap constant int := 15;
BEGIN
  IF NOT f_mem_sw(p_user, 'mem_enabled') THEN
    RETURN jsonb_build_object('ok', false, 'disabled', true, 'text', 'A memória está desligada. Diga "liga a memória" para eu guardar critérios.');
  END IF;
  v_norm := f_norm(v_txt);
  IF length(v_norm) < 3 THEN RETURN jsonb_build_object('ok', false, 'error', 'vazio', 'text', 'Qual é o critério?'); END IF;
  SELECT id INTO v_id FROM user_memory WHERE user_id = p_user AND ativo AND tipo = 'criterio' AND norm = v_norm LIMIT 1;
  IF v_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'duplicate', true, 'id', v_id, 'text', 'Já sigo esse critério: ' || v_txt);
  END IF;
  SELECT count(*) INTO n FROM user_memory WHERE user_id = p_user AND ativo AND tipo = 'criterio';
  IF n >= v_cap THEN
    RETURN jsonb_build_object('ok', false, 'error', 'teto', 'total', n,
      'text', 'Você já tem ' || n || ' critérios, que é o máximo. Veja com /memoria e apague um ("esquece o #id") antes de criar outro.');
  END IF;
  INSERT INTO user_memory (user_id, texto, norm, tipo, origem)
  VALUES (p_user, v_txt, v_norm, 'criterio', left(coalesce(p_origem, 'pedido'), 30)) RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'duplicate', false, 'id', v_id, 'text', 'Anotei o critério: ' || v_txt);
END $$;

CREATE OR REPLACE FUNCTION agente.f_crit_txt(p_user bigint) RETURNS text
LANGUAGE sql STABLE SET search_path TO 'agente', 'public' AS $$
  SELECT CASE WHEN NOT f_mem_sw(p_user, 'mem_enabled') THEN '' ELSE
    coalesce((SELECT string_agg('- ' || texto, E'\n' ORDER BY id) FROM user_memory
               WHERE user_id = p_user AND ativo AND tipo = 'criterio'), '') END
$$;
