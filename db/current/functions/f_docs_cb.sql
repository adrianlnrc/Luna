-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_docs_cb(p_user bigint, p_data text)
-- Origem da definicao atual: 015_documentos.sql (linha 475)
-- Definicoes (migracao:linha), da mais antiga a atual: 015_documentos.sql:475
CREATE OR REPLACE FUNCTION agente.f_docs_cb(p_user bigint, p_data text)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'agente','public' AS $f$
DECLARE a text := split_part(p_data, ':', 1); v_id bigint; d documents%ROWTYPE; fo doc_folders%ROWTYPE; v_cnt integer;
BEGIN
  BEGIN v_id := nullif(split_part(p_data, ':', 2), '')::bigint; EXCEPTION WHEN others THEN v_id := NULL; END;
  IF a = 'dckeep' THEN RETURN jsonb_build_object('text', 'Ok, mantive.', 'kb', 'none'); END IF;
  IF a = 'dcdel' THEN
    SELECT * INTO d FROM documents WHERE id = v_id AND user_id = p_user;
    IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Esse arquivo já foi apagado.', 'kb', 'none'); END IF;
    PERFORM f_doc_unremind(d.id);
    DELETE FROM documents WHERE id = d.id AND user_id = p_user;
    RETURN jsonb_build_object('text', 'Apaguei "' || d.title || '".', 'kb', 'none');
  END IF;
  IF a = 'dcfdel' THEN
    SELECT * INTO fo FROM doc_folders WHERE id = v_id AND user_id = p_user;
    IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Essa pasta já foi apagada.', 'kb', 'none'); END IF;
    SELECT count(*) INTO v_cnt FROM documents WHERE folder_id = fo.id AND user_id = p_user;
    DELETE FROM doc_folders WHERE id = fo.id AND user_id = p_user;
    RETURN jsonb_build_object('text', 'Apaguei a pasta ' || fo.name || '.' || CASE WHEN v_cnt > 0 THEN ' Os ' || v_cnt || ' arquivos continuam guardados, sem pasta.' ELSE '' END, 'kb', 'none');
  END IF;
  RETURN jsonb_build_object('text', 'Não entendi esse botão.', 'kb', 'none');
EXCEPTION WHEN others THEN
  RAISE WARNING 'f_docs_cb: %', SQLERRM;
  RETURN jsonb_build_object('text', 'Não consegui agora. Tente de novo.', 'kb', 'none');
END $f$;
