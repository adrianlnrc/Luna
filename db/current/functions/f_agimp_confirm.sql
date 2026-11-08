-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agimp_confirm(p_user bigint, p_id bigint)
-- Origem da definicao atual: 032_resumo_enxuto.sql (linha 146)
-- Definicoes (migracao:linha), da mais antiga a atual: 031_agenda_import.sql:111, 032_resumo_enxuto.sql:146
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
