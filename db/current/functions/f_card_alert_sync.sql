-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_card_alert_sync(p_card bigint)
-- Origem da definicao atual: 013_extras.sql (linha 140)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:140
CREATE OR REPLACE FUNCTION f_card_alert_sync(p_card bigint) RETURNS void
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE c fin_cards%ROWTYPE; ts timestamptz; v_rid bigint;
BEGIN
  UPDATE notifications SET state = 'cancelled'
   WHERE state = 'pending' AND reminder_id IN (SELECT id FROM reminders WHERE card_id = p_card AND status = 'pending');
  UPDATE reminders SET status = 'cancelled', repeat_rule = NULL WHERE card_id = p_card AND status = 'pending';
  SELECT * INTO c FROM fin_cards WHERE id = p_card AND active;
  IF NOT FOUND THEN RETURN; END IF;
  ts := f_card_next_alert(p_card, now());
  INSERT INTO reminders (user_id, kind, title, due_at, status, source, repeat_rule, card_id)
  VALUES (c.user_id, 'reminder', 'Fatura do cartão ' || c.name || ' vence dia ' || c.due_day, ts, 'pending', 'text', 'monthly', p_card)
  RETURNING id INTO v_rid;
  INSERT INTO notifications (user_id, reminder_id, type, fire_at) VALUES (c.user_id, v_rid, 'reminder', ts);
END $$;
