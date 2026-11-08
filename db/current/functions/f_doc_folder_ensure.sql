-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_doc_folder_ensure(p_user bigint, p_name text, OUT o_id bigint, OUT o_created boolean)
-- Origem da definicao atual: 015_documentos.sql (linha 106)
-- Definicoes (migracao:linha), da mais antiga a atual: 015_documentos.sql:106
CREATE OR REPLACE FUNCTION agente.f_doc_folder_ensure(p_user bigint, p_name text, OUT o_id bigint, OUT o_created boolean)
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $f$
DECLARE v_name text := btrim(regexp_replace(coalesce(p_name, ''), '[[:space:]]+', ' ', 'g')); v_norm text;
BEGIN
  v_name := left(v_name, 60);
  v_name := upper(left(v_name, 1)) || substr(v_name, 2);
  v_norm := f_norm(v_name);
  o_created := false;
  IF v_norm = '' THEN o_id := NULL; RETURN; END IF;
  SELECT id INTO o_id FROM doc_folders WHERE user_id = p_user AND name_norm = v_norm;
  IF o_id IS NULL THEN o_id := f_doc_folder_find(p_user, v_name); END IF;
  IF o_id IS NULL THEN
    INSERT INTO doc_folders(user_id, name, name_norm) VALUES (p_user, v_name, v_norm)
    ON CONFLICT (user_id, name_norm) DO NOTHING RETURNING id INTO o_id;
    IF o_id IS NULL THEN SELECT id INTO o_id FROM doc_folders WHERE user_id = p_user AND name_norm = v_norm; ELSE o_created := true; END IF;
  END IF;
END $f$;
