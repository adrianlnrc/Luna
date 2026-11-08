-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_proj_gt_users()
-- Origem da definicao atual: 030_projetos_google.sql (linha 312)
-- Definicoes (migracao:linha), da mais antiga a atual: 030_projetos_google.sql:312
CREATE OR REPLACE FUNCTION f_proj_gt_users() RETURNS jsonb
LANGUAGE sql STABLE SET search_path TO 'agente','public' AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('user_id', u.id, 'calendar_key', u.calendar_key) ORDER BY u.id), '[]'::jsonb)
    FROM users u WHERE u.calendar_key IN ('adrian', 'maria') AND u.onboarding_step = 'done'
$$;
