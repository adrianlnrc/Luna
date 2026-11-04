-- Fase 9: resumo do dia enxuto, importacao de agenda sem ruido.
--  * blocos que se repetem no mesmo horario em 2+ dias viram "fixos" (criados SEM aviso; "sem os fixos" descarta)
--  * notas soltas (feriado etc.) nao viram tarefa: vao para "Nao importei"
--  * tarefas de dias futuros ficam guardadas (agenda_tarefas_agendadas) e so sao criadas no Google no dia, no resumo da manha
--  * resumo: f_summary_data deixa de trazer o bloco de projetos do banco; avisa o prazo do projeto (hoje/amanha)
-- Idempotente. Depende de 017, 022, 026, 031.
SET search_path TO agente, public;

CREATE TABLE IF NOT EXISTS agenda_tarefas_agendadas (
  id         bigserial PRIMARY KEY,
  user_id    bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  draft_id   bigint NOT NULL,
  n          int NOT NULL,
  title      text NOT NULL,
  due        date NOT NULL,
  urgent     boolean NOT NULL DEFAULT false,
  state      text NOT NULL DEFAULT 'scheduled' CHECK (state IN ('scheduled','created')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (draft_id, n)
);
CREATE INDEX IF NOT EXISTS agenda_tarefas_ag_due ON agenda_tarefas_agendadas (user_id, due) WHERE state = 'scheduled';

-- ---------- marca "fixos": mesmo titulo + mesmo inicio/fim em 2+ dias distintos ----------
CREATE OR REPLACE FUNCTION f_agimp_mark_fixed(p_items jsonb) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  WITH it AS (
    SELECT x.e, x.ord, lower(trim(x.e->>'title')) AS t, x.e->>'start' AS s, x.e->>'end' AS en
      FROM jsonb_array_elements(p_items) WITH ORDINALITY AS x(e, ord)
  ), g AS (
    SELECT t, s, en FROM it WHERE it.e->>'kind' = 'event'
     GROUP BY t, s, en HAVING count(DISTINCT it.e->>'day') >= 2
  )
  SELECT coalesce(jsonb_agg(CASE WHEN it.e->>'kind' = 'event' AND EXISTS (SELECT 1 FROM g WHERE g.t = it.t AND g.s = it.s AND g.en = it.en)
                                 THEN jsonb_set(it.e, '{fixed}', 'true'::jsonb) ELSE jsonb_set(it.e, '{fixed}', 'false'::jsonb) END ORDER BY it.ord), '[]'::jsonb)
    FROM it
$$;

-- "ter a sex" / "seg, qua" a partir de uma lista de datas
CREATE OR REPLACE FUNCTION f_agimp_days_label(p_days date[]) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path TO 'agente','public' AS $$
DECLARE ab text[] := ARRAY['dom','seg','ter','qua','qui','sex','sáb']; ds int[]; i int; r text := ''; run_start int; prev int; contiguous boolean := true;
BEGIN
  SELECT array_agg(DISTINCT extract(dow FROM d)::int ORDER BY extract(dow FROM d)::int) INTO ds FROM unnest(p_days) d;
  FOR i IN 2..coalesce(array_length(ds, 1), 0) LOOP
    IF ds[i] <> ds[i-1] + 1 THEN contiguous := false; END IF;
  END LOOP;
  IF array_length(ds, 1) >= 3 AND contiguous THEN
    RETURN ab[ds[1] + 1] || ' a ' || ab[ds[array_length(ds, 1)] + 1];
  END IF;
  SELECT string_agg(ab[x + 1], ', ' ORDER BY x) INTO r FROM unnest(ds) x;
  RETURN coalesce(r, '');
END $$;

-- ---------- texto do rascunho (fixos agrupados, "nao importei") ----------
CREATE OR REPLACE FUNCTION f_agimp_render(p_id bigint) RETURNS text
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE r agenda_import; it jsonb; v text; last_day date; d date; n_ev int := 0; n_tk int := 0; n_fx int := 0; tks text := ''; nt text := ''; fx text := ''; g record;
BEGIN
  SELECT * INTO r FROM agenda_import WHERE id = p_id;
  IF NOT FOUND THEN RETURN ''; END IF;
  SELECT count(*) FILTER (WHERE x.e->>'kind' = 'event' AND coalesce((x.e->>'fixed')::boolean, false) = false),
         count(*) FILTER (WHERE x.e->>'kind' = 'task'),
         count(*) FILTER (WHERE x.e->>'kind' = 'event' AND coalesce((x.e->>'fixed')::boolean, false))
    INTO n_ev, n_tk, n_fx FROM jsonb_array_elements(r.items) AS x(e) WHERE coalesce((x.e->>'skip')::boolean, false) = false;
  v := 'Li sua agenda' || CASE WHEN r.week_start IS NOT NULL THEN ' da semana de ' || to_char(r.week_start, 'DD/MM') || ' a ' || to_char(r.week_start + 6, 'DD/MM/YYYY') ELSE '' END
    || '. Confira antes de eu criar: ' || n_ev || ' compromisso(s) no Google Agenda, ' || n_tk || ' tarefa(s) no Google Tarefas'
    || CASE WHEN n_fx > 0 THEN ' e ' || n_fx || ' bloco(s) fixo(s)' ELSE '' END || '.' || E'\n';
  FOR it IN SELECT x.e FROM jsonb_array_elements(r.items) AS x(e)
            WHERE x.e->>'kind' = 'event' AND coalesce((x.e->>'skip')::boolean, false) = false AND coalesce((x.e->>'fixed')::boolean, false) = false
            ORDER BY x.e->>'day', x.e->>'start' LOOP
    d := (it->>'day')::date;
    IF last_day IS DISTINCT FROM d THEN
      v := v || E'\n' || f_agimp_dow(d) || ' ' || to_char(d, 'DD/MM') || E'\n';
      last_day := d;
    END IF;
    v := v || (it->>'n') || '. ' || (it->>'start') || '–' || (it->>'end') || ' ' || (it->>'title')
      || CASE WHEN coalesce((it->>'uncertain')::boolean, false) THEN ' (?)' ELSE '' END || E'\n';
  END LOOP;
  FOR g IN SELECT x.e->>'title' AS title, x.e->>'start' AS s, x.e->>'end' AS en, array_agg((x.e->>'day')::date) AS days, string_agg(x.e->>'n', ', ' ORDER BY (x.e->>'n')::int) AS ns,
                  bool_or(coalesce((x.e->>'uncertain')::boolean, false)) AS unc
             FROM jsonb_array_elements(r.items) AS x(e)
            WHERE x.e->>'kind' = 'event' AND coalesce((x.e->>'skip')::boolean, false) = false AND coalesce((x.e->>'fixed')::boolean, false)
            GROUP BY lower(x.e->>'title'), x.e->>'title', x.e->>'start', x.e->>'end' ORDER BY min(x.e->>'start'), x.e->>'title' LOOP
    fx := fx || g.title || ' ' || g.s || '–' || g.en || ', ' || f_agimp_days_label(g.days) || ' (itens ' || g.ns || ')' || CASE WHEN g.unc THEN ' (?)' ELSE '' END || E'\n';
  END LOOP;
  IF fx <> '' THEN
    v := v || E'\nBlocos fixos (repetem no mesmo horário):\n' || fx
      || 'Quer esses fixos na agenda? Eles entram sem aviso, só para você ver os blocos; o lembrete vem no resumo da manhã. Se não quiser, diga "sem os fixos".' || E'\n';
  END IF;
  FOR it IN SELECT x.e FROM jsonb_array_elements(r.items) AS x(e)
            WHERE x.e->>'kind' = 'task' AND coalesce((x.e->>'skip')::boolean, false) = false
            ORDER BY x.e->>'day', (x.e->>'n')::int LOOP
    d := (it->>'day')::date;
    tks := tks || (it->>'n') || '. ' || CASE WHEN coalesce((it->>'urgent')::boolean, false) THEN '🔴 ' ELSE '' END || (it->>'title')
      || ' (' || f_agimp_dow(d) || ' ' || to_char(d, 'DD/MM') || ')'
      || CASE WHEN coalesce((it->>'uncertain')::boolean, false) THEN ' (?)' ELSE '' END || E'\n';
  END LOOP;
  IF tks <> '' THEN v := v || E'\nTarefas (cada uma aparece no Google Tarefas só no dia dela)\n' || tks; END IF;
  SELECT string_agg('- ' || n, E'\n') INTO nt FROM jsonb_array_elements_text(r.notes) AS n;
  IF coalesce(nt, '') <> '' THEN v := v || E'\nNão importei:\n' || nt || E'\n'; END IF;
  v := v || E'\nItens com (?) são os que eu li com dúvida. Para corrigir, escreva por exemplo "o 3 é na segunda", "o 4 termina às 16h" ou "tira o 5". Para criar, toque em Criar tudo.';
  RETURN v;
END $$;

-- ---------- criar rascunho: descarta notas, marca fixos ----------
CREATE OR REPLACE FUNCTION f_agimp_create(p_user bigint, p_x jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE v_cal text; e jsonb; v_items jsonb := '[]'::jsonb; n int := 0; v_day date; k text; v_id bigint; v_week date; v_notes jsonb; v_title text; v_drop jsonb := '[]'::jsonb;
BEGIN
  SELECT calendar_key INTO v_cal FROM users WHERE id = p_user;
  IF coalesce(v_cal, '') = '' THEN
    RETURN jsonb_build_object('text', 'Ainda não tenho o seu Google conectado, então não consigo criar eventos nem tarefas. Fale com o Adrian para ligar a sua conta.', 'kb', 'none', 'rid', 0);
  END IF;
  FOR e IN SELECT x FROM jsonb_array_elements(coalesce(p_x->'items', '[]'::jsonb)) AS x LOOP
    BEGIN v_day := (e->>'day')::date; EXCEPTION WHEN others THEN CONTINUE; END;
    IF v_day IS NULL THEN CONTINUE; END IF;
    v_title := left(coalesce(nullif(trim(e->>'title'), ''), 'Compromisso'), 120);
    -- nao e acao nem compromisso: feriado, avisos soltos
    IF lower(v_title) ~ '^(feriado|recesso|ponto facultativo|obs\.?|observa[cç][aã]o|anota[cç][aã]o|nota|lembrete geral)\M' THEN
      v_drop := v_drop || to_jsonb(v_title || ' (' || to_char(v_day, 'DD/MM') || ')');
      CONTINUE;
    END IF;
    k := CASE WHEN e->>'kind' = 'task' THEN 'task' ELSE 'event' END;
    IF k = 'event' AND NOT (coalesce(e->>'start', '') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' AND coalesce(e->>'end', '') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' AND (e->>'end') > (e->>'start')) THEN
      k := 'task';
    END IF;
    n := n + 1;
    v_items := v_items || jsonb_build_array(jsonb_build_object('n', n, 'kind', k, 'day', v_day,
      'start', CASE WHEN k = 'event' THEN e->>'start' END, 'end', CASE WHEN k = 'event' THEN e->>'end' END,
      'title', v_title,
      'urgent', coalesce((e->>'urgent')::boolean, false), 'uncertain', coalesce((e->>'uncertain')::boolean, false)));
  END LOOP;
  IF n = 0 THEN
    RETURN jsonb_build_object('text', 'Não consegui ler compromissos nessa foto. Tente de novo com a página inteira, bem iluminada e sem reflexo.', 'kb', 'none', 'rid', 0);
  END IF;
  v_items := f_agimp_mark_fixed(v_items);
  BEGIN v_week := (p_x->>'week_start')::date; EXCEPTION WHEN others THEN v_week := NULL; END;
  v_notes := (CASE WHEN jsonb_typeof(p_x->'notes') = 'array' THEN p_x->'notes' ELSE '[]'::jsonb END) || v_drop;
  DELETE FROM agenda_import WHERE user_id = p_user AND created_at < now() - interval '30 days';
  UPDATE agenda_import SET state = 'cancelled' WHERE user_id = p_user AND state = 'open';
  INSERT INTO agenda_import (user_id, calendar_key, week_start, items, notes) VALUES (p_user, v_cal, v_week, v_items, v_notes) RETURNING id INTO v_id;
  RETURN jsonb_build_object('text', f_agimp_render(v_id), 'kb', 'agimp', 'rid', v_id);
END $$;

-- ---------- confirmar: eventos (fixos sem aviso), tarefas de hoje agora, futuras guardadas ----------
CREATE OR REPLACE FUNCTION f_agimp_confirm(p_user bigint, p_id bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE r agenda_import; v_tz text; ev jsonb; tk jsonb; v_today date;
BEGIN
  UPDATE agenda_import SET state = 'running' WHERE id = p_id AND user_id = p_user AND state = 'open' RETURNING * INTO r;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('text', 'Essa importação já foi processada ou cancelada. Se precisar, mande a foto de novo.', 'kb', 'none', 'rid', 0);
  END IF;
  SELECT coalesce(timezone, 'America/Sao_Paulo') INTO v_tz FROM users WHERE id = p_user;
  v_today := (now() AT TIME ZONE v_tz)::date;
  SELECT coalesce(jsonb_agg(jsonb_build_object('summary', x.e->>'title', 'start', f_agimp_iso((x.e->>'day')::date, x.e->>'start', v_tz), 'end', f_agimp_iso((x.e->>'day')::date, x.e->>'end', v_tz),
           'no_reminders', coalesce((x.e->>'fixed')::boolean, false))
         ORDER BY x.e->>'day', x.e->>'start'), '[]'::jsonb) INTO ev
    FROM jsonb_array_elements(r.items) AS x(e) WHERE x.e->>'kind' = 'event' AND coalesce((x.e->>'skip')::boolean, false) = false;
  SELECT coalesce(jsonb_agg(jsonb_build_object('title', CASE WHEN coalesce((x.e->>'urgent')::boolean, false) THEN '🔴 ' ELSE '' END || (x.e->>'title'), 'due', x.e->>'day')
         ORDER BY x.e->>'day', (x.e->>'n')::int), '[]'::jsonb) INTO tk
    FROM jsonb_array_elements(r.items) AS x(e) WHERE x.e->>'kind' = 'task' AND coalesce((x.e->>'skip')::boolean, false) = false AND (x.e->>'day')::date <= v_today;
  INSERT INTO agenda_tarefas_agendadas (user_id, draft_id, n, title, due, urgent)
    SELECT p_user, p_id, (x.e->>'n')::int, x.e->>'title', (x.e->>'day')::date, coalesce((x.e->>'urgent')::boolean, false)
      FROM jsonb_array_elements(r.items) AS x(e)
     WHERE x.e->>'kind' = 'task' AND coalesce((x.e->>'skip')::boolean, false) = false AND (x.e->>'day')::date > v_today
    ON CONFLICT (draft_id, n) DO NOTHING;
  RETURN jsonb_build_object('text', 'Criando no seu Google...', 'kb', 'none', 'rid', 0,
    'imp', jsonb_build_object('draft_id', p_id, 'calendar_key', r.calendar_key, 'events', ev, 'tasks', tk));
END $$;

-- ---------- edit: "sem os fixos" ----------
-- Sobrescreve apenas o inicio: delega ao corpo antigo quando nao e o caso dos fixos.
DO $$
BEGIN
  IF to_regproc('agente.f_agimp_edit_pre_m9') IS NULL THEN
    ALTER FUNCTION agente.f_agimp_edit(bigint, jsonb) RENAME TO f_agimp_edit_pre_m9;
  END IF;
END $$;
CREATE OR REPLACE FUNCTION f_agimp_edit(p_user bigint, p_x jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE r agenda_import; n_fx int;
BEGIN
  IF coalesce(p_x->>'act', '') = 'remove' AND lower(trim(coalesce(p_x->>'title', ''))) = 'fixos' AND coalesce(p_x->>'n', '') = '' THEN
    SELECT * INTO r FROM agenda_import WHERE user_id = p_user AND state = 'open' ORDER BY id DESC LIMIT 1;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('text', 'Não tenho nenhuma importação de agenda em aberto. Mande a foto da agenda que eu leio de novo.', 'kb', 'none', 'rid', 0);
    END IF;
    SELECT count(*) INTO n_fx FROM jsonb_array_elements(r.items) x(e) WHERE coalesce((x.e->>'fixed')::boolean, false) AND coalesce((x.e->>'skip')::boolean, false) = false;
    IF n_fx = 0 THEN
      RETURN jsonb_build_object('text', 'Não há blocos fixos nesse rascunho.' || E'\n\n' || f_agimp_render(r.id), 'kb', 'agimp', 'rid', r.id);
    END IF;
    UPDATE agenda_import SET items = (SELECT jsonb_agg(CASE WHEN coalesce((x.e->>'fixed')::boolean, false) THEN jsonb_set(x.e, '{skip}', 'true'::jsonb) ELSE x.e END ORDER BY ord)
                                        FROM jsonb_array_elements(items) WITH ORDINALITY AS x(e, ord)) WHERE id = r.id;
    RETURN jsonb_build_object('text', 'Tirei os blocos fixos.' || E'\n\n' || f_agimp_render(r.id), 'kb', 'agimp', 'rid', r.id);
  END IF;
  RETURN f_agimp_edit_pre_m9(p_user, p_x);
END $$;

-- ---------- depois de criar no Google ----------
CREATE OR REPLACE FUNCTION f_agimp_done(p_user bigint, p_id bigint, p_res jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE eo int := coalesce((p_res->>'events_ok')::int, 0); ef int := coalesce((p_res->>'events_fail')::int, 0);
        tko int := coalesce((p_res->>'tasks_ok')::int, 0); tkf int := coalesce((p_res->>'tasks_fail')::int, 0); v text; errs text; sch int;
BEGIN
  SELECT count(*) INTO sch FROM agenda_tarefas_agendadas WHERE draft_id = p_id AND user_id = p_user AND state = 'scheduled';
  IF eo + tko + sch = 0 OR (eo + tko = 0 AND ef + tkf > 0) THEN
    DELETE FROM agenda_tarefas_agendadas WHERE draft_id = p_id AND user_id = p_user AND state = 'scheduled';
    UPDATE agenda_import SET state = 'open', result = p_res WHERE id = p_id AND user_id = p_user AND state = 'running';
    SELECT string_agg('- ' || left(x, 120), E'\n') INTO errs FROM (SELECT jsonb_array_elements_text(coalesce(p_res->'errors', '[]'::jsonb)) AS x LIMIT 3) q;
    RETURN jsonb_build_object('text', 'Não consegui criar nada no seu Google agora.' || CASE WHEN coalesce(errs, '') <> '' THEN E'\n' || errs ELSE '' END || E'\nToque em Criar tudo para tentar de novo.', 'kb', 'agimp', 'rid', p_id);
  END IF;
  UPDATE agenda_import SET state = 'done', result = p_res, done_at = now() WHERE id = p_id AND user_id = p_user;
  v := 'Pronto! Criei ' || eo || ' compromisso(s) no Google Agenda e ' || tko || ' tarefa(s) no Google Tarefas hoje.';
  IF sch > 0 THEN v := v || E'\nGuardei ' || sch || ' tarefa(s) de outros dias: cada uma aparece no Google Tarefas na manhã do dia dela.'; END IF;
  IF ef + tkf > 0 THEN
    SELECT string_agg('- ' || left(x, 120), E'\n') INTO errs FROM (SELECT jsonb_array_elements_text(coalesce(p_res->'errors', '[]'::jsonb)) AS x LIMIT 3) q;
    v := v || E'\nNão consegui criar ' || (ef + tkf) || ' item(ns).' || CASE WHEN coalesce(errs, '') <> '' THEN E'\n' || errs ELSE '' END;
  END IF;
  v := v || E'\nSe algo ficou errado, me diga que eu ajusto.';
  RETURN jsonb_build_object('text', v, 'kb', 'none', 'rid', 0);
END $$;

-- ---------- Disparador: tarefas agendadas que vencem hoje (ou antes) ----------
CREATE OR REPLACE FUNCTION f_agimp_tasks_due(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE v_tz text; v_today date;
BEGIN
  SELECT coalesce(timezone, 'America/Sao_Paulo') INTO v_tz FROM users WHERE id = p_user;
  v_today := (now() AT TIME ZONE coalesce(v_tz, 'America/Sao_Paulo'))::date;
  RETURN jsonb_build_object('items', coalesce((SELECT jsonb_agg(jsonb_build_object('id', t.id, 'title', CASE WHEN t.urgent THEN '🔴 ' ELSE '' END || t.title, 'due', t.due) ORDER BY t.due, t.id)
    FROM agenda_tarefas_agendadas t WHERE t.user_id = p_user AND t.state = 'scheduled' AND t.due <= v_today), '[]'::jsonb));
END $$;

-- p_ids = [id,...] criadas com sucesso no Google; as que falharam continuam 'scheduled' (tenta no dia seguinte)
CREATE OR REPLACE FUNCTION f_agimp_tasks_mark(p_user bigint, p_ids jsonb) RETURNS integer
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE c int;
BEGIN
  UPDATE agenda_tarefas_agendadas SET state = 'created'
   WHERE user_id = p_user AND state = 'scheduled' AND id IN (SELECT (jsonb_array_elements_text(coalesce(p_ids, '[]'::jsonb)))::bigint);
  GET DIAGNOSTICS c = ROW_COUNT;
  RETURN c;
END $$;

-- ---------- resumo: sem bloco de projetos do banco; avisa prazo do projeto hoje/amanha ----------
CREATE OR REPLACE FUNCTION f_proj_deadline_lines(p_user bigint) RETURNS text
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE today date := f_fin_today(p_user); t text := ''; r record;
BEGIN
  FOR r IN SELECT pr.name, pr.due_date FROM projects pr
            WHERE pr.user_id = p_user AND pr.due_date IN (today, today + 1)
              AND EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = pr.id AND NOT x.done)
            ORDER BY pr.due_date, pr.name LOOP
    t := t || E'\n- Prazo do projeto ' || r.name || ': ' || CASE WHEN r.due_date = today THEN 'hoje' ELSE 'amanhã' END;
  END LOOP;
  RETURN ltrim(t, E'\n');
END $$;

CREATE OR REPLACE FUNCTION f_summary_data_pre_m2(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE
  v jsonb; c jsonb; t text := ''; x jsonb; NL text := chr(10); tip text; pj text;
BEGIN
  v := f_summary_data_base(p_user);
  c := COALESCE(v->'cards', '[]'::jsonb);
  FOR x IN SELECT * FROM jsonb_array_elements(c) LOOP
    t := t || '- Fatura ' || (x->>'name') || ' R$ ' || replace(to_char((x->>'amount')::numeric, 'FM999G990D00'), ',', '.') || ' vence ' || (x->>'due')
         || CASE WHEN (x->>'days')::int = 0 THEN ' (hoje)' WHEN (x->>'days')::int = 1 THEN ' (amanha)' ELSE '' END || NL;
  END LOOP;
  IF t <> '' THEN t := 'Cartoes:' || NL || t; END IF;
  pj := f_proj_deadline_lines(p_user);
  IF pj <> '' THEN t := t || CASE WHEN t <> '' THEN NL ELSE '' END || pj || NL; END IF;
  tip := f_tip(p_user);
  IF tip <> '' THEN t := rtrim(t, NL) || CASE WHEN rtrim(t, NL) <> '' THEN NL || NL ELSE '' END || tip; END IF;
  RETURN v || jsonb_build_object('extras_text', rtrim(t, NL));
END $$;
