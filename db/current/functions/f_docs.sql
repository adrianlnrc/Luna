-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_docs(p_user bigint, p_req jsonb)
-- Origem da definicao atual: 015_documentos.sql (linha 288)
-- Definicoes (migracao:linha), da mais antiga a atual: 015_documentos.sql:288
CREATE OR REPLACE FUNCTION agente.f_docs(p_user bigint, p_req jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'agente','public' AS $f$
DECLARE
  v_act text := lower(btrim(coalesce(p_req->>'action', '')));
  v_title text := btrim(coalesce(p_req->>'title', '')); v_q text := btrim(coalesce(p_req->>'query', ''));
  v_folder text := btrim(coalesce(p_req->>'folder', '')); v_to text := btrim(coalesce(p_req->>'folder_to', ''));
  v_exp date := f_safe_date(p_req->>'expires_on'); v_days integer := nullif(p_req->>'alert_days', '')::integer;
  v_fid bigint; v_ids bigint[]; v_files jsonb; v_txt text; v_n integer; v_cnt integer; d documents%ROWTYPE; fo doc_folders%ROWTYPE;
  v_names text; v_created boolean; v_tid bigint; v_lim integer; v_ex integer; v_tz text;
BEGIN
  IF p_user IS NULL THEN RETURN jsonb_build_object('text', 'Não consegui identificar você.', 'kb', 'none', 'rid', 0); END IF;
  SELECT timezone INTO v_tz FROM users WHERE id = p_user;
  IF v_act = '' THEN
    v_act := CASE WHEN v_exp IS NOT NULL THEN 'expiry_set' WHEN v_q <> '' THEN 'find' ELSE '' END;
  END IF;

  -- ===== guardar =====
  IF v_act = 'save' THEN
    RETURN f_docs_save(p_user, p_req);

  -- ===== criar pasta =====
  ELSIF v_act = 'create_folder' THEN
    IF v_folder = '' THEN v_folder := coalesce(nullif(v_to, ''), v_title); END IF;
    IF f_norm(v_folder) = '' THEN RETURN jsonb_build_object('text', 'Qual o nome da pasta?', 'kb', 'none', 'rid', 0); END IF;
    IF (SELECT count(*) FROM doc_folders WHERE user_id = p_user) >= 100 THEN
      RETURN jsonb_build_object('text', 'Você já tem 100 pastas, que é o limite. Apague alguma antes de criar outra.', 'kb', 'none', 'rid', 0);
    END IF;
    SELECT o_id, o_created INTO v_fid, v_created FROM f_doc_folder_ensure(p_user, v_folder);
    SELECT * INTO fo FROM doc_folders WHERE id = v_fid;
    RETURN jsonb_build_object('text', CASE WHEN v_created THEN 'Criei a pasta ' || fo.name || '. Para guardar nela, mande o arquivo e diga "guarda na pasta ' || fo.name || '".' ELSE 'Você já tem a pasta ' || fo.name || '.' END, 'kb', 'none', 'rid', 0);

  -- ===== listar pastas / conteudo de uma pasta =====
  ELSIF v_act = 'list_folders' THEN
    IF v_folder <> '' THEN
      v_fid := f_doc_folder_find(p_user, v_folder);
      IF v_fid IS NULL THEN
        RETURN jsonb_build_object('text', 'Não achei a pasta "' || v_folder || '".' || coalesce(E'\nSuas pastas: ' || (SELECT string_agg(name, ', ' ORDER BY name) FROM doc_folders WHERE user_id = p_user), ''), 'kb', 'none', 'rid', 0);
      END IF;
      SELECT * INTO fo FROM doc_folders WHERE id = v_fid AND user_id = p_user;
      SELECT count(*) INTO v_cnt FROM documents WHERE user_id = p_user AND folder_id = v_fid;
      IF v_cnt = 0 THEN RETURN jsonb_build_object('text', 'A pasta ' || fo.name || ' está vazia.', 'kb', 'none', 'rid', 0); END IF;
      SELECT string_agg('- ' || x.title || CASE WHEN x.expires_on IS NOT NULL THEN ' (vence ' || to_char(x.expires_on, 'DD/MM/YYYY') || ')' ELSE '' END, E'\n' ORDER BY x.created_at DESC)
        INTO v_names FROM (SELECT title, expires_on, created_at FROM documents WHERE user_id = p_user AND folder_id = v_fid ORDER BY created_at DESC LIMIT 25) x;
      RETURN jsonb_build_object('text', 'Pasta ' || fo.name || ' (' || v_cnt || CASE WHEN v_cnt = 1 THEN ' arquivo' ELSE ' arquivos' END || '):' || E'\n' || v_names
        || CASE WHEN v_cnt > 25 THEN E'\n... e mais ' || (v_cnt - 25) ELSE '' END || E'\nPara receber os arquivos, diga "me manda a pasta ' || fo.name || '".', 'kb', 'none', 'rid', 0);
    END IF;
    SELECT count(*) INTO v_cnt FROM documents WHERE user_id = p_user AND folder_id IS NULL;
    SELECT string_agg('- ' || f.name || ' (' || (SELECT count(*) FROM documents dd WHERE dd.folder_id = f.id AND dd.user_id = p_user) || ')', E'\n' ORDER BY f.name)
      INTO v_names FROM doc_folders f WHERE f.user_id = p_user;
    IF v_names IS NULL AND v_cnt = 0 THEN
      RETURN jsonb_build_object('text', 'Você ainda não guardou nada. Mande um arquivo ou foto e diga "guarda" (pode dizer a pasta).', 'kb', 'none', 'rid', 0);
    END IF;
    RETURN jsonb_build_object('text', 'Suas pastas:' || coalesce(E'\n' || v_names, E'\n(nenhuma pasta criada)') || CASE WHEN v_cnt > 0 THEN E'\nSem pasta: ' || v_cnt || CASE WHEN v_cnt = 1 THEN ' arquivo' ELSE ' arquivos' END ELSE '' END, 'kb', 'none', 'rid', 0);

  -- ===== achar (e mandar de volta) =====
  ELSIF v_act = 'find' THEN
    v_fid := CASE WHEN v_folder <> '' THEN f_doc_folder_find(p_user, v_folder) END;
    IF v_q = '' THEN v_q := v_title; END IF;
    IF v_q = '' AND v_folder <> '' THEN v_q := ''; END IF;
    IF v_folder <> '' AND v_fid IS NULL AND f_norm(v_q) = '' THEN
      v_q := v_folder;
    END IF;
    SELECT count(*) INTO v_cnt FROM f_doc_search(p_user, v_q, v_fid, 50) WHERE exact_hit;
    IF v_cnt > 0 THEN
      v_ex := 1;
    ELSE
      SELECT count(*) INTO v_cnt FROM f_doc_search(p_user, v_q, v_fid, 50);
      v_ex := 0;
    END IF;
    IF v_cnt = 0 THEN
      RETURN jsonb_build_object('text', 'Não achei nenhum arquivo parecido com "' || coalesce(nullif(v_q, ''), v_folder) || '". Diga "minhas pastas" para ver o que está guardado.', 'kb', 'none', 'rid', 0);
    END IF;
    SELECT jsonb_agg(jsonb_build_object('file_id', x.file_id, 'tg_type', x.tg_type, 'caption', f_doc_caption(x.title, x.fname)) ORDER BY x.ord),
           string_agg(x.title, ', ' ORDER BY x.ord) FILTER (WHERE x.ord > 3)
      INTO v_files, v_names
      FROM (SELECT d2.file_id, d2.tg_type, d2.title, fo2.name AS fname, row_number() OVER (ORDER BY s.exact_hit DESC, s.score DESC, d2.created_at DESC) AS ord
              FROM f_doc_search(p_user, v_q, v_fid, 50) s JOIN documents d2 ON d2.id = s.doc_id AND d2.user_id = p_user LEFT JOIN doc_folders fo2 ON fo2.id = d2.folder_id
             WHERE (v_ex = 0 OR s.exact_hit)) x;
    -- v_files so com os 3 primeiros
    v_files := (SELECT coalesce(jsonb_agg(e), '[]'::jsonb) FROM (SELECT e FROM jsonb_array_elements(v_files) WITH ORDINALITY t(e, i) WHERE i <= 3 ORDER BY i) q);
    RETURN jsonb_build_object('text',
      CASE WHEN v_ex = 1 THEN CASE WHEN v_cnt = 1 THEN 'Achei 1 arquivo.' ELSE 'Achei ' || v_cnt || ' arquivos' || CASE WHEN v_cnt > 3 THEN '; mandei os 3 mais recentes.' ELSE '.' END END
           ELSE 'Não achei exatamente, mas tem ' || v_cnt || CASE WHEN v_cnt = 1 THEN ' arquivo parecido' ELSE ' arquivos parecidos' END || CASE WHEN v_cnt > 3 THEN ' (mandei 3)' ELSE '' END || '.' END
      || CASE WHEN v_names IS NOT NULL THEN E'\nOutros: ' || v_names || E'.\nDiga o nome para eu mandar.' ELSE '' END,
      'kb', 'none', 'rid', 0, 'files', v_files);

  -- ===== mandar a pasta (ou tudo de uma busca) =====
  ELSIF v_act = 'send_folder' THEN
    IF v_folder = '' THEN v_folder := v_q; END IF;
    IF v_folder = '' THEN v_folder := v_title; END IF;
    v_fid := f_doc_folder_find(p_user, v_folder);
    v_lim := 10;
    IF v_fid IS NOT NULL THEN
      SELECT * INTO fo FROM doc_folders WHERE id = v_fid AND user_id = p_user;
      SELECT count(*) INTO v_cnt FROM documents WHERE user_id = p_user AND folder_id = v_fid;
      IF v_cnt = 0 THEN RETURN jsonb_build_object('text', 'A pasta ' || fo.name || ' está vazia.', 'kb', 'none', 'rid', 0); END IF;
      SELECT jsonb_agg(jsonb_build_object('file_id', x.file_id, 'tg_type', x.tg_type, 'caption', f_doc_caption(x.title, NULL)) ORDER BY x.created_at, x.id)
        INTO v_files FROM (SELECT id, file_id, tg_type, title, created_at FROM documents WHERE user_id = p_user AND folder_id = v_fid ORDER BY created_at DESC, id DESC LIMIT v_lim) x;
      RETURN jsonb_build_object('text', 'Pasta ' || fo.name || ': ' || CASE WHEN v_cnt > v_lim THEN 'mandei os ' || v_lim || ' mais recentes de ' || v_cnt || '.' WHEN v_cnt = 1 THEN 'mandei o único arquivo.' ELSE 'mandei os ' || v_cnt || ' arquivos.' END, 'kb', 'none', 'rid', 0, 'files', v_files);
    END IF;
    SELECT count(*) INTO v_cnt FROM f_doc_search(p_user, v_folder, NULL, 50) WHERE exact_hit;
    IF v_cnt = 0 THEN
      RETURN jsonb_build_object('text', 'Não achei uma pasta nem arquivos com "' || v_folder || '".' || coalesce(E'\nSuas pastas: ' || (SELECT string_agg(name, ', ' ORDER BY name) FROM doc_folders WHERE user_id = p_user), ''), 'kb', 'none', 'rid', 0);
    END IF;
    SELECT jsonb_agg(jsonb_build_object('file_id', x.file_id, 'tg_type', x.tg_type, 'caption', f_doc_caption(x.title, x.fname)) ORDER BY x.created_at, x.id)
      INTO v_files FROM (SELECT d2.id, d2.file_id, d2.tg_type, d2.title, d2.created_at, fo2.name AS fname
                           FROM f_doc_search(p_user, v_folder, NULL, v_lim) s JOIN documents d2 ON d2.id = s.doc_id AND d2.user_id = p_user LEFT JOIN doc_folders fo2 ON fo2.id = d2.folder_id
                          WHERE s.exact_hit) x;
    RETURN jsonb_build_object('text', 'Achei ' || v_cnt || CASE WHEN v_cnt = 1 THEN ' arquivo' ELSE ' arquivos' END || ' sobre "' || v_folder || '"' || CASE WHEN v_cnt > v_lim THEN '; mandei os ' || v_lim || ' mais relevantes.' ELSE '.' END, 'kb', 'none', 'rid', 0, 'files', v_files);

  -- ===== mover =====
  ELSIF v_act = 'move' THEN
    IF v_to = '' THEN v_to := v_folder; END IF;
    IF f_norm(v_to) = '' THEN RETURN jsonb_build_object('text', 'Para qual pasta eu movo?', 'kb', 'none', 'rid', 0); END IF;
    v_ids := f_doc_resolve(p_user, v_q, NULL, true);
    IF cardinality(v_ids) = 0 THEN RETURN jsonb_build_object('text', 'Não achei esse arquivo. Diga o nome dele (ou "minhas pastas" para ver o que está guardado).', 'kb', 'none', 'rid', 0); END IF;
    IF cardinality(v_ids) > 1 THEN
      RETURN jsonb_build_object('text', 'Achei mais de um:' || (SELECT string_agg(E'\n- ' || title, '' ORDER BY created_at DESC) FROM documents WHERE id = ANY (v_ids) AND user_id = p_user) || E'\nDiga o nome com mais detalhe.', 'kb', 'none', 'rid', 0);
    END IF;
    SELECT o_id, o_created INTO v_tid, v_created FROM f_doc_folder_ensure(p_user, v_to);
    UPDATE documents SET folder_id = v_tid WHERE id = v_ids[1] AND user_id = p_user RETURNING * INTO d;
    RETURN jsonb_build_object('text', 'Movi "' || d.title || '" para a pasta ' || (SELECT name FROM doc_folders WHERE id = v_tid) || CASE WHEN v_created THEN ' (criei a pasta).' ELSE '.' END, 'kb', 'none', 'rid', 0);

  -- ===== renomear (arquivo ou pasta) =====
  ELSIF v_act = 'rename' THEN
    IF v_q = '' AND v_folder <> '' THEN
      v_to := coalesce(nullif(v_to, ''), v_title);
      v_fid := f_doc_folder_find(p_user, v_folder);
      IF v_fid IS NULL THEN RETURN jsonb_build_object('text', 'Não achei a pasta "' || v_folder || '".', 'kb', 'none', 'rid', 0); END IF;
      IF f_norm(v_to) = '' THEN RETURN jsonb_build_object('text', 'Qual o novo nome da pasta?', 'kb', 'none', 'rid', 0); END IF;
      v_to := left(upper(left(btrim(v_to), 1)) || substr(btrim(v_to), 2), 60);
      IF EXISTS (SELECT 1 FROM doc_folders WHERE user_id = p_user AND name_norm = f_norm(v_to) AND id <> v_fid) THEN
        RETURN jsonb_build_object('text', 'Já existe uma pasta com o nome ' || v_to || '.', 'kb', 'none', 'rid', 0);
      END IF;
      UPDATE doc_folders SET name = v_to, name_norm = f_norm(v_to) WHERE id = v_fid AND user_id = p_user RETURNING * INTO fo;
      RETURN jsonb_build_object('text', 'Renomeei a pasta para ' || fo.name || '.', 'kb', 'none', 'rid', 0);
    END IF;
    IF v_title = '' THEN v_title := v_to; END IF;
    IF v_title = '' THEN RETURN jsonb_build_object('text', 'Qual o novo nome?', 'kb', 'none', 'rid', 0); END IF;
    v_ids := f_doc_resolve(p_user, v_q, NULL, true);
    IF cardinality(v_ids) = 0 THEN RETURN jsonb_build_object('text', 'Não achei esse arquivo. Diga o nome atual dele.', 'kb', 'none', 'rid', 0); END IF;
    IF cardinality(v_ids) > 1 THEN
      RETURN jsonb_build_object('text', 'Achei mais de um:' || (SELECT string_agg(E'\n- ' || title, '' ORDER BY created_at DESC) FROM documents WHERE id = ANY (v_ids) AND user_id = p_user) || E'\nDiga o nome atual com mais detalhe.', 'kb', 'none', 'rid', 0);
    END IF;
    SELECT * INTO d FROM documents WHERE id = v_ids[1] AND user_id = p_user;
    UPDATE documents SET title = left(v_title, 80) WHERE id = d.id AND user_id = p_user;
    IF d.reminder_id IS NOT NULL AND d.expires_on IS NOT NULL THEN
      UPDATE reminders SET title = 'Vencimento: ' || left(v_title, 80) || ' (vence em ' || to_char(d.expires_on, 'DD/MM/YYYY') || ')' WHERE id = d.reminder_id AND status = 'pending';
    END IF;
    RETURN jsonb_build_object('text', 'Renomeei "' || d.title || '" para "' || left(v_title, 80) || '".', 'kb', 'none', 'rid', 0);

  -- ===== apagar (com confirmacao) =====
  ELSIF v_act = 'delete' THEN
    IF v_q = '' AND v_folder <> '' THEN
      v_fid := f_doc_folder_find(p_user, v_folder);
      IF v_fid IS NULL THEN RETURN jsonb_build_object('text', 'Não achei a pasta "' || v_folder || '".', 'kb', 'none', 'rid', 0); END IF;
      SELECT * INTO fo FROM doc_folders WHERE id = v_fid AND user_id = p_user;
      SELECT count(*) INTO v_cnt FROM documents WHERE user_id = p_user AND folder_id = v_fid;
      RETURN jsonb_build_object('text', 'Apago a pasta ' || fo.name || '?' || CASE WHEN v_cnt > 0 THEN ' Os ' || v_cnt || ' arquivos dela continuam guardados, só ficam sem pasta.' ELSE '' END, 'kb', 'dc_fdel', 'rid', v_fid);
    END IF;
    IF cardinality(f_doc_tokens(v_q)) = 0 THEN RETURN jsonb_build_object('text', 'Qual arquivo eu apago? Diga o nome dele.', 'kb', 'none', 'rid', 0); END IF;
    v_ids := f_doc_resolve(p_user, v_q, NULL, false);
    IF cardinality(v_ids) = 0 THEN RETURN jsonb_build_object('text', 'Não achei esse arquivo.', 'kb', 'none', 'rid', 0); END IF;
    IF cardinality(v_ids) > 1 THEN
      RETURN jsonb_build_object('text', 'Achei mais de um:' || (SELECT string_agg(E'\n- ' || title, '' ORDER BY created_at DESC) FROM documents WHERE id = ANY (v_ids) AND user_id = p_user) || E'\nDiga o nome com mais detalhe para eu apagar o certo.', 'kb', 'none', 'rid', 0);
    END IF;
    SELECT * INTO d FROM documents WHERE id = v_ids[1] AND user_id = p_user;
    RETURN jsonb_build_object('text', 'Apago "' || d.title || '"? Isso tira o arquivo da sua lista' || CASE WHEN d.expires_on IS NOT NULL THEN ' e cancela o aviso de vencimento' ELSE '' END || '.', 'kb', 'dc_del', 'rid', d.id);

  -- ===== validade + aviso =====
  ELSIF v_act = 'expiry_set' THEN
    IF v_exp IS NULL THEN RETURN jsonb_build_object('text', 'Quando ele vence? Me diga a data, por exemplo: "vence em 30/11/2026".', 'kb', 'none', 'rid', 0); END IF;
    v_ids := f_doc_resolve(p_user, coalesce(nullif(v_q, ''), v_title), NULL, true);
    IF cardinality(v_ids) = 0 THEN RETURN jsonb_build_object('text', 'Não achei esse documento. Guarde primeiro (mande o arquivo e diga "guarda") ou diga o nome dele.', 'kb', 'none', 'rid', 0); END IF;
    IF cardinality(v_ids) > 1 THEN
      RETURN jsonb_build_object('text', 'Achei mais de um:' || (SELECT string_agg(E'\n- ' || title, '' ORDER BY created_at DESC) FROM documents WHERE id = ANY (v_ids) AND user_id = p_user) || E'\nDiga o nome com mais detalhe.', 'kb', 'none', 'rid', 0);
    END IF;
    RETURN jsonb_build_object('text', f_doc_expiry_apply(p_user, v_ids[1], v_exp, coalesce(v_days, 7)), 'kb', 'none', 'rid', 0);
  END IF;

  RETURN jsonb_build_object('text', 'Não entendi o que fazer com o arquivo. Exemplos: "guarda essa foto na pasta Casa", "acha a apólice do carro", "me manda tudo da reforma", "minhas pastas", "me avisa antes do alvará vencer".', 'kb', 'none', 'rid', 0);
EXCEPTION WHEN others THEN
  RAISE WARNING 'f_docs: %', SQLERRM;
  RETURN jsonb_build_object('text', 'Não consegui agora. Tente de novo.', 'kb', 'none', 'rid', 0);
END $f$;
