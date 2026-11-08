-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_supply_bought(p_user bigint, p_item text)
-- Origem da definicao atual: 006_cadastro_simples.sql (linha 123)
-- Definicoes (migracao:linha), da mais antiga a atual: 003_functions.sql:138, 005_doses.sql:232, 006_cadastro_simples.sql:123
CREATE OR REPLACE FUNCTION f_supply_bought(p_user bigint, p_item text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint; s supplies%ROWTYPE;
BEGIN
  v_id := f_find_supply(p_user, p_item);
  IF v_id IS NULL THEN RETURN jsonb_build_object('found', false); END IF;
  SELECT * INTO s FROM supplies WHERE id = v_id;
  UPDATE supplies SET units_total = COALESCE(pack_size, units_total), started_on = CURRENT_DATE, paused_days = 0, alert_notified_on = NULL WHERE id = v_id;
  RETURN jsonb_build_object('found', true, 'item', s.item, 'units_total', COALESCE(s.pack_size, s.units_total));
END $$;
