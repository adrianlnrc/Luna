-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_proj_gt_owner(p_user bigint)
-- Origem da definicao atual: 030_projetos_google.sql (linha 46)
-- Definicoes (migracao:linha), da mais antiga a atual: 030_projetos_google.sql:46
CREATE OR REPLACE FUNCTION f_proj_gt_owner(p_user bigint) RETURNS text
LANGUAGE sql STABLE SET search_path TO 'agente','public' AS $$
  SELECT u.calendar_key FROM users u WHERE u.id = p_user AND u.calendar_key IN ('adrian', 'maria')
$$;
