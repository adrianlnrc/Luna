-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_proj_overdue_text(p_user bigint, p_pid bigint, p_today date, p_limit integer)
-- Origem da definicao atual: 017_projetos.sql (linha 135)
-- Definicoes (migracao:linha), da mais antiga a atual: 017_projetos.sql:135
CREATE OR REPLACE FUNCTION f_proj_overdue_text(p_user bigint, p_pid bigint, p_today date, p_limit integer DEFAULT 10) RETURNS text
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE r record; t text := ''; k integer := 0; tot integer;
BEGIN
  SELECT count(*) INTO tot FROM project_tasks WHERE user_id = p_user AND NOT done AND due_date < p_today AND (p_pid IS NULL OR project_id = p_pid);
  FOR r IN
    SELECT t.title, t.due_date, t.urgent, pr.name FROM project_tasks t JOIN projects pr ON pr.id = t.project_id
     WHERE t.user_id = p_user AND NOT t.done AND t.due_date < p_today AND (p_pid IS NULL OR t.project_id = p_pid)
     ORDER BY t.due_date, t.id LIMIT p_limit
  LOOP
    k := k + 1;
    t := t || E'\n- ' || r.title || CASE WHEN p_pid IS NULL THEN ' (' || r.name || ')' ELSE '' END || ' - venceu ' || f_proj_fmt(r.due_date, p_today) || CASE WHEN r.urgent THEN ' [urgente]' ELSE '' END;
  END LOOP;
  IF tot > k THEN t := t || E'\n... e mais ' || (tot - k); END IF;
  RETURN t;
END $$;
