-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_proj_gtitle(p_urgent boolean, p_title text)
-- Origem da definicao atual: 030_projetos_google.sql (linha 52)
-- Definicoes (migracao:linha), da mais antiga a atual: 030_projetos_google.sql:52
CREATE OR REPLACE FUNCTION f_proj_gtitle(p_urgent boolean, p_title text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT left(CASE WHEN p_urgent THEN '🔴 ' ELSE '' END || coalesce(p_title, ''), 1000)
$$;
