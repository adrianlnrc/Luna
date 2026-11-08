-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_proj_progress(p_user bigint, p_pid bigint)
-- Origem da definicao atual: 017_projetos.sql (linha 50)
-- Definicoes (migracao:linha), da mais antiga a atual: 017_projetos.sql:50
CREATE OR REPLACE FUNCTION f_proj_progress(p_user bigint, p_pid bigint) RETURNS text
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE d integer; t integer;
BEGIN
  SELECT count(*) FILTER (WHERE done), count(*) INTO d, t FROM project_tasks WHERE user_id = p_user AND project_id = p_pid;
  IF t = 0 THEN RETURN 'sem tarefas ainda'; END IF;
  RETURN d || '/' || t || ' tarefa' || CASE WHEN t > 1 THEN 's' ELSE '' END || ' (' || round(100.0 * d / t) || '%)';
END $$;
