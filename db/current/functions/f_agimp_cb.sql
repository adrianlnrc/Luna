-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agimp_cb(p_user bigint, p_data text)
-- Origem da definicao atual: 031_agenda_import.sql (linha 222)
-- Definicoes (migracao:linha), da mais antiga a atual: 031_agenda_import.sql:222
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
