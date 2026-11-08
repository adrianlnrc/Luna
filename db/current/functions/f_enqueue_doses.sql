-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_enqueue_doses()
-- Origem da definicao atual: 005_doses.sql (linha 45)
-- Definicoes (migracao:linha), da mais antiga a atual: 005_doses.sql:45
CREATE OR REPLACE FUNCTION f_enqueue_doses() RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n integer;
BEGIN
  UPDATE notifications SET state = 'cancelled'
  WHERE state = 'pending' AND dose_id IN (
    SELECT d.id FROM supply_doses d JOIN users u ON u.id = d.user_id
    WHERE d.status = 'pending' AND d.dose_date < (now() AT TIME ZONE u.timezone)::date);
  UPDATE supply_doses d SET status = 'missed' FROM users u
  WHERE u.id = d.user_id AND d.status = 'pending' AND d.dose_date < (now() AT TIME ZONE u.timezone)::date;

  WITH due AS (
    SELECT s.id AS sid, s.user_id, (now() AT TIME ZONE u.timezone)::date AS d
    FROM supplies s JOIN users u ON u.id = s.user_id
    WHERE s.status = 'active' AND s.take_time IS NOT NULL
      AND (now() AT TIME ZONE u.timezone)::time >= s.take_time
      AND (now() AT TIME ZONE u.timezone)::time <  time '23:30'
      AND NOT EXISTS (SELECT 1 FROM supply_doses x WHERE x.supply_id = s.id AND x.dose_date = (now() AT TIME ZONE u.timezone)::date)),
  ins AS (
    INSERT INTO supply_doses(supply_id, user_id, dose_date) SELECT sid, user_id, d FROM due RETURNING id, supply_id, user_id)
  INSERT INTO notifications(user_id, supply_id, dose_id, type, fire_at) SELECT user_id, supply_id, id, 'dose', now() FROM ins;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;
