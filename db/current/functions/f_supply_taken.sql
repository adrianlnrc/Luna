-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_supply_taken(p_user bigint, p_item text)
-- Origem da definicao atual: 006_cadastro_simples.sql (linha 106)
-- Definicoes (migracao:linha), da mais antiga a atual: 005_doses.sql:192, 006_cadastro_simples.sql:106
CREATE OR REPLACE FUNCTION f_supply_taken(p_user bigint, p_item text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint; s supplies%ROWTYPE; v_row supplies_status%ROWTYPE;
BEGIN
  v_id := f_find_supply(p_user, p_item);
  IF v_id IS NULL THEN RETURN jsonb_build_object('found', false); END IF;
  SELECT * INTO s FROM supplies WHERE id = v_id;
  IF s.take_time IS NULL THEN RETURN jsonb_build_object('found', true, 'tracking', false, 'item', s.item); END IF;
  INSERT INTO supply_doses(supply_id, user_id, dose_date, status, taken_at)
  VALUES (s.id, p_user, CURRENT_DATE, 'taken', now())
  ON CONFLICT (supply_id, dose_date) DO UPDATE SET status = 'taken', taken_at = now() WHERE supply_doses.status <> 'taken';
  UPDATE notifications SET state = 'cancelled'
  WHERE state = 'pending' AND dose_id IN (SELECT id FROM supply_doses WHERE supply_id = s.id AND dose_date = CURRENT_DATE);
  SELECT * INTO v_row FROM supplies_status WHERE id = s.id;
  RETURN jsonb_build_object('found', true, 'tracking', true, 'item', v_row.item, 'units_left', v_row.units_left,
    'runs_out_on', to_char(v_row.runs_out_on, 'DD/MM'));
END $$;
