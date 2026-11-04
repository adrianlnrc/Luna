-- Fase 8: importar agenda de papel por foto (compromissos -> Google Agenda, tarefas -> Google Tarefas)
-- Fluxo: a IA le a foto (n8n) -> f_agimp_create guarda um RASCUNHO numerado -> o usuario confere, corrige por texto
-- (f_agimp_edit) ou por botao -> f_agimp_cb (aiok/aino) devolve o pacote 'imp' -> sub-workflow cria no Google -> f_agimp_done.
-- Nao guarda a imagem: so titulos, dias e horarios (texto). Rascunhos com mais de 30 dias sao apagados ao criar um novo.
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE).
SET search_path TO agente, public;

CREATE TABLE IF NOT EXISTS agenda_import (
  id          bigserial PRIMARY KEY,
  user_id     bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  calendar_key text,
  week_start  date,
  items       jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{n,kind:'event'|'task',day,start,end,title,urgent,uncertain,skip}]
  notes       jsonb NOT NULL DEFAULT '[]'::jsonb,   -- avisos da leitura ("nao consegui ler a quinta")
  state       text NOT NULL DEFAULT 'open' CHECK (state IN ('open','running','done','cancelled')),
  result      jsonb,
  created_at  timestamptz NOT NULL DEFAULT now(),
  done_at     timestamptz
);
CREATE INDEX IF NOT EXISTS agenda_import_user_open ON agenda_import (user_id, id DESC) WHERE state IN ('open','running');

-- ---------- utilitarios ----------
CREATE OR REPLACE FUNCTION f_agimp_dow(p_d date) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT (ARRAY['Domingo','Segunda','Terça','Quarta','Quinta','Sexta','Sábado'])[extract(dow FROM p_d)::int + 1]
$$;

-- data + HH:MM no fuso da pessoa -> ISO com deslocamento (ex.: 2026-11-02T13:00:00-03:00)
CREATE OR REPLACE FUNCTION f_agimp_iso(p_day date, p_hm text, p_tz text) RETURNS text
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE l timestamp := p_day::timestamp + p_hm::time; u timestamp; mins int;
BEGIN
  u := (l AT TIME ZONE coalesce(nullif(p_tz, ''), 'America/Sao_Paulo')) AT TIME ZONE 'UTC';
  mins := (extract(epoch FROM (l - u)) / 60)::int;
  RETURN to_char(l, 'YYYY-MM-DD"T"HH24:MI:SS') || CASE WHEN mins < 0 THEN '-' ELSE '+' END
    || lpad((abs(mins) / 60)::text, 2, '0') || ':' || lpad((abs(mins) % 60)::text, 2, '0');
END $$;

-- ---------- texto do rascunho ----------
CREATE OR REPLACE FUNCTION f_agimp_render(p_id bigint) RETURNS text
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE r agenda_import; it jsonb; v text; last_day date; d date; n_ev int := 0; n_tk int := 0; tks text := ''; nt text := '';
BEGIN
  SELECT * INTO r FROM agenda_import WHERE id = p_id;
  IF NOT FOUND THEN RETURN ''; END IF;
  SELECT count(*) FILTER (WHERE x.e->>'kind' = 'event'), count(*) FILTER (WHERE x.e->>'kind' = 'task')
    INTO n_ev, n_tk FROM jsonb_array_elements(r.items) AS x(e) WHERE coalesce((x.e->>'skip')::boolean, false) = false;
  v := 'Li sua agenda' || CASE WHEN r.week_start IS NOT NULL THEN ' da semana de ' || to_char(r.week_start, 'DD/MM') || ' a ' || to_char(r.week_start + 6, 'DD/MM/YYYY') ELSE '' END
    || '. Confira antes de eu criar: ' || n_ev || ' compromisso(s) no Google Agenda e ' || n_tk || ' tarefa(s) no Google Tarefas.' || E'\n';
  FOR it IN SELECT x.e FROM jsonb_array_elements(r.items) AS x(e)
            WHERE x.e->>'kind' = 'event' AND coalesce((x.e->>'skip')::boolean, false) = false
            ORDER BY x.e->>'day', x.e->>'start' LOOP
    d := (it->>'day')::date;
    IF last_day IS DISTINCT FROM d THEN
      v := v || E'\n' || f_agimp_dow(d) || ' ' || to_char(d, 'DD/MM') || E'\n';
      last_day := d;
    END IF;
    v := v || (it->>'n') || '. ' || (it->>'start') || '–' || (it->>'end') || ' ' || (it->>'title')
      || CASE WHEN coalesce((it->>'uncertain')::boolean, false) THEN ' (?)' ELSE '' END || E'\n';
  END LOOP;
  FOR it IN SELECT x.e FROM jsonb_array_elements(r.items) AS x(e)
            WHERE x.e->>'kind' = 'task' AND coalesce((x.e->>'skip')::boolean, false) = false
            ORDER BY x.e->>'day', (x.e->>'n')::int LOOP
    d := (it->>'day')::date;
    tks := tks || (it->>'n') || '. ' || CASE WHEN coalesce((it->>'urgent')::boolean, false) THEN '🔴 ' ELSE '' END || (it->>'title')
      || ' (' || f_agimp_dow(d) || ' ' || to_char(d, 'DD/MM') || ')'
      || CASE WHEN coalesce((it->>'uncertain')::boolean, false) THEN ' (?)' ELSE '' END || E'\n';
  END LOOP;
  IF tks <> '' THEN v := v || E'\nTarefas\n' || tks; END IF;
  SELECT string_agg('- ' || n, E'\n') INTO nt FROM jsonb_array_elements_text(r.notes) AS n;
  IF coalesce(nt, '') <> '' THEN v := v || E'\nNão consegui ler direito:\n' || nt || E'\n'; END IF;
  v := v || E'\nItens com (?) são os que eu li com dúvida. Para corrigir, escreva por exemplo "o 3 é na segunda", "o 4 termina às 16h" ou "tira o 5". Para criar, toque em Criar tudo.';
  RETURN v;
END $$;

-- ---------- criar rascunho a partir da leitura da IA ----------
-- p_x = {week_start, items:[{day,start,end,title,kind,urgent,uncertain}], notes:[texto]}
CREATE OR REPLACE FUNCTION f_agimp_create(p_user bigint, p_x jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE v_cal text; e jsonb; v_items jsonb := '[]'::jsonb; n int := 0; v_day date; k text; v_id bigint; v_week date; v_notes jsonb;
BEGIN
  SELECT calendar_key INTO v_cal FROM users WHERE id = p_user;
  IF coalesce(v_cal, '') = '' THEN
    RETURN jsonb_build_object('text', 'Ainda não tenho o seu Google conectado, então não consigo criar eventos nem tarefas. Fale com o Adrian para ligar a sua conta.', 'kb', 'none', 'rid', 0);
  END IF;
  FOR e IN SELECT x FROM jsonb_array_elements(coalesce(p_x->'items', '[]'::jsonb)) AS x LOOP
    BEGIN v_day := (e->>'day')::date; EXCEPTION WHEN others THEN CONTINUE; END;
    IF v_day IS NULL THEN CONTINUE; END IF;
    k := CASE WHEN e->>'kind' = 'task' THEN 'task' ELSE 'event' END;
    IF k = 'event' AND NOT (coalesce(e->>'start', '') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' AND coalesce(e->>'end', '') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' AND (e->>'end') > (e->>'start')) THEN
      k := 'task';
    END IF;
    n := n + 1;
    v_items := v_items || jsonb_build_array(jsonb_build_object('n', n, 'kind', k, 'day', v_day,
      'start', CASE WHEN k = 'event' THEN e->>'start' END, 'end', CASE WHEN k = 'event' THEN e->>'end' END,
      'title', left(coalesce(nullif(trim(e->>'title'), ''), 'Compromisso'), 120),
      'urgent', coalesce((e->>'urgent')::boolean, false), 'uncertain', coalesce((e->>'uncertain')::boolean, false)));
  END LOOP;
  IF n = 0 THEN
    RETURN jsonb_build_object('text', 'Não consegui ler compromissos nessa foto. Tente de novo com a página inteira, bem iluminada e sem reflexo.', 'kb', 'none', 'rid', 0);
  END IF;
  BEGIN v_week := (p_x->>'week_start')::date; EXCEPTION WHEN others THEN v_week := NULL; END;
  v_notes := CASE WHEN jsonb_typeof(p_x->'notes') = 'array' THEN p_x->'notes' ELSE '[]'::jsonb END;
  DELETE FROM agenda_import WHERE user_id = p_user AND created_at < now() - interval '30 days';
  UPDATE agenda_import SET state = 'cancelled' WHERE user_id = p_user AND state = 'open';
  INSERT INTO agenda_import (user_id, calendar_key, week_start, items, notes) VALUES (p_user, v_cal, v_week, v_items, v_notes) RETURNING id INTO v_id;
  RETURN jsonb_build_object('text', f_agimp_render(v_id), 'kb', 'agimp', 'rid', v_id);
END $$;

-- ---------- confirmar: devolve o pacote para o sub-workflow criar no Google ----------
CREATE OR REPLACE FUNCTION f_agimp_confirm(p_user bigint, p_id bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE r agenda_import; v_tz text; ev jsonb; tk jsonb;
BEGIN
  UPDATE agenda_import SET state = 'running' WHERE id = p_id AND user_id = p_user AND state = 'open' RETURNING * INTO r;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('text', 'Essa importação já foi processada ou cancelada. Se precisar, mande a foto de novo.', 'kb', 'none', 'rid', 0);
  END IF;
  SELECT coalesce(timezone, 'America/Sao_Paulo') INTO v_tz FROM users WHERE id = p_user;
  SELECT coalesce(jsonb_agg(jsonb_build_object('summary', x.e->>'title', 'start', f_agimp_iso((x.e->>'day')::date, x.e->>'start', v_tz), 'end', f_agimp_iso((x.e->>'day')::date, x.e->>'end', v_tz))
         ORDER BY x.e->>'day', x.e->>'start'), '[]'::jsonb) INTO ev
    FROM jsonb_array_elements(r.items) AS x(e) WHERE x.e->>'kind' = 'event' AND coalesce((x.e->>'skip')::boolean, false) = false;
  SELECT coalesce(jsonb_agg(jsonb_build_object('title', CASE WHEN coalesce((x.e->>'urgent')::boolean, false) THEN '🔴 ' ELSE '' END || (x.e->>'title'), 'due', x.e->>'day')
         ORDER BY x.e->>'day', (x.e->>'n')::int), '[]'::jsonb) INTO tk
    FROM jsonb_array_elements(r.items) AS x(e) WHERE x.e->>'kind' = 'task' AND coalesce((x.e->>'skip')::boolean, false) = false;
  RETURN jsonb_build_object('text', 'Criando no seu Google...', 'kb', 'none', 'rid', 0,
    'imp', jsonb_build_object('draft_id', p_id, 'calendar_key', r.calendar_key, 'events', ev, 'tasks', tk));
END $$;

-- ---------- corrigir o rascunho por texto ----------
-- p_x = {act:'edit'|'remove'|'confirm'|'cancel', n, title, date, time, end, kind}
CREATE OR REPLACE FUNCTION f_agimp_edit(p_user bigint, p_x jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE r agenda_import; v_act text := coalesce(p_x->>'act', ''); v_n int; v_item jsonb; v_new jsonb; v_vis int; v_title text; v_date date; v_start text; v_end text;
        v_dur int; v_kind text;
BEGIN
  SELECT * INTO r FROM agenda_import WHERE user_id = p_user AND state = 'open' ORDER BY id DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('text', 'Não tenho nenhuma importação de agenda em aberto. Mande a foto da agenda que eu leio de novo.', 'kb', 'none', 'rid', 0);
  END IF;
  IF v_act = 'cancel' THEN
    UPDATE agenda_import SET state = 'cancelled' WHERE id = r.id;
    RETURN jsonb_build_object('text', 'Importação cancelada. Nada foi criado.', 'kb', 'none', 'rid', 0);
  END IF;
  IF v_act = 'confirm' THEN RETURN f_agimp_confirm(p_user, r.id); END IF;
  IF p_x->>'n' ~ '^[0-9]+$' THEN v_n := (p_x->>'n')::int; END IF;
  SELECT count(*) INTO v_vis FROM jsonb_array_elements(r.items) AS x(e) WHERE coalesce((x.e->>'skip')::boolean, false) = false;
  IF v_n IS NULL AND v_vis = 1 THEN
    SELECT (x.e->>'n')::int INTO v_n FROM jsonb_array_elements(r.items) AS x(e) WHERE coalesce((x.e->>'skip')::boolean, false) = false;
  END IF;
  IF v_n IS NULL THEN
    RETURN jsonb_build_object('text', 'Qual item você quer corrigir? Diga o número, por exemplo "o 3 é na segunda".' || E'\n\n' || f_agimp_render(r.id), 'kb', 'agimp', 'rid', r.id);
  END IF;
  SELECT x.e INTO v_item FROM jsonb_array_elements(r.items) AS x(e) WHERE (x.e->>'n')::int = v_n AND coalesce((x.e->>'skip')::boolean, false) = false;
  IF v_item IS NULL THEN
    RETURN jsonb_build_object('text', 'Não achei o item ' || v_n || ' na lista.' || E'\n\n' || f_agimp_render(r.id), 'kb', 'agimp', 'rid', r.id);
  END IF;
  v_new := v_item;
  IF v_act = 'remove' THEN
    v_new := jsonb_set(v_new, '{skip}', 'true'::jsonb);
  ELSE
    v_title := nullif(trim(coalesce(p_x->>'title', '')), '');
    IF v_title IS NOT NULL THEN v_new := jsonb_set(v_new, '{title}', to_jsonb(left(v_title, 120))); END IF;
    BEGIN v_date := nullif(p_x->>'date', '')::date; EXCEPTION WHEN others THEN v_date := NULL; END;
    IF v_date IS NOT NULL THEN v_new := jsonb_set(v_new, '{day}', to_jsonb(v_date)); END IF;
    v_kind := CASE WHEN p_x->>'kind' IN ('event', 'task') THEN p_x->>'kind' ELSE v_item->>'kind' END;
    v_start := CASE WHEN coalesce(p_x->>'time', '') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN p_x->>'time' END;
    v_end := CASE WHEN coalesce(p_x->>'end', '') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN p_x->>'end' END;
    IF v_kind = 'task' THEN
      v_new := jsonb_set(jsonb_set(jsonb_set(v_new, '{kind}', '"task"'::jsonb), '{start}', 'null'::jsonb), '{end}', 'null'::jsonb);
    ELSE
      IF v_item->>'kind' = 'event' THEN
        v_dur := greatest(15, (extract(epoch FROM ((v_item->>'end')::time - (v_item->>'start')::time)) / 60)::int);
        IF v_start IS NOT NULL AND v_end IS NULL THEN
          v_end := to_char(least((v_start::time + make_interval(mins => v_dur)), time '23:59'), 'HH24:MI');
        END IF;
        v_start := coalesce(v_start, v_item->>'start'); v_end := coalesce(v_end, v_item->>'end');
      ELSE
        -- tarefa virando compromisso: precisa de hora de inicio
        IF v_start IS NULL THEN
          RETURN jsonb_build_object('text', 'Para virar compromisso eu preciso da hora. Diga, por exemplo, "o ' || v_n || ' é às 14h".' || E'\n\n' || f_agimp_render(r.id), 'kb', 'agimp', 'rid', r.id);
        END IF;
        v_end := coalesce(v_end, to_char(least((v_start::time + interval '1 hour'), time '23:59'), 'HH24:MI'));
        v_new := jsonb_set(v_new, '{kind}', '"event"'::jsonb);
      END IF;
      IF v_end <= v_start THEN
        RETURN jsonb_build_object('text', 'O fim precisa ser depois do início. Diga de novo o horário do item ' || v_n || '.' || E'\n\n' || f_agimp_render(r.id), 'kb', 'agimp', 'rid', r.id);
      END IF;
      v_new := jsonb_set(jsonb_set(v_new, '{start}', to_jsonb(v_start)), '{end}', to_jsonb(v_end));
    END IF;
    v_new := jsonb_set(v_new, '{uncertain}', 'false'::jsonb);
  END IF;
  UPDATE agenda_import SET items = (
    SELECT jsonb_agg(CASE WHEN (x.e->>'n')::int = v_n THEN v_new ELSE x.e END ORDER BY ord)
      FROM jsonb_array_elements(items) WITH ORDINALITY AS x(e, ord)) WHERE id = r.id;
  RETURN jsonb_build_object('text', CASE WHEN v_act = 'remove' THEN 'Tirei o item ' || v_n || '.' ELSE 'Corrigi o item ' || v_n || '.' END || E'\n\n' || f_agimp_render(r.id), 'kb', 'agimp', 'rid', r.id);
END $$;

-- ---------- depois de criar no Google ----------
-- p_res = {events_ok, events_fail, tasks_ok, tasks_fail, errors:[texto]}
CREATE OR REPLACE FUNCTION f_agimp_done(p_user bigint, p_id bigint, p_res jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE eo int := coalesce((p_res->>'events_ok')::int, 0); ef int := coalesce((p_res->>'events_fail')::int, 0);
        tko int := coalesce((p_res->>'tasks_ok')::int, 0); tkf int := coalesce((p_res->>'tasks_fail')::int, 0); v text; errs text;
BEGIN
  IF eo + tko = 0 THEN
    UPDATE agenda_import SET state = 'open', result = p_res WHERE id = p_id AND user_id = p_user AND state = 'running';
    SELECT string_agg('- ' || left(x, 120), E'\n') INTO errs FROM (SELECT jsonb_array_elements_text(coalesce(p_res->'errors', '[]'::jsonb)) AS x LIMIT 3) q;
    RETURN jsonb_build_object('text', 'Não consegui criar nada no seu Google agora.' || CASE WHEN coalesce(errs, '') <> '' THEN E'\n' || errs ELSE '' END || E'\nToque em Criar tudo para tentar de novo.', 'kb', 'agimp', 'rid', p_id);
  END IF;
  UPDATE agenda_import SET state = 'done', result = p_res, done_at = now() WHERE id = p_id AND user_id = p_user;
  v := 'Pronto! Criei ' || eo || ' compromisso(s) no Google Agenda e ' || tko || ' tarefa(s) no Google Tarefas.';
  IF ef + tkf > 0 THEN
    SELECT string_agg('- ' || left(x, 120), E'\n') INTO errs FROM (SELECT jsonb_array_elements_text(coalesce(p_res->'errors', '[]'::jsonb)) AS x LIMIT 3) q;
    v := v || E'\nNão consegui criar ' || (ef + tkf) || ' item(ns).' || CASE WHEN coalesce(errs, '') <> '' THEN E'\n' || errs ELSE '' END;
  END IF;
  v := v || E'\nSe algo ficou errado, me diga que eu ajusto.';
  RETURN jsonb_build_object('text', v, 'kb', 'none', 'rid', 0);
END $$;

-- ---------- botoes: aiok:<id> (criar tudo), aino:<id> (cancelar) ----------
CREATE OR REPLACE FUNCTION f_agimp_cb(p_user bigint, p_data text) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE a text := split_part(p_data, ':', 1); v_id bigint := CASE WHEN split_part(p_data, ':', 2) ~ '^[0-9]+$' THEN split_part(p_data, ':', 2)::bigint END;
BEGIN
  IF v_id IS NULL OR NOT EXISTS (SELECT 1 FROM agenda_import WHERE id = v_id AND user_id = p_user) THEN
    RETURN jsonb_build_object('text', 'Não achei essa importação. Mande a foto da agenda de novo.', 'kb', 'none', 'rid', 0);
  END IF;
  IF a = 'aino' THEN
    UPDATE agenda_import SET state = 'cancelled' WHERE id = v_id AND user_id = p_user AND state = 'open';
    RETURN jsonb_build_object('text', 'Importação cancelada. Nada foi criado.', 'kb', 'none', 'rid', 0);
  END IF;
  RETURN f_agimp_confirm(p_user, v_id);
END $$;

-- ---------- despachante: f_callback ganha o prefixo ai* (resto igual a versao viva em 01/11/2026) ----------
CREATE OR REPLACE FUNCTION f_callback(p_user bigint, p_data text) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE a text := split_part(p_data, ':', 1); v_id bigint := CASE WHEN split_part(p_data, ':', 2) ~ '^[0-9]+$' THEN split_part(p_data, ':', 2)::bigint END; res jsonb; al text := '';
BEGIN
  IF a IN ('aiok', 'aino') THEN
    RETURN f_agimp_cb(p_user, p_data);
  END IF;
  IF a = 'fedit' THEN
    RETURN f_fin_edit_cb(p_user, coalesce(v_id, 0));
  END IF;
  IF a = 'fundo' AND v_id IS NOT NULL AND EXISTS (SELECT 1 FROM fin_entries WHERE id = v_id AND user_id = p_user) AND f_fin_expired(v_id) THEN
    RETURN jsonb_build_object('text', 'Esse lançamento já passou de 24h; diga o que corrigir, por exemplo: corrige o gasto do mercado de ontem para 50', 'kb', 'none');
  END IF;
  res := f_callback_pre_m2(p_user, p_data);
  IF a = 'fok' AND v_id IS NOT NULL AND res->>'kb' = 'fin_undo' THEN
    UPDATE fin_entries SET created_at = now() WHERE id = v_id AND user_id = p_user AND status IN ('paid', 'pending');
    BEGIN al := f_fin_alerts(p_user, v_id); EXCEPTION WHEN others THEN al := ''; END;
    res := jsonb_set(res, '{text}', to_jsonb((res->>'text') || al));
    res := jsonb_set(res, '{kb}', '"fin_recibo"'::jsonb);
  END IF;
  RETURN res;
END $$;
