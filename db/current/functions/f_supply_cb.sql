-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_supply_cb(p_user bigint, p_data text)
-- Origem da definicao atual: 024_ciclo_correcoes.sql (linha 132)
-- Definicoes (migracao:linha), da mais antiga a atual: 024_ciclo_correcoes.sql:132
CREATE OR REPLACE FUNCTION agente.f_supply_cb(p_user bigint, p_data text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE a text := split_part(p_data, ':', 1); v_id bigint := nullif(split_part(p_data, ':', 2), '')::bigint; s supplies%ROWTYPE;
BEGIN
  IF a = 'spkeep' THEN RETURN jsonb_build_object('text', 'Ok, mantive.', 'kb', 'none'); END IF;
  SELECT * INTO s FROM supplies WHERE id = v_id AND user_id = p_user;
  IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Esse item já foi apagado.', 'kb', 'none'); END IF;
  DELETE FROM notifications WHERE user_id = p_user AND (supply_id = v_id OR dose_id IN (SELECT id FROM supply_doses WHERE supply_id = v_id));
  DELETE FROM supply_doses WHERE supply_id = v_id;
  DELETE FROM supplies WHERE id = v_id;
  RETURN jsonb_build_object('text', 'Apaguei ' || s.item || CASE WHEN s.take_time IS NOT NULL THEN ' e o lembrete de tomar às ' || to_char(s.take_time, 'HH24:MI') ELSE '' END || '.', 'kb', 'none');
END $function$;
