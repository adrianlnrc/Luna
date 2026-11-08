-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_projects_summary(p_user bigint)
-- Origem da definicao atual: 017_projetos.sql (linha 420)
-- Definicoes (migracao:linha), da mais antiga a atual: 017_projetos.sql:420
CREATE OR REPLACE FUNCTION f_projects_summary(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE today date := f_fin_today(p_user); ov jsonb; dt jsonb; so jsonb; po jsonb; t text := ''; r record; n integer := 0; tot integer;
BEGIN
  SELECT coalesce(jsonb_agg(jsonb_build_object('project', pr.name, 'task', x.title, 'due', x.due_date, 'days_late', today - x.due_date, 'urgent', x.urgent) ORDER BY x.due_date, x.id), '[]'::jsonb)
    INTO ov FROM project_tasks x JOIN projects pr ON pr.id = x.project_id WHERE x.user_id = p_user AND NOT x.done AND x.due_date < today;
  SELECT coalesce(jsonb_agg(jsonb_build_object('project', pr.name, 'task', x.title, 'urgent', x.urgent) ORDER BY x.urgent DESC, x.id), '[]'::jsonb)
    INTO dt FROM project_tasks x JOIN projects pr ON pr.id = x.project_id WHERE x.user_id = p_user AND NOT x.done AND x.due_date = today;
  SELECT coalesce(jsonb_agg(jsonb_build_object('project', s.name, 'due', s.due_date, 'open_tasks', s.o) ORDER BY s.due_date), '[]'::jsonb)
    INTO so FROM (SELECT pr.name, pr.due_date, (SELECT count(*) FROM project_tasks x WHERE x.project_id = pr.id AND NOT x.done) AS o
                    FROM projects pr WHERE pr.user_id = p_user AND pr.due_date BETWEEN today AND today + 7) s WHERE s.o > 0;
  SELECT coalesce(jsonb_agg(jsonb_build_object('project', s.name, 'due', s.due_date, 'open_tasks', s.o) ORDER BY s.due_date), '[]'::jsonb)
    INTO po FROM (SELECT pr.name, pr.due_date, (SELECT count(*) FROM project_tasks x WHERE x.project_id = pr.id AND NOT x.done) AS o
                    FROM projects pr WHERE pr.user_id = p_user AND pr.due_date < today) s WHERE s.o > 0;
  n := jsonb_array_length(ov) + jsonb_array_length(dt) + jsonb_array_length(so) + jsonb_array_length(po);
  IF jsonb_array_length(ov) > 0 THEN
    t := t || 'Tarefas de projeto atrasadas:';
    FOR r IN SELECT x->>'project' AS pj, x->>'task' AS tk, (x->>'due')::date AS d FROM jsonb_array_elements(ov) x LIMIT 5 LOOP
      t := t || E'\n- ' || r.tk || ' (' || r.pj || ', venceu ' || f_proj_fmt(r.d, today) || ')';
    END LOOP;
    IF jsonb_array_length(ov) > 5 THEN t := t || E'\n... e mais ' || (jsonb_array_length(ov) - 5); END IF;
  END IF;
  IF jsonb_array_length(dt) > 0 THEN
    t := t || CASE WHEN t <> '' THEN E'\n' ELSE '' END || 'Tarefas de projeto para hoje:';
    FOR r IN SELECT x->>'project' AS pj, x->>'task' AS tk FROM jsonb_array_elements(dt) x LIMIT 5 LOOP
      t := t || E'\n- ' || r.tk || ' (' || r.pj || ')';
    END LOOP;
    IF jsonb_array_length(dt) > 5 THEN t := t || E'\n... e mais ' || (jsonb_array_length(dt) - 5); END IF;
  END IF;
  IF jsonb_array_length(so) > 0 THEN
    t := t || CASE WHEN t <> '' THEN E'\n' ELSE '' END || 'Projetos com prazo nos próximos 7 dias:';
    FOR r IN SELECT x->>'project' AS pj, (x->>'due')::date AS d, (x->>'open_tasks')::int AS o FROM jsonb_array_elements(so) x LIMIT 5 LOOP
      t := t || E'\n- ' || r.pj || ' (prazo ' || f_proj_fmt(r.d, today) || ', ' || r.o || ' tarefa' || CASE WHEN r.o > 1 THEN 's' ELSE '' END || ' em aberto)';
    END LOOP;
  END IF;
  IF jsonb_array_length(po) > 0 THEN
    t := t || CASE WHEN t <> '' THEN E'\n' ELSE '' END || 'Projetos com prazo vencido e tarefas em aberto:';
    FOR r IN SELECT x->>'project' AS pj, (x->>'due')::date AS d FROM jsonb_array_elements(po) x LIMIT 5 LOOP
      t := t || E'\n- ' || r.pj || ' (prazo era ' || f_proj_fmt(r.d, today) || ')';
    END LOOP;
  END IF;
  RETURN jsonb_build_object('overdue', ov, 'due_today', dt, 'soon', so, 'projects_overdue', po, 'count', n, 'text', t);
EXCEPTION WHEN others THEN
  RAISE WARNING 'f_projects_summary: %', SQLERRM;
  RETURN jsonb_build_object('overdue', '[]'::jsonb, 'due_today', '[]'::jsonb, 'soon', '[]'::jsonb, 'projects_overdue', '[]'::jsonb, 'count', 0, 'text', '');
END $$;
