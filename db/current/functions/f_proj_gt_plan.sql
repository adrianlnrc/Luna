-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_proj_gt_plan(p_user bigint, p_opts jsonb)
-- Origem da definicao atual: 030_projetos_google.sql (linha 123)
-- Definicoes (migracao:linha), da mais antiga a atual: 030_projetos_google.sql:123
CREATE OR REPLACE FUNCTION f_proj_gt_plan(p_user bigint, p_opts jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE
  v_owner text := f_proj_gt_owner(p_user);
  v_push boolean := coalesce((p_opts->>'push')::boolean, true);
  v_list boolean := coalesce((p_opts->>'list')::boolean, false);
  v_legacy boolean := coalesce((p_opts->>'legacy')::boolean, false);
  v_limit integer := least(greatest(coalesce((p_opts->>'limit')::integer, 40), 1), 200);
  ops jsonb := '[]'::jsonb; pmap jsonb := '{}'::jsonb; r record; st text; v_pseq integer;
  v_stale timestamptz := now() - interval '3 minutes';
BEGIN
  IF v_owner IS NULL THEN RETURN jsonb_build_object('owner', NULL, 'ops', '[]'::jsonb); END IF;

  IF v_legacy THEN
    UPDATE projects p SET google_pending = true
     WHERE p.user_id = p_user AND p.google_task_id IS NULL AND NOT p.google_pending
       AND (NOT EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = p.id)
            OR EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = p.id AND NOT x.done));
    UPDATE project_tasks SET google_pending = true
     WHERE user_id = p_user AND google_task_id IS NULL AND NOT done AND NOT google_pending;
  END IF;

  IF v_list AND EXISTS (SELECT 1 FROM project_tasks WHERE user_id = p_user AND google_task_id IS NOT NULL AND NOT done) THEN
    ops := ops || jsonb_build_array(jsonb_build_object('op', 'list', 'ref', 'list', 'ver', 0, 'seq', jsonb_array_length(ops)));
  END IF;

  IF v_push THEN
    -- projetos (tarefa-pai)
    FOR r IN
      SELECT p.id, p.name, p.due_date, p.google_task_id, p.google_list, p.google_ver,
             (SELECT count(*) FROM project_tasks x WHERE x.project_id = p.id) AS tot,
             (SELECT count(*) FROM project_tasks x WHERE x.project_id = p.id AND NOT x.done) AS open_n
        FROM projects p
       WHERE p.user_id = p_user AND p.google_pending AND (p.google_lock_at IS NULL OR p.google_lock_at < v_stale)
       ORDER BY p.id
    LOOP
      EXIT WHEN jsonb_array_length(ops) >= v_limit;
      st := CASE WHEN r.tot > 0 AND r.open_n = 0 THEN 'completed' ELSE 'needsAction' END;
      IF r.google_task_id IS NULL THEN
        pmap := pmap || jsonb_build_object(r.id::text, jsonb_array_length(ops));
        ops := ops || jsonb_build_array(jsonb_build_object('op', 'create', 'kind', 'project', 'ref', 'p:' || r.id, 'ver', r.google_ver,
                 'seq', jsonb_array_length(ops), 'list', '@default', 'title', left(r.name, 1000), 'due', coalesce(r.due_date::text, ''), 'status', 'needsAction'));
      ELSE
        ops := ops || jsonb_build_array(jsonb_build_object('op', 'update', 'kind', 'project', 'ref', 'p:' || r.id, 'ver', r.google_ver,
                 'seq', jsonb_array_length(ops), 'list', coalesce(r.google_list, '@default'), 'gid', r.google_task_id,
                 'title', left(r.name, 1000), 'due', coalesce(r.due_date::text, ''), 'status', st));
      END IF;
      UPDATE projects SET google_lock_at = now() WHERE id = r.id;
    END LOOP;

    -- tarefas do projeto (subtarefas). Ordem decrescente de id: o Google poe a subtarefa nova no topo, entao a ordem final fica igual a do banco.
    FOR r IN
      SELECT t.id, t.project_id, t.title, t.due_date, t.urgent, t.done, t.google_task_id, t.google_list, t.google_ver,
             p.google_task_id AS pgid
        FROM project_tasks t JOIN projects p ON p.id = t.project_id
       WHERE t.user_id = p_user AND t.google_pending AND (t.google_lock_at IS NULL OR t.google_lock_at < v_stale)
       ORDER BY t.project_id, t.id DESC
    LOOP
      EXIT WHEN jsonb_array_length(ops) >= v_limit;
      IF r.google_task_id IS NULL THEN
        IF r.done THEN
          UPDATE project_tasks SET google_pending = false WHERE id = r.id;   -- nunca foi ao Google e ja esta concluida: nada a espelhar
          CONTINUE;
        END IF;
        v_pseq := -1;
        IF r.pgid IS NULL THEN
          IF pmap ? r.project_id::text THEN v_pseq := (pmap->>r.project_id::text)::integer; ELSE CONTINUE; END IF;
        END IF;
        ops := ops || jsonb_build_array(jsonb_build_object('op', 'create', 'kind', 'task', 'ref', 't:' || r.id, 'ver', r.google_ver,
                 'seq', jsonb_array_length(ops), 'list', '@default', 'title', f_proj_gtitle(r.urgent, r.title), 'due', coalesce(r.due_date::text, ''),
                 'status', 'needsAction', 'parent_gid', coalesce(r.pgid, ''), 'parent_seq', v_pseq));
      ELSE
        ops := ops || jsonb_build_array(jsonb_build_object('op', 'update', 'kind', 'task', 'ref', 't:' || r.id, 'ver', r.google_ver,
                 'seq', jsonb_array_length(ops), 'list', coalesce(r.google_list, '@default'), 'gid', r.google_task_id,
                 'title', f_proj_gtitle(r.urgent, r.title), 'due', coalesce(r.due_date::text, ''),
                 'status', CASE WHEN r.done THEN 'completed' ELSE 'needsAction' END));
      END IF;
      UPDATE project_tasks SET google_lock_at = now() WHERE id = r.id;
    END LOOP;

    -- lixeira (projeto/tarefa apagados que existiam no Google)
    FOR r IN
      SELECT id, google_task_id, google_list FROM project_google_trash
       WHERE user_id = p_user AND (lock_at IS NULL OR lock_at < v_stale) ORDER BY id
    LOOP
      EXIT WHEN jsonb_array_length(ops) >= v_limit;
      ops := ops || jsonb_build_array(jsonb_build_object('op', 'delete', 'kind', 'trash', 'ref', 'x:' || r.id, 'ver', 0,
               'seq', jsonb_array_length(ops), 'list', coalesce(r.google_list, '@default'), 'gid', r.google_task_id));
      UPDATE project_google_trash SET lock_at = now() WHERE id = r.id;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('owner', v_owner, 'ops', ops);
EXCEPTION WHEN others THEN
  RAISE WARNING 'f_proj_gt_plan: %', SQLERRM;
  RETURN jsonb_build_object('owner', NULL, 'ops', '[]'::jsonb);
END $$;
