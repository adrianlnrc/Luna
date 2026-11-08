-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_set_lead(p_user bigint, p_rid bigint, p_minutes integer)
-- Origem da definicao atual: 003_functions.sql (linha 34)
-- Definicoes (migracao:linha), da mais antiga a atual: 003_functions.sql:34
CREATE OR REPLACE FUNCTION f_set_lead(p_user bigint, p_rid bigint, p_minutes integer)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r reminders%ROWTYPE;
BEGIN
  SELECT * INTO r FROM reminders WHERE id = p_rid AND user_id = p_user;
  IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Nao encontrei esse lembrete.', 'kb', 'none'); END IF;
  IF p_minutes <= 0 THEN
    RETURN jsonb_build_object('text', 'Ok, sem aviso antes.', 'kb', 'none');
  END IF;
  IF r.due_at - make_interval(mins => p_minutes) <= now() THEN
    RETURN jsonb_build_object('text', 'Esse aviso ja passou do horario. Escolha uma antecedencia menor.', 'kb', 'lead', 'rid', p_rid);
  END IF;
  INSERT INTO notifications(user_id, reminder_id, type, fire_at, offset_minutes)
  VALUES (p_user, p_rid, 'pre_alert', r.due_at - make_interval(mins => p_minutes), p_minutes);
  RETURN jsonb_build_object('text', 'Fechado. Aviso ' ||
    CASE WHEN p_minutes >= 1440 THEN (p_minutes / 1440) || ' dia(s)' WHEN p_minutes >= 60 THEN (p_minutes / 60) || 'h' ELSE p_minutes || ' min' END
    || ' antes de "' || r.title || '".', 'kb', 'none');
END $$;
