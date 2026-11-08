-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ai_groups(p_user bigint)
-- Origem da definicao atual: 021_locais_comandos.sql (linha 89)
-- Definicoes (migracao:linha), da mais antiga a atual: 021_locais_comandos.sql:89
CREATE OR REPLACE FUNCTION f_ai_groups(p_user bigint) RETURNS text
LANGUAGE sql STABLE SET search_path TO 'agente','public' AS $$
  SELECT coalesce(string_agg(name, ', ' ORDER BY name), '') FROM contact_groups WHERE user_id = p_user;
$$;
