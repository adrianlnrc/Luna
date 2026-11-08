-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_proj_task_resolve(p_user bigint, p_pid bigint, p_name text, p_done boolean)
-- Origem da definicao atual: 017_projetos.sql (linha 90)
-- Definicoes (migracao:linha), da mais antiga a atual: 017_projetos.sql:90
CREATE OR REPLACE FUNCTION f_proj_task_resolve(p_user bigint, p_pid bigint, p_name text, p_done boolean) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE q text := coalesce(f_norm(p_name), ''); toks text[]; ids bigint[]; n integer; lst text; r record;
BEGIN
  SELECT array_agg(t) INTO toks FROM (
    SELECT regexp_replace(x, '[^a-z0-9]', '', 'g') AS t FROM unnest(string_to_array(q, ' ')) x) s
   WHERE t <> '' AND t NOT IN ('o','a','os','as','de','do','da','dos','das','tarefa','tarefas','no','na','em','pro','pra','para','um','uma');
  IF toks IS NULL THEN RETURN jsonb_build_object('err', 'Qual tarefa? Diga o nome dela.'); END IF;
  SELECT t.id, t.title, t.project_id INTO r FROM project_tasks t
   WHERE t.user_id = p_user AND (p_pid IS NULL OR t.project_id = p_pid) AND (p_done IS NULL OR t.done = p_done) AND t.norm_title = q LIMIT 1;
  IF FOUND THEN RETURN jsonb_build_object('id', r.id, 'title', r.title, 'project_id', r.project_id); END IF;
  SELECT array_agg(t.id ORDER BY t.id) INTO ids FROM project_tasks t
   WHERE t.user_id = p_user AND (p_pid IS NULL OR t.project_id = p_pid) AND (p_done IS NULL OR t.done = p_done)
     AND (SELECT bool_and(t.norm_title LIKE '%' || x || '%') FROM unnest(toks) x);
  n := coalesce(cardinality(ids), 0);
  IF n = 1 THEN
    SELECT t.id, t.title, t.project_id INTO r FROM project_tasks t WHERE t.id = ids[1];
    RETURN jsonb_build_object('id', r.id, 'title', r.title, 'project_id', r.project_id);
  END IF;
  IF n > 1 THEN
    SELECT string_agg(t.title || CASE WHEN p_pid IS NULL THEN ' (' || pr.name || ')' ELSE '' END, '; ' ORDER BY t.id) INTO lst
      FROM (SELECT * FROM project_tasks WHERE id = ANY(ids) ORDER BY id LIMIT 5) t JOIN projects pr ON pr.id = t.project_id;
    RETURN jsonb_build_object('err', 'Achei mais de uma tarefa parecida: ' || lst || '. Qual delas?');
  END IF;
  RETURN jsonb_build_object('err', 'Não achei a tarefa "' || btrim(p_name) || '"' ||
    CASE p_done WHEN false THEN ' entre as tarefas em aberto' WHEN true THEN ' entre as concluídas' ELSE '' END || '.');
END $$;
