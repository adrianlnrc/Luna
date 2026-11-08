-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_projects_cb(p_user bigint, p_data text)
-- Origem da definicao atual: 017_projetos.sql (linha 380)
-- Definicoes (migracao:linha), da mais antiga a atual: 017_projetos.sql:380
CREATE OR REPLACE FUNCTION f_projects_cb(p_user bigint, p_data text) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE a text := split_part(p_data, ':', 1); v_id bigint; pe project_pending%ROWTYPE; pr projects%ROWTYPE; n integer; ins integer;
BEGIN
  BEGIN v_id := nullif(split_part(p_data, ':', 2), '')::bigint; EXCEPTION WHEN others THEN v_id := NULL; END;
  IF a = 'pjno' THEN
    UPDATE project_pending SET state = 'cancelled' WHERE id = v_id AND user_id = p_user AND state = 'open';
    RETURN jsonb_build_object('text', 'Ok, não gravei as tarefas.', 'kb', 'none');
  END IF;
  IF a = 'pjok' THEN
    SELECT * INTO pe FROM project_pending WHERE id = v_id AND user_id = p_user FOR UPDATE;
    IF NOT FOUND OR pe.state <> 'open' THEN RETURN jsonb_build_object('text', 'Essa lista de tarefas já foi tratada.', 'kb', 'none'); END IF;
    SELECT * INTO pr FROM projects WHERE id = pe.project_id AND user_id = p_user;
    IF NOT FOUND THEN
      UPDATE project_pending SET state = 'cancelled' WHERE id = pe.id;
      RETURN jsonb_build_object('text', 'Esse projeto não existe mais.', 'kb', 'none');
    END IF;
    ins := f_proj_insert_tasks(p_user, pe.project_id, pe.tasks);
    UPDATE project_pending SET state = 'done' WHERE id = pe.id;
    n := jsonb_array_length(pe.tasks);
    RETURN jsonb_build_object('text', 'Gravei ' || ins || ' tarefa' || CASE WHEN ins <> 1 THEN 's' ELSE '' END || ' no projeto ' || pr.name
      || CASE WHEN ins < n THEN ' (' || (n - ins) || ' já existia' || CASE WHEN n - ins > 1 THEN 'm' ELSE '' END || ')' ELSE '' END
      || '. Progresso: ' || f_proj_progress(p_user, pr.id) || '.', 'kb', 'none');
  END IF;
  IF a = 'pjkeep' THEN RETURN jsonb_build_object('text', 'Ok, mantive o projeto.', 'kb', 'none'); END IF;
  IF a = 'pjdel' THEN
    SELECT * INTO pr FROM projects WHERE id = v_id AND user_id = p_user;
    IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Esse projeto já foi apagado.', 'kb', 'none'); END IF;
    DELETE FROM projects WHERE id = pr.id AND user_id = p_user;
    RETURN jsonb_build_object('text', 'Apaguei o projeto ' || pr.name || ' e as tarefas dele.', 'kb', 'none');
  END IF;
  RETURN jsonb_build_object('text', 'Não entendi esse botão.', 'kb', 'none');
EXCEPTION WHEN others THEN
  RAISE WARNING 'f_projects_cb: %', SQLERRM;
  RETURN jsonb_build_object('text', 'Não consegui agora. Tente de novo.', 'kb', 'none');
END $$;
