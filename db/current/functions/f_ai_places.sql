-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ai_places(p_user bigint)
-- Origem da definicao atual: 021_locais_comandos.sql (linha 84)
-- Definicoes (migracao:linha), da mais antiga a atual: 021_locais_comandos.sql:84
CREATE OR REPLACE FUNCTION f_ai_places(p_user bigint) RETURNS text
LANGUAGE sql STABLE SET search_path TO 'agente','public' AS $$
  SELECT coalesce(string_agg(name || ' = ' || address, '; ' ORDER BY name), '') FROM places WHERE user_id = p_user;
$$;
