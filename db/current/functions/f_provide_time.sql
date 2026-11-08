-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_provide_time(p_user bigint, p_rid bigint, p_due timestamptz)
-- Origem da definicao atual: 003_functions.sql (linha 54)
-- Definicoes (migracao:linha), da mais antiga a atual: 003_functions.sql:54
CREATE OR REPLACE FUNCTION f_provide_time(p_user bigint, p_rid bigint, p_due timestamptz)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r reminders%ROWTYPE; tz text;
BEGIN
  SELECT * INTO r FROM reminders WHERE id = p_rid AND user_id = p_user;
  IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Nao encontrei esse lembrete.', 'kb', 'none'); END IF;
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  UPDATE notifications SET state = 'cancelled' WHERE reminder_id = p_rid AND state = 'pending';
  UPDATE reminders SET due_at = p_due, status = 'pending' WHERE id = p_rid;
  INSERT INTO notifications(user_id, reminder_id, type, fire_at) VALUES (p_user, p_rid, 'reminder', p_due);
  RETURN jsonb_build_object('text', 'Adiado: "' || r.title || '" para ' ||
    to_char(p_due AT TIME ZONE tz, 'DD/MM "as" HH24:MI') || '.', 'kb', 'none');
END $$;
