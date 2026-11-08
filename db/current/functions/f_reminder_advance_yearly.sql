-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_reminder_advance_yearly(p_rid bigint)
-- Origem da definicao atual: 028_custo_ia_anuais.sql (linha 188)
-- Definicoes (migracao:linha), da mais antiga a atual: 028_custo_ia_anuais.sql:188
CREATE OR REPLACE FUNCTION f_reminder_advance_yearly(p_rid bigint) RETURNS bigint
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE r reminders%ROWTYPE; root reminders%ROWTYPE; tz text; v_chain bigint; v_loc timestamp; v_nxt timestamptz;
        v_left integer; v_lead integer; v_new bigint; a_mon integer; a_day integer; y integer; d integer; n integer := 0;
BEGIN
  SELECT * INTO r FROM reminders WHERE id = p_rid;
  IF NOT FOUND OR r.repeat_rule IS DISTINCT FROM 'yearly' OR r.status <> 'pending' THEN RETURN NULL; END IF;
  v_chain := coalesce(r.repeat_of, r.id);
  UPDATE notifications SET state = 'cancelled'
   WHERE state = 'pending' AND reminder_id IN (SELECT id FROM reminders WHERE coalesce(repeat_of, id) = v_chain AND id < r.id AND user_id = r.user_id);
  UPDATE reminders SET status = 'done' WHERE coalesce(repeat_of, id) = v_chain AND id < r.id AND user_id = r.user_id AND status = 'pending';
  IF EXISTS (SELECT 1 FROM reminders WHERE coalesce(repeat_of, id) = v_chain AND id > r.id AND user_id = r.user_id AND status = 'pending') THEN RETURN NULL; END IF;
  SELECT timezone INTO tz FROM users WHERE id = r.user_id;
  SELECT * INTO root FROM reminders WHERE id = v_chain;
  a_mon := extract(month FROM (coalesce(root.due_at, r.due_at) AT TIME ZONE tz))::int;
  a_day := extract(day FROM (coalesce(root.due_at, r.due_at) AT TIME ZONE tz))::int;
  v_loc := r.due_at AT TIME ZONE tz;
  v_left := r.repeat_left;
  LOOP
    n := n + 1;
    IF n > 100 THEN RETURN NULL; END IF;
    IF v_left IS NOT NULL AND v_left <= 0 THEN RETURN NULL; END IF;
    y := extract(year FROM v_loc)::int + 1;
    d := least(a_day, extract(day FROM (make_date(y, a_mon, 1) + interval '1 month - 1 day'))::int);
    v_loc := make_date(y, a_mon, d) + v_loc::time;
    v_nxt := v_loc AT TIME ZONE tz;
    IF v_left IS NOT NULL THEN v_left := v_left - 1; END IF;
    EXIT WHEN v_nxt > now();
  END LOOP;
  IF r.repeat_until IS NOT NULL AND v_loc::date > r.repeat_until THEN RETURN NULL; END IF;
  INSERT INTO reminders (user_id, kind, title, due_at, status, shared_group, source, repeat_rule, repeat_until, repeat_left, repeat_of)
  VALUES (r.user_id, 'reminder', r.title, v_nxt, 'pending', r.shared_group, r.source, 'yearly', r.repeat_until, v_left, v_chain)
  RETURNING id INTO v_new;
  INSERT INTO notifications (user_id, reminder_id, type, fire_at) VALUES (r.user_id, v_new, 'reminder', v_nxt);
  SELECT offset_minutes INTO v_lead FROM notifications WHERE reminder_id = r.id AND type = 'pre_alert' ORDER BY id LIMIT 1;
  v_lead := coalesce(v_lead, 21600);
  IF v_lead > 0 AND v_nxt - make_interval(mins => v_lead) > now() THEN
    INSERT INTO notifications (user_id, reminder_id, type, fire_at, offset_minutes)
    VALUES (r.user_id, v_new, 'pre_alert', v_nxt - make_interval(mins => v_lead), v_lead);
  END IF;
  RETURN v_new;
END $$;
