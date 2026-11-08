-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_summary_candidates()
-- Origem da definicao atual: 011_planejamento.sql (linha 332)
-- Definicoes (migracao:linha), da mais antiga a atual: 003_functions.sql:233, 009_resumos.sql:13, 011_planejamento.sql:332
CREATE OR REPLACE FUNCTION f_summary_candidates() RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE v_m jsonb; v_e jsonb;
BEGIN
  WITH due AS (
    UPDATE users u SET last_summary_on = (now() AT TIME ZONE u.timezone)::date
    WHERE u.onboarding_step = 'done' AND u.morning_enabled
      AND u.last_summary_on IS DISTINCT FROM (now() AT TIME ZONE u.timezone)::date
      AND (now() AT TIME ZONE u.timezone)::time >= u.summary_time
      AND (now() AT TIME ZONE u.timezone)::time <  u.summary_time + interval '30 minutes'
    RETURNING u.id, u.telegram_id, coalesce(u.nickname, u.name) AS name, u.timezone, u.calendar_key, u.no_emoji)
  SELECT jsonb_agg(jsonb_build_object('user_id', id, 'chat_id', telegram_id, 'name', name, 'timezone', timezone, 'calendar_key', calendar_key, 'kind', 'morning', 'no_emoji', no_emoji))
  INTO v_m FROM due;
  WITH due AS (
    UPDATE users u SET last_evening_on = (now() AT TIME ZONE u.timezone)::date
    WHERE u.onboarding_step = 'done' AND u.evening_enabled
      AND u.last_evening_on IS DISTINCT FROM (now() AT TIME ZONE u.timezone)::date
      AND (now() AT TIME ZONE u.timezone)::time >= u.evening_time
      AND (now() AT TIME ZONE u.timezone)::time <  u.evening_time + interval '30 minutes'
    RETURNING u.id, u.telegram_id, coalesce(u.nickname, u.name) AS name, u.timezone, u.calendar_key, u.no_emoji)
  SELECT jsonb_agg(jsonb_build_object('user_id', id, 'chat_id', telegram_id, 'name', name, 'timezone', timezone, 'calendar_key', calendar_key, 'kind', 'evening', 'no_emoji', no_emoji))
  INTO v_e FROM due;
  RETURN coalesce(v_m, '[]'::jsonb) || coalesce(v_e, '[]'::jsonb);
END $$;
