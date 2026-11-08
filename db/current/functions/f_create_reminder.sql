-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_create_reminder(p_user bigint, p_title text, p_due timestamptz, p_shared boolean, p_lead integer, p_kind text, p_event_id text, p_source text)
-- Origem da definicao atual: 003_functions.sql (linha 7)
-- Definicoes (migracao:linha), da mais antiga a atual: 003_functions.sql:7
CREATE OR REPLACE FUNCTION f_create_reminder(
  p_user bigint, p_title text, p_due timestamptz, p_shared boolean DEFAULT false,
  p_lead integer DEFAULT NULL, p_kind text DEFAULT 'reminder', p_event_id text DEFAULT NULL,
  p_source text DEFAULT 'text') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r record; v_rid bigint; v_my bigint; v_lead integer; v_ask boolean := false;
        v_group uuid := CASE WHEN p_shared THEN gen_random_uuid() END;
BEGIN
  FOR r IN SELECT id, default_lead_minutes FROM users WHERE id = p_user OR p_shared LOOP
    INSERT INTO reminders(user_id, kind, title, due_at, status, calendar_event_id, shared_group, source)
    VALUES (r.id, p_kind, p_title, p_due, 'pending',
            CASE WHEN r.id = p_user THEN p_event_id END, v_group, p_source)
    RETURNING id INTO v_rid;
    IF r.id = p_user THEN v_my := v_rid; END IF;
    IF p_kind = 'reminder' THEN
      INSERT INTO notifications(user_id, reminder_id, type, fire_at) VALUES (r.id, v_rid, 'reminder', p_due);
    END IF;
    v_lead := COALESCE(CASE WHEN r.id = p_user THEN p_lead END, r.default_lead_minutes);
    IF v_lead IS NOT NULL AND v_lead > 0 AND p_due - make_interval(mins => v_lead) > now() THEN
      INSERT INTO notifications(user_id, reminder_id, type, fire_at, offset_minutes)
      VALUES (r.id, v_rid, 'pre_alert', p_due - make_interval(mins => v_lead), v_lead);
    END IF;
    IF r.id = p_user AND p_lead IS NULL AND r.default_lead_minutes IS NULL THEN v_ask := true; END IF;
  END LOOP;
  RETURN jsonb_build_object('reminder_id', v_my, 'ask_lead', v_ask, 'title', p_title, 'due_at', p_due);
END $$;
