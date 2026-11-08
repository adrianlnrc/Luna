-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_enqueue_supply_alerts()
-- Origem da definicao atual: 003_functions.sql (linha 220)
-- Definicoes (migracao:linha), da mais antiga a atual: 003_functions.sql:220
CREATE OR REPLACE FUNCTION f_enqueue_supply_alerts() RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n integer;
BEGIN
  WITH due AS (
    UPDATE supplies s SET alert_notified_on = CURRENT_DATE
    FROM supplies_status v WHERE v.id = s.id AND s.status = 'active' AND s.alert_notified_on IS NULL AND v.alert_on <= CURRENT_DATE
    RETURNING s.id, s.user_id)
  INSERT INTO notifications(user_id, supply_id, type, fire_at) SELECT user_id, id, 'supply', now() FROM due;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;
