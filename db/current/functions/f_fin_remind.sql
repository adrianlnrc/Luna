-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_remind(p_entry bigint)
-- Origem da definicao atual: 008_financas.sql (linha 202)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:202
CREATE OR REPLACE FUNCTION f_fin_remind(p_entry bigint) RETURNS void LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE e fin_entries%ROWTYPE; tz text; ts timestamptz; v_rid bigint; v_title text;
BEGIN
  SELECT * INTO e FROM fin_entries WHERE id = p_entry;
  IF NOT FOUND OR e.status <> 'pending' OR e.due_on IS NULL OR e.reminder_id IS NOT NULL THEN RETURN; END IF;
  SELECT timezone INTO tz FROM users WHERE id = e.user_id;
  ts := (e.due_on + time '09:00') AT TIME ZONE tz;
  IF ts < now() THEN ts := now() + interval '1 minute'; END IF;
  v_title := CASE
    WHEN e.kind = 'expense' THEN 'Pagar ' || e.description || ' (' || f_brl(e.amount) || ')'
    WHEN e.person IS NOT NULL THEN 'Cobrar ' || e.person || ': ' || f_brl(e.amount)
    ELSE 'Receber ' || e.description || ' (' || f_brl(e.amount) || ')' END;
  INSERT INTO reminders (user_id, kind, title, due_at, status, source) VALUES (e.user_id, 'reminder', v_title, ts, 'pending', 'text')
  RETURNING id INTO v_rid;
  INSERT INTO notifications (user_id, reminder_id, type, fire_at) VALUES (e.user_id, v_rid, 'reminder', ts);
  UPDATE fin_entries SET reminder_id = v_rid WHERE id = p_entry;
END $$;
