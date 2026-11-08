-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_supply_schedule(p_user bigint, p_item text, p_time text, p_clear boolean, p_kind text)
-- Origem da definicao atual: 006_cadastro_simples.sql (linha 88)
-- Definicoes (migracao:linha), da mais antiga a atual: 006_cadastro_simples.sql:88
CREATE OR REPLACE FUNCTION f_supply_schedule(p_user bigint, p_item text, p_time text, p_clear boolean DEFAULT false, p_kind text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint; s supplies_status%ROWTYPE; r jsonb;
BEGIN
  v_id := f_find_supply(p_user, p_item);
  IF p_clear THEN
    IF v_id IS NULL THEN RETURN jsonb_build_object('found', false); END IF;
    SELECT * INTO s FROM supplies_status WHERE id = v_id;
    UPDATE supplies SET take_time = NULL, units_total = CASE WHEN s.units_left IS NULL THEN NULL ELSE GREATEST(1, round(s.units_left)::int) END,
      started_on = CURRENT_DATE, paused_days = 0 WHERE id = v_id;
    UPDATE notifications SET state = 'cancelled' WHERE state = 'pending' AND supply_id = v_id AND type = 'dose';
    RETURN jsonb_build_object('found', true, 'item', s.item, 'cleared', true);
  END IF;
  r := f_create_supply(p_user, p_item, NULL, 1, NULL, NULL, p_kind, p_time::time, NULL);
  RETURN r || jsonb_build_object('found', true, 'cleared', false);
END $$;
