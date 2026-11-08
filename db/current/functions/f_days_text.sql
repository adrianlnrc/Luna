-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_days_text(p_n integer)
-- Origem da definicao atual: 013_extras.sql (linha 85)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:85
CREATE OR REPLACE FUNCTION f_days_text(p_n integer) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT CASE WHEN p_n = 0 THEN 'hoje' WHEN p_n = 1 THEN 'amanhã' WHEN p_n > 1 THEN 'em ' || p_n || ' dias'
              WHEN p_n = -1 THEN 'ontem' ELSE 'há ' || (-p_n) || ' dias' END
$$;
