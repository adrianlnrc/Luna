-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_docs_file(p_user bigint, p_req jsonb)
-- Origem da definicao atual: 015_documentos.sql (linha 262)
-- Definicoes (migracao:linha), da mais antiga a atual: 015_documentos.sql:262
CREATE OR REPLACE FUNCTION agente.f_docs_file(p_user bigint, p_req jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'agente','public' AS $f$
DECLARE v_cap text := coalesce(p_req->>'caption', ''); v_size bigint; v_fname text := coalesce(p_req->>'file_name', ''); v_folder text; m text[]; v_res jsonb; v_label text; v_mb text;
BEGIN
  IF p_user IS NULL OR p_user <= 0 THEN RETURN jsonb_build_object('text', 'Não consegui identificar você.', 'kb', 'none', 'rid', 0); END IF;
  v_size := CASE WHEN coalesce(p_req->>'file_size', '') ~ '^[0-9]{1,15}$' THEN (p_req->>'file_size')::bigint END;
  IF v_size IS NOT NULL AND v_size > 52428800 THEN
    RETURN jsonb_build_object('text', 'Esse arquivo passa de 50 MB, o limite que o Telegram permite para eu guardar e reenviar. Mande um menor.', 'kb', 'none', 'rid', 0);
  END IF;
  PERFORM f_docs_inbox_note(p_user, p_req);
  IF f_norm(v_cap) ~ '(^| )(guarda|guardar|guarde|salva|salvar|salve|arquiva|arquivar|arquive)( |$)' THEN
    m := regexp_match(v_cap, 'pasta[[:space:]]+(?:d[aeo]s?[[:space:]]+)?([^,.;!?]+)', 'i');
    v_res := f_docs_save(p_user, jsonb_build_object('file_id', p_req->>'file_id', 'folder', btrim(coalesce(m[1], '')), 'query', v_cap, 'single', 'true'));
    RETURN v_res;
  END IF;
  v_label := CASE WHEN v_fname <> '' THEN '"' || v_fname || '"' ELSE 'o arquivo' END;
  v_mb := CASE WHEN v_size IS NOT NULL THEN ' (' || round(v_size / 1048576.0, 1)::text || ' MB)' ELSE '' END;
  RETURN jsonb_build_object('text', 'Recebi ' || v_label || v_mb || '. Quer que eu guarde? Diga "guarda" (pode dizer a pasta, por exemplo: "guarda na pasta Casa"). Depois é só pedir: "acha o ' || coalesce(nullif(regexp_replace(v_fname, '\.[A-Za-z0-9]{1,6}$', ''), ''), 'arquivo') || '".', 'kb', 'none', 'rid', 0);
EXCEPTION WHEN others THEN
  RAISE WARNING 'f_docs_file: %', SQLERRM;
  RETURN jsonb_build_object('text', 'Não consegui processar o arquivo agora. Tente de novo.', 'kb', 'none', 'rid', 0);
END $f$;
