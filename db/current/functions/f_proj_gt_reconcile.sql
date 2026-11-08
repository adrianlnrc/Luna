-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_proj_gt_reconcile(p_user bigint, p_ids jsonb)
-- Origem da definicao atual: 030_projetos_google.sql (linha 222)
-- Definicoes (migracao:linha), da mais antiga a atual: 030_projetos_google.sql:222
CREATE OR REPLACE FUNCTION f_proj_gt_reconcile(p_user bigint, p_ids jsonb) RETURNS integer
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE n integer := 0; pids bigint[];
BEGIN
  IF p_ids IS NULL OR jsonb_typeof(p_ids) <> 'array' OR jsonb_array_length(p_ids) = 0 THEN RETURN 0; END IF;
  PERFORM set_config('agente.gsync', 'on', true);
  WITH upd AS (
    UPDATE project_tasks t SET done = true, done_at = now()
     WHERE t.user_id = p_user AND NOT t.done AND t.google_task_id IN (SELECT jsonb_array_elements_text(p_ids))
    RETURNING t.project_id)
  SELECT count(*), array_agg(DISTINCT project_id) INTO n, pids FROM upd;
  PERFORM set_config('agente.gsync', 'off', true);
  IF n > 0 THEN   -- o estado da tarefa-pai (concluida quando todas as subtarefas estao feitas) precisa ir ao Google
    UPDATE projects SET google_pending = true, google_ver = google_ver + 1
     WHERE id = ANY(pids) AND user_id = p_user AND google_task_id IS NOT NULL;
  END IF;
  RETURN coalesce(n, 0);
END $$;
