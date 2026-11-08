-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_proj_google_apply(p_user bigint, p_res jsonb)
-- Origem da definicao atual: 030_projetos_google.sql (linha 242)
-- Definicoes (migracao:linha), da mais antiga a atual: 030_projetos_google.sql:242
CREATE OR REPLACE FUNCTION f_proj_google_apply(p_user bigint, p_res jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE
  x jsonb; ref text; kind text; rid bigint; ok boolean; gid text; op text; err text; v integer; gone boolean; k integer;
  n_ok integer := 0; n_fail integer := 0; n_done integer := 0;
BEGIN
  IF p_res IS NULL OR jsonb_typeof(p_res->'results') <> 'array' THEN
    RETURN jsonb_build_object('ok', 0, 'failed', 0, 'done', 0);
  END IF;
  FOR x IN SELECT * FROM jsonb_array_elements(p_res->'results') LOOP
    BEGIN
      ref := coalesce(x->>'ref', ''); op := coalesce(x->>'op', ''); err := coalesce(x->>'error', '');
      ok := coalesce((x->>'ok')::boolean, false); gid := nullif(btrim(coalesce(x->>'gid', '')), '');
      v := coalesce(nullif(x->>'ver', '')::integer, 0);
      gone := err ~* '404|not found|could not be found|notfound';
      IF ref = 'list' THEN
        IF ok THEN n_done := n_done + f_proj_gt_reconcile(p_user, x->'done_ids'); END IF;
        CONTINUE;
      END IF;
      kind := split_part(ref, ':', 1);
      IF split_part(ref, ':', 2) !~ '^[0-9]+$' THEN CONTINUE; END IF;
      rid := split_part(ref, ':', 2)::bigint;

      IF kind = 'x' THEN
        IF ok OR gone THEN DELETE FROM project_google_trash WHERE id = rid AND user_id = p_user; n_ok := n_ok + 1; ELSE n_fail := n_fail + 1; END IF;
        CONTINUE;
      END IF;

      IF ok THEN
        IF op = 'create' THEN
          IF gid IS NULL THEN n_fail := n_fail + 1; CONTINUE; END IF;
          IF kind = 'p' THEN
            UPDATE projects SET google_task_id = gid, google_list = '@default', google_lock_at = NULL, google_synced_at = now(), google_pending = (google_ver <> v)
             WHERE id = rid AND user_id = p_user AND google_task_id IS NULL;
          ELSE
            UPDATE project_tasks SET google_task_id = gid, google_list = '@default', google_lock_at = NULL, google_synced_at = now(), google_pending = (google_ver <> v)
             WHERE id = rid AND user_id = p_user AND google_task_id IS NULL;
          END IF;
          GET DIAGNOSTICS k = ROW_COUNT;
          IF k = 0 THEN   -- a linha foi apagada (ou ja ganhou outro id) enquanto o Google criava: nao deixar tarefa sobrando la
            INSERT INTO project_google_trash (user_id, google_task_id, google_list) VALUES (p_user, gid, '@default');
          END IF;
        ELSE
          IF kind = 'p' THEN
            UPDATE projects SET google_lock_at = NULL, google_synced_at = now(), google_pending = (google_ver <> v) WHERE id = rid AND user_id = p_user;
          ELSE
            UPDATE project_tasks SET google_lock_at = NULL, google_synced_at = now(), google_pending = (google_ver <> v) WHERE id = rid AND user_id = p_user;
          END IF;
        END IF;
        n_ok := n_ok + 1;
      ELSIF gone AND op = 'update' THEN
        -- a tarefa foi apagada la no Google: solta o vinculo (o banco continua valendo) e nao recria sozinho
        IF kind = 'p' THEN
          UPDATE projects SET google_task_id = NULL, google_pending = false, google_lock_at = NULL WHERE id = rid AND user_id = p_user;
        ELSE
          UPDATE project_tasks SET google_task_id = NULL, google_pending = false, google_lock_at = NULL WHERE id = rid AND user_id = p_user;
        END IF;
        n_fail := n_fail + 1;
      ELSE
        n_fail := n_fail + 1;   -- falhou: continua pendente; o travamento de 3 min expira e a proxima chamada tenta de novo
      END IF;
    EXCEPTION WHEN others THEN
      RAISE WARNING 'f_proj_google_apply: %', SQLERRM;
      n_fail := n_fail + 1;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', n_ok, 'failed', n_fail, 'done', n_done);
END $$;
