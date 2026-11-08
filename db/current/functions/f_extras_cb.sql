-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_extras_cb(p_user bigint, p_data text)
-- Origem da definicao atual: 013_extras.sql (linha 644)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:644
CREATE OR REPLACE FUNCTION f_extras_cb(p_user bigint, p_data text) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE a text := split_part(p_data, ':', 1); v_id bigint; c fin_cards%ROWTYPE;
BEGIN
  BEGIN v_id := nullif(split_part(p_data, ':', 2), '')::bigint; EXCEPTION WHEN others THEN v_id := NULL; END;
  IF a = 'exkeep' THEN RETURN jsonb_build_object('text', 'Ok, mantive o cartão.', 'kb', 'none'); END IF;
  IF a = 'exdel' THEN
    SELECT * INTO c FROM fin_cards WHERE id = v_id AND user_id = p_user;
    IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Esse cartão já foi apagado.', 'kb', 'none'); END IF;
    UPDATE notifications SET state = 'cancelled' WHERE state = 'pending' AND reminder_id IN (SELECT id FROM reminders WHERE card_id = c.id AND status = 'pending');
    UPDATE reminders SET status = 'cancelled', repeat_rule = NULL WHERE card_id = c.id AND status = 'pending';
    DELETE FROM fin_cards WHERE id = c.id;
    RETURN jsonb_build_object('text', 'Apaguei o cartão ' || c.name || '. Os lançamentos continuam registrados.', 'kb', 'none');
  END IF;
  RETURN jsonb_build_object('text', 'Não entendi esse botão.', 'kb', 'none');
EXCEPTION WHEN others THEN
  RAISE WARNING 'f_extras_cb: %', SQLERRM;
  RETURN jsonb_build_object('text', 'Não consegui agora. Tente de novo.', 'kb', 'none');
END $$;
