-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_doc_folder_find(p_user bigint, p_name text)
-- Origem da definicao atual: 015_documentos.sql (linha 93)
-- Definicoes (migracao:linha), da mais antiga a atual: 015_documentos.sql:93
CREATE OR REPLACE FUNCTION agente.f_doc_folder_find(p_user bigint, p_name text)
RETURNS bigint LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $f$
DECLARE v_raw text := f_norm(p_name); v_clean text; v_id bigint;
BEGIN
  IF v_raw = '' THEN RETURN NULL; END IF;
  v_clean := coalesce(nullif(array_to_string(f_doc_tokens(p_name), ' '), ''), v_raw);
  SELECT id INTO v_id FROM doc_folders
   WHERE user_id = p_user AND (name_norm = v_raw OR name_norm LIKE '%' || v_clean || '%' OR v_raw LIKE '%' || name_norm || '%')
   ORDER BY (name_norm = v_raw) DESC, length(name_norm) ASC LIMIT 1;
  RETURN v_id;
END $f$;
