-- Assessor (PRD RF-09): Vigia proativo. Regras fixas que cruzam areas e geram sinais. Sem IA. Idempotente.
-- NAO aplicado em producao. Os compromissos chegam em p_events (lista do Google, mesmo formato de f_agenda_manage:
-- [{id, title, start, end, all_day}]).
SET search_path = agente, public;

CREATE TABLE IF NOT EXISTS insight_prefs (
  user_id            bigint PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  modo               text NOT NULL DEFAULT 'normal' CHECK (modo IN ('quieto', 'normal', 'atento')),
  regras_silenciadas text[] NOT NULL DEFAULT '{}',   -- "nao me avise mais disso"
  regras_desligadas  text[] NOT NULL DEFAULT '{}',   -- desligadas sozinhas por rejeicao repetida
  ignorados_seguidos integer NOT NULL DEFAULT 0,
  atualizado_em      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS insights_log (
  id            bigserial PRIMARY KEY,
  user_id       bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  chave         text   NOT NULL,
  regra         text   NOT NULL,
  prioridade    text   NOT NULL CHECK (prioridade IN ('alta', 'normal')),
  texto         text   NOT NULL,
  acao          jsonb,
  via           text   NOT NULL CHECK (via IN ('resumo', 'imediato', 'revisao')),
  enviado_em    timestamptz NOT NULL DEFAULT now(),
  resposta      text CHECK (resposta IN ('aceito', 'agora_nao', 'silenciado', 'ignorado')),
  respondido_em timestamptz
);
CREATE INDEX IF NOT EXISTS insights_log_user ON insights_log (user_id, enviado_em DESC);
CREATE INDEX IF NOT EXISTS insights_log_key ON insights_log (user_id, chave, enviado_em DESC);

CREATE OR REPLACE FUNCTION f_insight_prefs(p_user bigint) RETURNS insight_prefs
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE p insight_prefs%ROWTYPE;
BEGIN
  SELECT * INTO p FROM insight_prefs WHERE user_id = p_user;
  IF NOT FOUND THEN
    INSERT INTO insight_prefs (user_id) VALUES (p_user) ON CONFLICT (user_id) DO NOTHING;
    SELECT * INTO p FROM insight_prefs WHERE user_id = p_user;
  END IF;
  RETURN p;
END $$;

-- Sinais candidatos (nao grava). Ja tira regra silenciada/desligada e chave enviada nos ultimos 30 dias.
CREATE OR REPLACE FUNCTION f_insights(p_user bigint, p_events jsonb DEFAULT '[]') RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE
  u users%ROWTYPE; today date; ps date; pe date; sp numeric; r record; r2 record;
  ev jsonb := CASE WHEN jsonb_typeof(p_events) = 'array' THEN p_events ELSE '[]'::jsonb END;
  out jsonb := '[]'; off text[]; sab date; n int; v_pct numeric; v_tit text; inc numeric; saldo numeric;
  s date; pv date; dd date; fechada numeric; lista text; v_norm text;
BEGIN
  SELECT * INTO u FROM users WHERE id = p_user;
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;
  today := f_fin_today(p_user);
  SELECT p_start, p_end INTO ps, pe FROM f_fin_period(p_user, 0);
  SELECT coalesce(regras_silenciadas, '{}') || coalesce(regras_desligadas, '{}') INTO off FROM insight_prefs WHERE user_id = p_user;
  off := coalesce(off, '{}');

  -- 1) lazer no fim de semana x orcamento de lazer
  IF NOT 'lazer_fim_de_semana' = ANY (off) THEN
    sab := today + ((6 - extract(dow FROM today)::int + 7) % 7);
    SELECT count(*), string_agg(x->>'title', ', ') INTO n, v_tit FROM jsonb_array_elements(ev) x
     WHERE (f_ag_ts(x->>'start') AT TIME ZONE u.timezone)::date IN (sab, sab + 1)
       AND f_norm(coalesce(x->>'title', '')) ~ '(jantar|almoco|festa|bar |bar$|cinema|show|churrasco|restaurante|aniversario|viagem|passeio|happy|balada|teatro|rodizio|pizza)';
    SELECT round(f_fin_spent(p_user, c.id, ps, pe) / c.budget * 100) INTO v_pct FROM fin_categories c
     WHERE c.user_id = p_user AND c.kind = 'expense' AND f_norm(c.name) = 'lazer' AND coalesce(c.budget, 0) > 0 LIMIT 1;
    IF n >= 2 AND coalesce(v_pct, 0) >= 80 THEN
      out := out || jsonb_build_object('chave', 'lazer:' || sab, 'regra', 'lazer_fim_de_semana', 'prioridade', 'normal',
        'texto', 'Seu fim de semana tem ' || n || ' programas (' || v_tit || ') e o orçamento de Lazer já está em ' || v_pct || '%.',
        'acao', NULL);
    END IF;
  END IF;

  -- 2) fatura fechada vencendo e o saldo do mes nao cobre
  IF NOT 'fatura_sem_saldo' = ANY (off) THEN
    SELECT coalesce(sum(amount), 0) INTO inc FROM fin_entries
     WHERE user_id = p_user AND kind = 'income' AND status = 'paid' AND occurred_on BETWEEN ps AND pe;
    inc := greatest(inc, coalesce(u.fin_income, 0));
    IF inc > 0 THEN
      sp := f_fin_total_spent(p_user, ps, pe);
      saldo := inc - sp;
      FOR r IN SELECT * FROM fin_cards WHERE user_id = p_user AND active LOOP
        s := f_card_close_le(r.closing_day, today);
        pv := f_card_close_le(r.closing_day, s - 1);
        dd := f_card_due_gt(r.due_day, s);
        fechada := f_card_sum(r.id, pv, s);
        IF fechada > 0 AND dd - today BETWEEN 0 AND 7 AND fechada > saldo THEN
          out := out || jsonb_build_object('chave', 'fatura:' || r.id || ':' || dd, 'regra', 'fatura_sem_saldo',
            'prioridade', CASE WHEN dd - today <= 1 THEN 'alta' ELSE 'normal' END,
            'texto', 'A fatura do ' || r.name || ' (' || f_brl(fechada) || ') vence em ' || to_char(dd, 'DD/MM')
                     || ' e o que sobrou do mês (' || f_brl(saldo) || ') não cobre.',
            'acao', NULL);
        END IF;
      END LOOP;
    END IF;
  END IF;

  -- 3) documento vencendo sem lembrete nem tarefa
  IF NOT 'documento_sem_lembrete' = ANY (off) THEN
    FOR r IN SELECT d.id, d.title, d.expires_on FROM documents d
              WHERE d.user_id = p_user AND d.expires_on BETWEEN today AND today + 30 AND d.reminder_id IS NULL
              ORDER BY d.expires_on LIMIT 5 LOOP
      v_norm := f_norm(r.title);
      CONTINUE WHEN EXISTS (SELECT 1 FROM reminders x WHERE x.user_id = p_user AND x.status = 'pending' AND length(v_norm) >= 4
                             AND position(v_norm IN f_norm(x.title)) > 0)
                 OR EXISTS (SELECT 1 FROM project_tasks x WHERE x.user_id = p_user AND NOT x.done AND length(v_norm) >= 4
                             AND position(v_norm IN x.norm_title) > 0);
      out := out || jsonb_build_object('chave', 'doc:' || r.id || ':' || r.expires_on, 'regra', 'documento_sem_lembrete',
        'prioridade', CASE WHEN r.expires_on - today <= 1 THEN 'alta' ELSE 'normal' END,
        'texto', '"' || r.title || '" vence em ' || to_char(r.expires_on, 'DD/MM') || ' (' || f_days_text(r.expires_on - today)
                 || ') e não há lembrete para isso.',
        'acao', jsonb_build_object('rotulo', 'Criar lembrete', 'ferramenta', 'lembretes', 'acao', 'criar',
          'args', jsonb_build_object('titulo', 'Renovar ' || r.title,
                                     'data', to_char(greatest(r.expires_on - 7, today + 1), 'YYYY-MM-DD'), 'hora', '09:00')));
    END LOOP;
  END IF;

  -- 4) item continuo acabando e fora da lista de compras
  IF NOT 'estoque_fora_da_lista' = ANY (off) THEN
    FOR r IN SELECT id, item, runs_out_on FROM supplies_status
              WHERE user_id = p_user AND status = 'active' AND runs_out_on IS NOT NULL AND runs_out_on BETWEEN today AND today + 7
              ORDER BY runs_out_on LIMIT 5 LOOP
      v_norm := f_norm(r.item);
      CONTINUE WHEN EXISTS (SELECT 1 FROM list_items li WHERE li.user_id = p_user AND NOT li.done
                             AND (position(v_norm IN li.name_norm) > 0 OR position(li.name_norm IN v_norm) > 0));
      SELECT l.name INTO lista FROM lists l WHERE l.user_id = p_user AND l.name_norm ~ '(mercado|compras|farmacia)'
       ORDER BY (l.name_norm ~ 'farmacia') DESC, l.id LIMIT 1;
      out := out || jsonb_build_object('chave', 'estoque:' || r.id || ':' || r.runs_out_on, 'regra', 'estoque_fora_da_lista',
        'prioridade', CASE WHEN r.runs_out_on - today <= 1 THEN 'alta' ELSE 'normal' END,
        'texto', initcap(left(r.item, 1)) || substr(r.item, 2) || ' acaba em ' || to_char(r.runs_out_on, 'DD/MM')
                 || ' e não está em nenhuma lista de compras.',
        'acao', jsonb_build_object('rotulo', 'Pôr na lista', 'ferramenta', 'listas_notas', 'acao', 'lista_adicionar',
          'args', jsonb_build_object('lista', coalesce(lista, 'compras'), 'itens', jsonb_build_array(r.item))));
    END LOOP;
  END IF;

  -- 5) prazo de projeto chegando com tarefas abertas
  IF NOT 'prazo_de_projeto' = ANY (off) THEN
    FOR r IN SELECT p.id, p.name, p.due_date, (SELECT count(*) FROM project_tasks x WHERE x.project_id = p.id AND NOT x.done) AS abertas
               FROM projects p WHERE p.user_id = p_user AND p.due_date BETWEEN today AND today + 7 ORDER BY p.due_date LIMIT 5 LOOP
      CONTINUE WHEN r.abertas = 0;
      out := out || jsonb_build_object('chave', 'proj:' || r.id || ':' || r.due_date, 'regra', 'prazo_de_projeto',
        'prioridade', CASE WHEN r.due_date - today <= 1 THEN 'alta' ELSE 'normal' END,
        'texto', 'O projeto ' || r.name || ' vence em ' || to_char(r.due_date, 'DD/MM') || ' (' || f_days_text(r.due_date - today)
                 || ') e ainda tem ' || r.abertas || ' tarefa(s) aberta(s).',
        'acao', NULL);
    END LOOP;
  END IF;

  -- 6) conflito de horario nos proximos 7 dias
  IF NOT 'conflito_de_agenda' = ANY (off) THEN
    FOR r IN
      SELECT a->>'id' AS ida, b->>'id' AS idb, a->>'title' AS ta, b->>'title' AS tb, f_ag_ts(a->>'start') AS sa
        FROM jsonb_array_elements(ev) a, jsonb_array_elements(ev) b
       WHERE (a->>'id') < (b->>'id')
         AND coalesce(a->>'all_day', 'false') <> 'true' AND coalesce(b->>'all_day', 'false') <> 'true'
         AND f_ag_ts(a->>'start') < f_ag_ts(b->>'end') AND f_ag_ts(b->>'start') < f_ag_ts(a->>'end')
         AND f_ag_ts(a->>'start') >= now() - interval '1 hour'
         AND (f_ag_ts(a->>'start') AT TIME ZONE u.timezone)::date <= today + 7
       ORDER BY f_ag_ts(a->>'start') LIMIT 3 LOOP
      out := out || jsonb_build_object('chave', 'conf:' || r.ida || ':' || r.idb, 'regra', 'conflito_de_agenda',
        'prioridade', CASE WHEN (r.sa AT TIME ZONE u.timezone)::date = today THEN 'alta' ELSE 'normal' END,
        'texto', '"' || r.ta || '" e "' || r.tb || '" estão no mesmo horário em ' || f_ag_fmt(r.sa, u.timezone) || '.',
        'acao', NULL);
    END LOOP;
  END IF;

  -- 7) limite geral do mes estourado
  IF NOT 'limite_estourado' = ANY (off) AND coalesce(u.fin_total_limit, 0) > 0 THEN
    sp := f_fin_total_spent(p_user, ps, pe);
    IF sp >= u.fin_total_limit THEN
      out := out || jsonb_build_object('chave', 'limite:' || ps, 'regra', 'limite_estourado', 'prioridade', 'alta',
        'texto', 'Você passou do limite do mês: gastou ' || f_brl(sp) || ' de ' || f_brl(u.fin_total_limit) || '.', 'acao', NULL);
    END IF;
  END IF;

  -- a mesma chave nao volta em 30 dias; prioridade alta primeiro
  RETURN coalesce((
    SELECT jsonb_agg(x ORDER BY (x->>'prioridade' = 'alta') DESC, x->>'chave')
      FROM jsonb_array_elements(out) x
     WHERE NOT EXISTS (SELECT 1 FROM insights_log l WHERE l.user_id = p_user AND l.chave = x->>'chave'
                                                      AND l.enviado_em > now() - interval '30 days')), '[]'::jsonb);
END $$;

-- Escolhe e registra os sinais a enviar por uma via, respeitando modo, tetos e expediente.
CREATE OR REPLACE FUNCTION f_insights_pick(p_user bigint, p_events jsonb, p_via text) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE
  u users%ROWTYPE; p insight_prefs%ROWTYPE; cand jsonb; lim int := 0; x jsonb; out jsonb := '[]'; v_id bigint;
  agora time; hoje_ini timestamptz; ja int;
BEGIN
  SELECT * INTO u FROM users WHERE id = p_user;
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;
  p := f_insight_prefs(p_user);
  IF p_via = 'resumo' THEN
    lim := CASE WHEN p.ignorados_seguidos >= 5 THEN 0 WHEN p.modo = 'quieto' THEN 0 WHEN p.modo = 'atento' THEN 4 ELSE 2 END;
  ELSIF p_via = 'imediato' THEN
    agora := (now() AT TIME ZONE u.timezone)::time;
    IF agora < u.work_start OR agora > u.work_end THEN RETURN '[]'::jsonb; END IF;
    hoje_ini := (f_fin_today(p_user)::timestamp AT TIME ZONE u.timezone);
    SELECT count(*) INTO ja FROM insights_log WHERE user_id = p_user AND via = 'imediato' AND enviado_em >= hoje_ini;
    lim := CASE WHEN p.ignorados_seguidos >= 5 THEN 0 WHEN p.modo = 'quieto' THEN 0 WHEN p.modo = 'atento' THEN 2 ELSE 1 END - ja;
  ELSIF p_via = 'revisao' THEN
    lim := 6;
  ELSE
    RETURN '[]'::jsonb;
  END IF;
  IF lim <= 0 THEN RETURN '[]'::jsonb; END IF;
  cand := f_insights(p_user, p_events);
  FOR x IN SELECT * FROM jsonb_array_elements(cand) LOOP
    EXIT WHEN lim <= 0;
    CONTINUE WHEN p_via = 'imediato' AND x->>'prioridade' <> 'alta';
    INSERT INTO insights_log (user_id, chave, regra, prioridade, texto, acao, via)
    VALUES (p_user, x->>'chave', x->>'regra', x->>'prioridade', x->>'texto', NULLIF(x->'acao', 'null'::jsonb), p_via)
    RETURNING id INTO v_id;
    out := out || (x || jsonb_build_object('id', v_id));
    lim := lim - 1;
  END LOOP;
  RETURN out;
END $$;

-- Resposta do usuario a um aviso: aceito | agora_nao | silenciado.
CREATE OR REPLACE FUNCTION f_insight_answer(p_user bigint, p_id bigint, p_resp text) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE l insights_log%ROWTYPE;
BEGIN
  IF p_resp NOT IN ('aceito', 'agora_nao', 'silenciado') THEN RETURN jsonb_build_object('ok', false, 'text', 'Não entendi.'); END IF;
  UPDATE insights_log SET resposta = p_resp, respondido_em = now()
   WHERE id = p_id AND user_id = p_user AND (resposta IS NULL OR resposta = 'ignorado') RETURNING * INTO l;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'text', 'Esse aviso já foi respondido.'); END IF;
  PERFORM f_insight_prefs(p_user);
  UPDATE insight_prefs SET ignorados_seguidos = 0, atualizado_em = now(),
         regras_silenciadas = CASE WHEN p_resp = 'silenciado' AND NOT l.regra = ANY (regras_silenciadas)
                                   THEN regras_silenciadas || l.regra ELSE regras_silenciadas END
   WHERE user_id = p_user;
  RETURN jsonb_build_object('ok', true, 'regra', l.regra, 'resposta', p_resp, 'acao', l.acao,
    'text', CASE p_resp WHEN 'silenciado' THEN 'Combinado, não aviso mais sobre isso. Para voltar, diga "volta a me avisar de tudo".'
                        WHEN 'agora_nao' THEN 'Tudo bem.' ELSE '' END);
END $$;

-- Marca como ignorado o que ficou 24 h sem clique e desliga regra muito rejeitada. Roda no agendador.
CREATE OR REPLACE FUNCTION f_insights_expire(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE n int; r record; desl text[] := '{}';
BEGIN
  WITH upd AS (
    UPDATE insights_log SET resposta = 'ignorado', respondido_em = now()
     WHERE user_id = p_user AND resposta IS NULL AND via <> 'revisao' AND enviado_em < now() - interval '24 hours' RETURNING 1)
  SELECT count(*) INTO n FROM upd;
  PERFORM f_insight_prefs(p_user);
  IF n > 0 THEN
    UPDATE insight_prefs SET ignorados_seguidos = ignorados_seguidos + n, atualizado_em = now() WHERE user_id = p_user;
  END IF;
  FOR r IN SELECT regra FROM insights_log
            WHERE user_id = p_user AND enviado_em > now() - interval '30 days'
            GROUP BY regra
           HAVING count(*) FILTER (WHERE resposta IN ('agora_nao', 'silenciado')) >= 3 AND count(*) FILTER (WHERE resposta = 'aceito') = 0 LOOP
    desl := desl || r.regra;
  END LOOP;
  IF array_length(desl, 1) > 0 THEN
    UPDATE insight_prefs SET regras_desligadas = (SELECT array_agg(DISTINCT x) FROM unnest(regras_desligadas || desl) x), atualizado_em = now()
     WHERE user_id = p_user;
  END IF;
  RETURN jsonb_build_object('ignorados', n, 'desligadas', to_jsonb(desl));
END $$;

CREATE OR REPLACE FUNCTION f_insight_mode(p_user bigint, p_modo text) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE m text := f_norm(p_modo);
BEGIN
  PERFORM f_insight_prefs(p_user);
  IF m IN ('todos', 'tudo', 'religar', 'reativar') THEN
    UPDATE insight_prefs SET regras_silenciadas = '{}', regras_desligadas = '{}', ignorados_seguidos = 0, atualizado_em = now() WHERE user_id = p_user;
    RETURN jsonb_build_object('ok', true, 'text', 'Voltei a avisar de tudo.');
  END IF;
  IF m NOT IN ('quieto', 'normal', 'atento') THEN
    RETURN jsonb_build_object('ok', false, 'text', 'Os modos são: quieto, normal ou atento.');
  END IF;
  UPDATE insight_prefs SET modo = m, ignorados_seguidos = 0, atualizado_em = now() WHERE user_id = p_user;
  RETURN jsonb_build_object('ok', true, 'modo', m, 'text', CASE m
    WHEN 'quieto' THEN 'Modo quieto: só a revisão da semana.'
    WHEN 'atento' THEN 'Modo atento: até 4 avisos no resumo da manhã e 2 imediatos por dia.'
    ELSE 'Modo normal: até 2 avisos no resumo da manhã e 1 imediato por dia.' END);
END $$;
