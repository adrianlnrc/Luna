-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_proj_gt_backfill_count(p_user bigint)
-- Origem da definicao atual: 030_projetos_google.sql (linha 319)
-- Definicoes (migracao:linha), da mais antiga a atual: 030_projetos_google.sql:319
CREATE OR REPLACE FUNCTION f_proj_gt_backfill_count(p_user bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE sql STABLE SET search_path TO 'agente','public' AS $$
  SELECT jsonb_build_object(
    'projects_sem_google', (SELECT count(*) FROM projects p WHERE (p_user IS NULL OR p.user_id = p_user) AND p.google_task_id IS NULL AND f_proj_gt_owner(p.user_id) IS NOT NULL),
    'tasks_abertas_sem_google', (SELECT count(*) FROM project_tasks t WHERE (p_user IS NULL OR t.user_id = p_user) AND t.google_task_id IS NULL AND NOT t.done AND f_proj_gt_owner(t.user_id) IS NOT NULL),
    'pendentes', (SELECT count(*) FROM projects p WHERE (p_user IS NULL OR p.user_id = p_user) AND p.google_pending)
                 + (SELECT count(*) FROM project_tasks t WHERE (p_user IS NULL OR t.user_id = p_user) AND t.google_pending),
    'lixeira', (SELECT count(*) FROM project_google_trash WHERE p_user IS NULL OR user_id = p_user))
$$;
