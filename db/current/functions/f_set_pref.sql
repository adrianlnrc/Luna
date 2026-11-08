-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_set_pref(p_user bigint, p_lead integer, p_summary time, p_supply_days integer)
-- Origem da definicao atual: 003_functions.sql (linha 167)
-- Definicoes (migracao:linha), da mais antiga a atual: 003_functions.sql:167
CREATE OR REPLACE FUNCTION f_set_pref(p_user bigint, p_lead integer, p_summary time, p_supply_days integer)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  UPDATE users SET default_lead_minutes = COALESCE(p_lead, default_lead_minutes),
                   summary_time = COALESCE(p_summary, summary_time),
                   supply_alert_days = COALESCE(p_supply_days, supply_alert_days)
  WHERE id = p_user;
  RETURN (SELECT jsonb_build_object('lead', default_lead_minutes, 'summary', to_char(summary_time, 'HH24:MI'), 'supply_days', supply_alert_days)
          FROM users WHERE id = p_user);
END $$;
