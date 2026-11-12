-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_insight_prefs(p_user bigint)
-- Origem da definicao atual: 039_insights.sql (linha 31)
-- Definicoes (migracao:linha), da mais antiga a atual: 039_insights.sql:31
CREATE OR REPLACE FUNCTION f_insight_prefs(p_user bigint) RETURNS insight_prefs
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE p insight_prefs%ROWTYPE;
BEGIN
  SELECT * INTO p FROM insight_prefs WHERE user_id = p_user;
  IF NOT FOUND THEN
    INSERT INTO insight_prefs (user_id) VALUES (p_user) ON CONFLICT (user_id) DO NOTHING;
    SELECT * INTO p FROM insight_prefs WHERE user_id = p_user;
  END IF;
  RETURN p;
END $$;
