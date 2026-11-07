-- 037: projetos sem tarefa repetida, lista do usuario gravada direto tambem ao criar o projeto,
--      contagem certa nas respostas e acoes de projeto no bloco ACOES RECENTES do prompt.
--
-- Problemas que motivaram (conversa de 06/11, projeto "ciminas"):
--   * "novo projeto X: a, b e b" mostrava a lista com "b" duas vezes e pedia confirmacao, embora a IA mande
--     task_name=lista_do_usuario (o 019 so gravava direto no add_tasks, nao no create).
--   * O botao "Gravar tarefas" respondia "(1 ja existia)" quando a tarefa so estava repetida na propria lista.
--   * add_tasks com lista_do_usuario dizia "Adicionei N" contando tambem as que ja estavam no projeto.
--   * A resposta do botao nao entra no historico da conversa; sem registro em recent_actions a IA achava que as
--     tarefas ainda esperavam confirmacao e inventava a resposta.
--
-- Desenho: f_projects (wrapper do 025) vira f_projects_pre_037 e f_projects_cb vira f_projects_cb_pre_037.
-- As novas versoes tiram repeticoes antes de tudo, tratam a lista do usuario e o botao pjok aqui mesmo e
-- delegam o resto. Acoes de projeto vao para recent_actions (kind 'project', sem lote: nao entram no "Desfazer tudo").
-- Idempotente. Depende de 017, 019, 025 e 033. Aplicar o SQL basta: o workflow nao muda.
SET search_path TO agente, public;

-- ---------------------------------------------------------------- recent_actions aceita 'project'
ALTER TABLE agente.recent_actions DROP CONSTRAINT IF EXISTS recent_actions_kind_check;
ALTER TABLE agente.recent_actions ADD CONSTRAINT recent_actions_kind_check
  CHECK (kind IN ('reminder', 'event', 'expense', 'note', 'list_item', 'task', 'project'));

-- registra uma acao de projeto para o prompt (sem lote). Nunca lanca erro.
CREATE OR REPLACE FUNCTION agente.f_proj_ra(p_user bigint, p_pid bigint, p_label text) RETURNS void
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
BEGIN
  IF btrim(coalesce(p_label, '')) = '' THEN RETURN; END IF;
  INSERT INTO recent_actions(user_id, batch_id, kind, ref_id, label)
  VALUES (p_user, NULL, 'project', p_pid, left(p_label, 200));
EXCEPTION WHEN others THEN
  NULL;
END $$;

-- ---------------------------------------------------------------- helpers de lista
-- '"a"', '"a" e "b"', '"a", "b" e "c"' (sem repetir)
CREATE OR REPLACE FUNCTION agente.f_proj_qlist(p_titles jsonb) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path TO 'agente', 'public' AS $$
DECLARE a text[];
BEGIN
  SELECT array_agg(t ORDER BY o) INTO a FROM (
    SELECT DISTINCT ON (lower(t)) t, o FROM jsonb_array_elements_text(coalesce(p_titles, '[]'::jsonb)) WITH ORDINALITY AS x(t, o) ORDER BY lower(t), o) s;
  IF a IS NULL THEN RETURN ''; END IF;
  IF cardinality(a) = 1 THEN RETURN '"' || a[1] || '"'; END IF;
  RETURN '"' || array_to_string(a[1:cardinality(a) - 1], '", "') || '" e "' || a[cardinality(a)] || '"';
END $$;

-- tira repetidas (mesmo titulo normalizado) de [{title,due}]. Devolve {tasks:[{title,due}], repeated:[title]}
CREATE OR REPLACE FUNCTION agente.f_proj_dedupe(p_tasks jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE x jsonb; nt text; seen text[] := '{}'; tl jsonb := '[]'::jsonb; rep jsonb := '[]'::jsonb;
BEGIN
  FOR x IN SELECT * FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_tasks) = 'array' THEN p_tasks ELSE '[]'::jsonb END) LOOP
    nt := f_norm(btrim(coalesce(x->>'title', '')));
    IF coalesce(nt, '') = '' THEN CONTINUE; END IF;
    IF nt = ANY(seen) THEN rep := rep || to_jsonb(btrim(x->>'title')); CONTINUE; END IF;
    seen := seen || nt;
    tl := tl || jsonb_build_array(jsonb_build_object('title', left(btrim(x->>'title'), 200), 'due', x->'due'));
  END LOOP;
  RETURN jsonb_build_object('tasks', tl, 'repeated', rep);
END $$;

-- le p.tasks (texto ou "texto|YYYY-MM-DD"). Devolve {tasks:[{title,due}], repeated:[title], past:[title]}
-- (ate 40 tarefas; prazo que ja passou vira sem prazo e entra em past)
CREATE OR REPLACE FUNCTION agente.f_proj_parse_tasks(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE today date := f_fin_today(p_user); e text; parts text[]; ttl text; td date; raw jsonb := '[]'::jsonb; past jsonb := '[]'::jsonb; d jsonb;
BEGIN
  IF jsonb_typeof(p->'tasks') = 'array' THEN
    FOR e IN SELECT CASE WHEN jsonb_typeof(x) = 'string' THEN x #>> '{}' ELSE x::text END FROM jsonb_array_elements(p->'tasks') x LOOP
      e := btrim(coalesce(e, ''));
      IF e = '' THEN CONTINUE; END IF;
      parts := regexp_split_to_array(e, '[|]');
      ttl := left(btrim(parts[1]), 200);
      IF ttl = '' THEN CONTINUE; END IF;
      td := NULL;
      IF array_length(parts, 1) > 1 THEN
        BEGIN td := nullif(btrim(parts[2]), '')::date; EXCEPTION WHEN others THEN td := NULL; END;
        IF td < today THEN past := past || to_jsonb(ttl); td := NULL; END IF;
      END IF;
      raw := raw || jsonb_build_array(jsonb_build_object('title', ttl, 'due', td));
    END LOOP;
  END IF;
  d := f_proj_dedupe(raw);
  IF jsonb_array_length(d->'tasks') > 40 THEN
    d := jsonb_set(d, '{tasks}', (SELECT jsonb_agg(x ORDER BY o) FROM jsonb_array_elements(d->'tasks') WITH ORDINALITY AS t(x, o) WHERE o <= 40));
  END IF;
  RETURN d || jsonb_build_object('past', past);
END $$;

-- de volta ao formato que o f_projects antigo le: ["texto" | "texto|YYYY-MM-DD"]
CREATE OR REPLACE FUNCTION agente.f_proj_tasks_txt(p_tasks jsonb) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path TO 'agente', 'public' AS $$
  SELECT coalesce(jsonb_agg(to_jsonb((x->>'title') || CASE WHEN coalesce(x->>'due', '') <> '' THEN '|' || (x->>'due') ELSE '' END) ORDER BY o), '[]'::jsonb)
    FROM jsonb_array_elements(coalesce(p_tasks, '[]'::jsonb)) WITH ORDINALITY AS t(x, o)
$$;

-- grava [{title,due}] direto no projeto. Devolve {added:[{title,due}], existing:[title]}
CREATE OR REPLACE FUNCTION agente.f_proj_add_direct(p_user bigint, p_pid bigint, p_tasks jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE x jsonb; k integer; d date; added jsonb := '[]'::jsonb; ex jsonb := '[]'::jsonb;
BEGIN
  FOR x IN SELECT * FROM jsonb_array_elements(coalesce(p_tasks, '[]'::jsonb)) LOOP
    BEGIN d := nullif(x->>'due', '')::date; EXCEPTION WHEN others THEN d := NULL; END;
    INSERT INTO project_tasks (project_id, user_id, title, norm_title, due_date)
    VALUES (p_pid, p_user, x->>'title', f_norm(x->>'title'), d)
    ON CONFLICT (project_id, norm_title) DO NOTHING;
    GET DIAGNOSTICS k = ROW_COUNT;
    IF k > 0 THEN added := added || jsonb_build_array(x); ELSE ex := ex || to_jsonb(x->>'title'); END IF;
  END LOOP;
  RETURN jsonb_build_object('added', added, 'existing', ex);
END $$;

-- linhas de aviso (repetidas na lista, ja no projeto, prazo vencido). '' se nada.
CREATE OR REPLACE FUNCTION agente.f_proj_notes(p_rep jsonb, p_ex jsonb, p_past jsonb) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path TO 'agente', 'public' AS $$
DECLARE t text := ''; n integer;
BEGIN
  n := (SELECT count(DISTINCT lower(v)) FROM jsonb_array_elements_text(coalesce(p_rep, '[]'::jsonb)) v);
  IF n > 0 THEN
    t := t || E'\n' || f_proj_qlist(p_rep) || CASE WHEN n > 1 THEN ' vieram repetidas' ELSE ' veio repetida' END || ' na sua lista; ficou uma vez só.';
  END IF;
  n := jsonb_array_length(coalesce(p_ex, '[]'::jsonb));
  IF n > 0 THEN
    t := t || E'\n' || f_proj_qlist(p_ex) || CASE WHEN n > 1 THEN ' já estavam' ELSE ' já estava' END || ' no projeto.';
  END IF;
  n := jsonb_array_length(coalesce(p_past, '[]'::jsonb));
  IF n > 0 THEN
    t := t || E'\n' || 'O prazo de ' || f_proj_qlist(p_past) || ' já tinha passado; gravei sem prazo.';
  END IF;
  RETURN t;
END $$;

-- texto "Adicionei N tarefas ao projeto P:" + linhas + avisos + progresso
CREATE OR REPLACE FUNCTION agente.f_proj_added_text(p_user bigint, p_pid bigint, p_pname text, p_res jsonb, p_rep jsonb, p_past jsonb) RETURNS text
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE today date := f_fin_today(p_user); n integer := jsonb_array_length(p_res->'added'); t text; r record;
BEGIN
  IF n = 0 THEN
    t := 'Nada novo para o projeto ' || p_pname || '.';
  ELSE
    t := 'Adicionei ' || n || ' tarefa' || CASE WHEN n > 1 THEN 's' ELSE '' END || ' ao projeto ' || p_pname || ':';
    FOR r IN SELECT x->>'title' AS title, nullif(x->>'due', '')::date AS due FROM jsonb_array_elements(p_res->'added') x LOOP
      t := t || E'\n- ' || r.title || CASE WHEN r.due IS NOT NULL THEN ' (até ' || f_proj_fmt(r.due, today) || ')' ELSE '' END;
    END LOOP;
  END IF;
  t := t || f_proj_notes(p_rep, p_res->'existing', p_past);
  RETURN t || E'\nProgresso: ' || f_proj_progress(p_user, p_pid) || '.';
END $$;

-- linha curta para ACOES RECENTES
CREATE OR REPLACE FUNCTION agente.f_proj_added_label(p_pname text, p_how text, p_res jsonb, p_rep jsonb) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path TO 'agente', 'public' AS $$
DECLARE n integer := jsonb_array_length(p_res->'added'); t text;
BEGIN
  t := p_pname || ': ' || p_how || ' ' || n || ' tarefa' || CASE WHEN n <> 1 THEN 's' ELSE '' END;
  IF n > 0 THEN
    t := t || ' (' || (SELECT string_agg(x->>'title', ', ' ORDER BY o) FROM jsonb_array_elements(p_res->'added') WITH ORDINALITY AS a(x, o)) || ')';
  END IF;
  IF jsonb_array_length(coalesce(p_rep, '[]'::jsonb)) > 0 THEN t := t || '; repetida na lista: ' || f_proj_qlist(p_rep); END IF;
  IF jsonb_array_length(coalesce(p_res->'existing', '[]'::jsonb)) > 0 THEN t := t || '; já estava no projeto: ' || f_proj_qlist(p_res->'existing'); END IF;
  RETURN t;
END $$;

-- ---------------------------------------------------------------- f_projects
DO $do$
BEGIN
  IF to_regproc('agente.f_projects_pre_037') IS NULL THEN
    ALTER FUNCTION agente.f_projects(bigint, jsonb) RENAME TO f_projects_pre_037;
  END IF;
END $do$;

CREATE OR REPLACE FUNCTION agente.f_projects(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  act text := lower(coalesce(p->>'action', ''));
  nm text := btrim(coalesce(p->>'name', ''));
  lista boolean := lower(btrim(coalesce(p->>'task', ''))) = 'lista_do_usuario';
  has_tasks boolean := jsonb_typeof(p->'tasks') = 'array';
  pr jsonb; tl jsonb := '[]'::jsonb; rep jsonb := '[]'::jsonb; past jsonb := '[]'::jsonb;
  q jsonb := p; r jsonb; res jsonb; pid bigint; pname text; head text; t text; n integer;
BEGIN
  IF p_user IS NULL OR NOT EXISTS (SELECT 1 FROM users WHERE id = p_user) THEN
    RETURN f_projects_pre_037(p_user, p);
  END IF;
  IF has_tasks THEN
    pr := f_proj_parse_tasks(p_user, p);
    tl := pr->'tasks'; rep := pr->'repeated'; past := pr->'past';
    q := jsonb_set(q, '{tasks}', f_proj_tasks_txt(tl));
  END IF;
  n := jsonb_array_length(tl);

  -- ---------- lista do usuario: grava direto (criar projeto com tarefas, ou varias tarefas num projeto)
  IF lista AND ((act = 'create' AND n > 0) OR (act = 'add_tasks' AND n > 1)) THEN
    IF act = 'create' THEN
      r := f_projects_pre_037(p_user, jsonb_set(jsonb_set(q, '{tasks}', '[]'::jsonb), '{task}', '""'::jsonb));
      IF coalesce(r->>'text', '') LIKE 'Projeto criado:%' THEN
        head := split_part(r->>'text', E'\n', 1);
        SELECT id, name INTO pid, pname FROM projects WHERE user_id = p_user AND norm_name = f_norm(left(nm, 120));
      ELSIF coalesce(r->>'text', '') LIKE 'Você já tem um projeto chamado%' THEN
        SELECT id, name INTO pid, pname FROM projects WHERE user_id = p_user AND norm_name = f_norm(left(nm, 120));
        head := 'O projeto ' || pname || ' já existia; coloquei as tarefas nele.';
      ELSE
        RETURN r;   -- nome vazio, prazo vencido, limite de projetos...
      END IF;
      IF pid IS NULL THEN RETURN r; END IF;
    ELSE
      res := f_proj_resolve(p_user, nm);
      IF res ? 'err' THEN RETURN jsonb_build_object('text', res->>'err', 'kb', 'none', 'rid', 0); END IF;
      pid := (res->>'id')::bigint; pname := res->>'name';
    END IF;
    res := f_proj_add_direct(p_user, pid, tl);
    t := f_proj_added_text(p_user, pid, pname, res, rep, past);
    IF head IS NOT NULL THEN t := head || E'\n\n' || t; END IF;
    PERFORM f_proj_ra(p_user, pid, f_proj_added_label(pname,
      CASE WHEN act = 'create' AND head LIKE 'Projeto criado:%' THEN 'projeto criado; gravei direto' ELSE 'gravei direto' END, res, rep));
    RETURN jsonb_build_object('text', t, 'kb', 'none', 'rid', 0);
  END IF;

  -- ---------- demais casos: o fluxo antigo, ja com a lista sem repeticao
  r := f_projects_pre_037(p_user, q);
  t := coalesce(r->>'text', '');

  -- avisos da lista (repetidas / prazo vencido) quando a lista apareceu na resposta
  IF has_tasks AND (r->>'kb' = 'pj_tasks' OR t LIKE 'Tarefa adicionada ao projeto%') THEN
    t := t || f_proj_notes(rep, '[]'::jsonb, past);
    r := jsonb_set(r, '{text}', to_jsonb(t));
  END IF;

  -- registro para o prompt
  IF act = 'create' AND t LIKE 'Projeto criado:%' THEN
    SELECT id, name INTO pid, pname FROM projects WHERE user_id = p_user AND norm_name = f_norm(left(nm, 120));
    PERFORM f_proj_ra(p_user, pid, pname || ': projeto criado'
      || CASE WHEN r->>'kb' = 'pj_tasks' THEN '; ' || n || ' tarefas sugeridas esperando o botão Gravar tarefas (nada gravado ainda)' ELSE ', sem tarefas' END);
  ELSIF act = 'add_tasks' AND r->>'kb' = 'pj_tasks' THEN
    SELECT pp.project_id, pj.name INTO pid, pname FROM project_pending pp JOIN projects pj ON pj.id = pp.project_id
     WHERE pp.id = (r->>'rid')::bigint AND pp.user_id = p_user;
    PERFORM f_proj_ra(p_user, pid, pname || ': ' || n || ' tarefas sugeridas esperando o botão Gravar tarefas (nada gravado ainda)');
  ELSIF act IN ('add_tasks', 'complete_task', 'reopen_task', 'set_urgent', 'set_due', 'rename')
        AND t ~ '^(Tarefa adicionada|Tarefa concluída|Reabri|Marquei como urgente|Tirei a urgência|Prazo d|Renomeei)' THEN
    PERFORM f_proj_ra(p_user, NULL, regexp_replace(split_part(t, E'\n', 1), '\s*Progresso:.*$', ''));
  END IF;
  RETURN r;
END $$;

-- ---------------------------------------------------------------- botoes
DO $do$
BEGIN
  IF to_regproc('agente.f_projects_cb_pre_037') IS NULL THEN
    ALTER FUNCTION agente.f_projects_cb(bigint, text) RENAME TO f_projects_cb_pre_037;
  END IF;
END $do$;

CREATE OR REPLACE FUNCTION agente.f_projects_cb(p_user bigint, p_data text) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  a text := split_part(p_data, ':', 1); v_id bigint; pe project_pending%ROWTYPE; pr projects%ROWTYPE;
  d jsonb; res jsonb; n integer; t text; r jsonb; v_name text;
BEGIN
  BEGIN v_id := nullif(split_part(p_data, ':', 2), '')::bigint; EXCEPTION WHEN others THEN v_id := NULL; END;

  IF a = 'pjok' THEN
    SELECT * INTO pe FROM project_pending WHERE id = v_id AND user_id = p_user FOR UPDATE;
    IF NOT FOUND OR pe.state <> 'open' THEN RETURN f_projects_cb_pre_037(p_user, p_data); END IF;
    SELECT * INTO pr FROM projects WHERE id = pe.project_id AND user_id = p_user;
    IF NOT FOUND THEN RETURN f_projects_cb_pre_037(p_user, p_data); END IF;
    d := f_proj_dedupe(pe.tasks);
    res := f_proj_add_direct(p_user, pr.id, d->'tasks');
    UPDATE project_pending SET state = 'done' WHERE id = pe.id;
    n := jsonb_array_length(res->'added');
    t := CASE WHEN n = 0 THEN 'Nada novo para gravar no projeto ' || pr.name || '.'
              ELSE 'Gravei ' || n || ' tarefa' || CASE WHEN n > 1 THEN 's' ELSE '' END || ' no projeto ' || pr.name || '.' END
         || f_proj_notes(d->'repeated', res->'existing', '[]'::jsonb)
         || E'\nProgresso: ' || f_proj_progress(p_user, pr.id) || '.';
    PERFORM f_proj_ra(p_user, pr.id, f_proj_added_label(pr.name, 'gravei pelo botão Gravar tarefas', res, d->'repeated'));
    RETURN jsonb_build_object('text', t, 'kb', 'none');
  END IF;

  IF a = 'pjno' THEN
    SELECT pj.name INTO v_name FROM project_pending pp JOIN projects pj ON pj.id = pp.project_id
     WHERE pp.id = v_id AND pp.user_id = p_user AND pp.state = 'open';
    r := f_projects_cb_pre_037(p_user, p_data);
    IF v_name IS NOT NULL THEN PERFORM f_proj_ra(p_user, NULL, v_name || ': tarefas sugeridas descartadas (botão Cancelar), nada gravado'); END IF;
    RETURN r;
  END IF;

  IF a = 'pjdel' THEN
    SELECT name INTO v_name FROM projects WHERE id = v_id AND user_id = p_user;
    r := f_projects_cb_pre_037(p_user, p_data);
    IF v_name IS NOT NULL AND coalesce(r->>'text', '') LIKE 'Apaguei%' THEN
      PERFORM f_proj_ra(p_user, NULL, v_name || ': projeto apagado, com as tarefas');
    END IF;
    RETURN r;
  END IF;

  RETURN f_projects_cb_pre_037(p_user, p_data);
EXCEPTION WHEN others THEN
  RAISE WARNING 'f_projects_cb (037): %', SQLERRM;
  RETURN jsonb_build_object('text', 'Não consegui agora. Tente de novo.', 'kb', 'none');
END $$;

-- ---------------------------------------------------------------- ACOES RECENTES: rotulo "projeto"
CREATE OR REPLACE FUNCTION agente.f_recent_actions_txt(p_user bigint) RETURNS text
LANGUAGE sql STABLE SET search_path TO 'agente', 'public' AS $$
  SELECT string_agg(
           '[' || s.id || '] ' ||
           CASE s.kind WHEN 'reminder' THEN 'lembrete' WHEN 'event' THEN 'compromisso' WHEN 'expense' THEN 'gasto'
                       WHEN 'note' THEN 'nota' WHEN 'task' THEN 'tarefa' WHEN 'project' THEN 'projeto' ELSE s.kind END ||
           ': ' || s.label || ' (ha ' ||
           CASE WHEN now() - s.created_at < interval '60 minutes' THEN greatest(1, floor(extract(epoch FROM now() - s.created_at) / 60)::int) || ' min'
                ELSE floor(extract(epoch FROM now() - s.created_at) / 3600)::int || ' h' END || ')',
           E'\n' ORDER BY s.id DESC)
    FROM (SELECT id, kind, label, created_at FROM agente.recent_actions
           WHERE user_id = p_user AND NOT undone AND kind <> 'list_item' AND created_at > now() - interval '24 hours'
           ORDER BY id DESC LIMIT 10) s
$$;

-- correcao por texto: acao de projeto nao e lembrete nem nota
DO $do$
BEGIN
  IF to_regproc('agente.f_recent_correct_pre_037') IS NULL THEN
    ALTER FUNCTION agente.f_recent_correct(bigint, jsonb) RENAME TO f_recent_correct_pre_037;
  END IF;
END $do$;

CREATE OR REPLACE FUNCTION agente.f_recent_correct(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM recent_actions
              WHERE id = CASE WHEN coalesce(p->>'recent_id', '') ~ '^[0-9]+$' THEN (p->>'recent_id')::bigint END
                AND user_id = p_user AND kind = 'project') THEN
    RETURN jsonb_build_object('text', 'Para mexer no projeto, diga por exemplo: "como está o projeto X?", "renomeia o projeto X para Y" ou "muda o prazo do projeto X para 30/11".', 'kb', 'none', 'rid', 0);
  END IF;
  RETURN f_recent_correct_pre_037(p_user, p);
END $$;
