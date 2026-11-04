-- Fase 8: espelho dos PROJETOS no Google Tarefas (o banco continua sendo a fonte de verdade).
-- Idempotente (IF NOT EXISTS / CREATE OR REPLACE / DROP TRIGGER IF EXISTS). Nao altera f_projects, f_projects_cb nem f_callback.
--
-- Desenho:
--   * projeto = tarefa-PAI na lista padrao do Google Tarefas do dono; tarefa do projeto = SUBTAREFA (1 nivel so).
--   * triggers em projects/project_tasks marcam a linha como google_pending (e sobem google_ver) quando algo que vai ao
--     Google muda (nome, prazo, titulo, urgencia, concluida); apagar linha com google_task_id grava a "lixeira".
--   * f_proj_gt_plan(user, opts) le o que esta pendente e devolve {owner, ops:[...]} para o subworkflow "Agente | Projetos Google".
--   * f_proj_google_apply(user, resultados) grava os ids devolvidos pelo Google e limpa as pendencias (e reconcilia Google -> banco).
--   * so usuarios com users.calendar_key em ('adrian','maria') participam; os demais seguem so no banco.
--   * linhas ANTIGAS (sem google_task_id e sem google_pending) so entram com opts.legacy = true (backfill sob demanda).
SET search_path TO agente, public;

-- ---------- colunas
ALTER TABLE projects      ADD COLUMN IF NOT EXISTS google_task_id   text;
ALTER TABLE projects      ADD COLUMN IF NOT EXISTS google_list      text;
ALTER TABLE projects      ADD COLUMN IF NOT EXISTS google_pending   boolean NOT NULL DEFAULT false;
ALTER TABLE projects      ADD COLUMN IF NOT EXISTS google_ver       integer NOT NULL DEFAULT 0;
ALTER TABLE projects      ADD COLUMN IF NOT EXISTS google_lock_at   timestamptz;
ALTER TABLE projects      ADD COLUMN IF NOT EXISTS google_synced_at timestamptz;
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS google_task_id   text;
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS google_list      text;
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS google_pending   boolean NOT NULL DEFAULT false;
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS google_ver       integer NOT NULL DEFAULT 0;
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS google_lock_at   timestamptz;
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS google_synced_at timestamptz;

CREATE INDEX IF NOT EXISTS projects_gt_id      ON projects (google_task_id)      WHERE google_task_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS project_tasks_gt_id ON project_tasks (google_task_id) WHERE google_task_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS projects_gt_pend      ON projects (user_id)      WHERE google_pending;
CREATE INDEX IF NOT EXISTS project_tasks_gt_pend ON project_tasks (user_id) WHERE google_pending;

-- tarefas do Google que ficaram sem dono no banco (projeto/tarefa apagados): precisam ser apagadas no Google.
-- Sem FK em user_id de proposito (apagar o usuario em cascata tambem passa pelo trigger).
CREATE TABLE IF NOT EXISTS project_google_trash (
  id             bigserial PRIMARY KEY,
  user_id        bigint NOT NULL,
  google_task_id text NOT NULL,
  google_list    text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  lock_at        timestamptz
);
CREATE INDEX IF NOT EXISTS project_google_trash_user ON project_google_trash (user_id);

-- ---------- dono do Google (null = usuario sem Google Tarefas conectado)
CREATE OR REPLACE FUNCTION f_proj_gt_owner(p_user bigint) RETURNS text
LANGUAGE sql STABLE SET search_path TO 'agente','public' AS $$
  SELECT u.calendar_key FROM users u WHERE u.id = p_user AND u.calendar_key IN ('adrian', 'maria')
$$;

-- titulo da subtarefa: urgencia vira marcador no titulo (o Google Tarefas nao tem prioridade)
CREATE OR REPLACE FUNCTION f_proj_gtitle(p_urgent boolean, p_title text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT left(CASE WHEN p_urgent THEN '🔴 ' ELSE '' END || coalesce(p_title, ''), 1000)
$$;

-- ---------- triggers: marcam o que precisa ir ao Google
CREATE OR REPLACE FUNCTION f_proj_gt_trg_p() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
BEGIN
  IF coalesce(current_setting('agente.gsync', true), '') = 'on' THEN RETURN NEW; END IF;
  IF f_proj_gt_owner(NEW.user_id) IS NULL THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.google_pending := true; NEW.google_ver := 1;
  ELSIF NEW.name IS DISTINCT FROM OLD.name OR NEW.due_date IS DISTINCT FROM OLD.due_date THEN
    NEW.google_pending := true; NEW.google_ver := OLD.google_ver + 1;
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION f_proj_gt_trg_t() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
BEGIN
  IF coalesce(current_setting('agente.gsync', true), '') = 'on' THEN RETURN NEW; END IF;
  IF f_proj_gt_owner(NEW.user_id) IS NULL THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.google_pending := true; NEW.google_ver := 1;
  ELSIF NEW.title IS DISTINCT FROM OLD.title OR NEW.due_date IS DISTINCT FROM OLD.due_date
     OR NEW.urgent IS DISTINCT FROM OLD.urgent OR NEW.done IS DISTINCT FROM OLD.done THEN
    NEW.google_pending := true; NEW.google_ver := OLD.google_ver + 1;
  END IF;
  RETURN NEW;
END $$;

-- a tarefa nova ou (re)aberta/concluida muda o estado da tarefa-pai (concluida quando todas as subtarefas estao feitas)
CREATE OR REPLACE FUNCTION f_proj_gt_trg_t_parent() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
BEGIN
  IF coalesce(current_setting('agente.gsync', true), '') = 'on' THEN RETURN NULL; END IF;
  IF TG_OP = 'UPDATE' AND NEW.done IS NOT DISTINCT FROM OLD.done THEN RETURN NULL; END IF;
  UPDATE projects SET google_pending = true, google_ver = google_ver + 1
   WHERE id = NEW.project_id AND user_id = NEW.user_id AND google_task_id IS NOT NULL AND f_proj_gt_owner(user_id) IS NOT NULL;
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION f_proj_gt_trg_del() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
BEGIN
  IF OLD.google_task_id IS NOT NULL THEN
    INSERT INTO project_google_trash (user_id, google_task_id, google_list) VALUES (OLD.user_id, OLD.google_task_id, OLD.google_list);
  END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS projects_gt_biu ON projects;
CREATE TRIGGER projects_gt_biu BEFORE INSERT OR UPDATE ON projects FOR EACH ROW EXECUTE FUNCTION f_proj_gt_trg_p();
DROP TRIGGER IF EXISTS project_tasks_gt_biu ON project_tasks;
CREATE TRIGGER project_tasks_gt_biu BEFORE INSERT OR UPDATE ON project_tasks FOR EACH ROW EXECUTE FUNCTION f_proj_gt_trg_t();
DROP TRIGGER IF EXISTS project_tasks_gt_parent ON project_tasks;
CREATE TRIGGER project_tasks_gt_parent AFTER INSERT OR UPDATE OF done ON project_tasks FOR EACH ROW EXECUTE FUNCTION f_proj_gt_trg_t_parent();
DROP TRIGGER IF EXISTS projects_gt_ad ON projects;
CREATE TRIGGER projects_gt_ad AFTER DELETE ON projects FOR EACH ROW EXECUTE FUNCTION f_proj_gt_trg_del();
DROP TRIGGER IF EXISTS project_tasks_gt_ad ON project_tasks;
CREATE TRIGGER project_tasks_gt_ad AFTER DELETE ON project_tasks FOR EACH ROW EXECUTE FUNCTION f_proj_gt_trg_del();

-- ============================================================ plano de operacoes no Google
-- p_opts: {push: true (default), list: false, legacy: false, limit: 40}
--   push   = envia o que esta pendente (criar/atualizar/apagar)
--   list   = inclui a leitura das tarefas concluidas no Google (reconciliacao Google -> banco), so se houver tarefa aberta espelhada
--   legacy = marca como pendentes os projetos/tarefas antigos que nunca foram ao Google (BACKFILL; so sob demanda)
-- Devolve {owner, ops:[{op,ref,kind,ver,seq,...}]}. Cada linha incluida fica "travada" por 3 min (evita duplicar em chamadas paralelas).
-- Tarefa de projeto sem espelho so e criada se o projeto ja tem google_task_id OU esta sendo criado neste mesmo plano (parent_seq).
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

-- ---------- reconciliacao Google -> banco: tarefas concluidas no Google viram done no banco
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

-- ---------- grava o que o subworkflow devolveu: {results:[{ref,op,ver,ok,gid,error,done_ids}]}
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

-- usuarios elegiveis ao backfill (para o workflow manual)
CREATE OR REPLACE FUNCTION f_proj_gt_users() RETURNS jsonb
LANGUAGE sql STABLE SET search_path TO 'agente','public' AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('user_id', u.id, 'calendar_key', u.calendar_key) ORDER BY u.id), '[]'::jsonb)
    FROM users u WHERE u.calendar_key IN ('adrian', 'maria') AND u.onboarding_step = 'done'
$$;

-- quanto falta espelhar (somente leitura; use antes do backfill para ver o tamanho): projetos/tarefas abertas sem google_task_id
CREATE OR REPLACE FUNCTION f_proj_gt_backfill_count(p_user bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE sql STABLE SET search_path TO 'agente','public' AS $$
  SELECT jsonb_build_object(
    'projects_sem_google', (SELECT count(*) FROM projects p WHERE (p_user IS NULL OR p.user_id = p_user) AND p.google_task_id IS NULL AND f_proj_gt_owner(p.user_id) IS NOT NULL),
    'tasks_abertas_sem_google', (SELECT count(*) FROM project_tasks t WHERE (p_user IS NULL OR t.user_id = p_user) AND t.google_task_id IS NULL AND NOT t.done AND f_proj_gt_owner(t.user_id) IS NOT NULL),
    'pendentes', (SELECT count(*) FROM projects p WHERE (p_user IS NULL OR p.user_id = p_user) AND p.google_pending)
                 + (SELECT count(*) FROM project_tasks t WHERE (p_user IS NULL OR t.user_id = p_user) AND t.google_pending),
    'lixeira', (SELECT count(*) FROM project_google_trash WHERE p_user IS NULL OR user_id = p_user))
$$;
