-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_doc_resolve(p_user bigint, p_q text, p_folder bigint, p_last boolean)
-- Origem da definicao atual: 015_documentos.sql (linha 125)
-- Definicoes (migracao:linha), da mais antiga a atual: 015_documentos.sql:125
CREATE OR REPLACE FUNCTION agente.f_doc_resolve(p_user bigint, p_q text, p_folder bigint DEFAULT NULL, p_last boolean DEFAULT true)
RETURNS bigint[] LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $f$
DECLARE v_ids bigint[];
BEGIN
  IF cardinality(f_doc_tokens(p_q)) = 0 THEN
    IF NOT p_last THEN RETURN ARRAY[]::bigint[]; END IF;
    RETURN ARRAY(SELECT id FROM documents WHERE user_id = p_user AND created_at > now() - interval '2 days' ORDER BY created_at DESC, id DESC LIMIT 1);
  END IF;
  v_ids := ARRAY(SELECT doc_id FROM f_doc_search(p_user, p_q, p_folder, 6) WHERE exact_hit);
  IF cardinality(v_ids) = 0 THEN
    v_ids := ARRAY(SELECT doc_id FROM f_doc_search(p_user, p_q, p_folder, 2));
    IF cardinality(v_ids) <> 1 THEN v_ids := ARRAY[]::bigint[]; END IF;
  END IF;
  RETURN v_ids;
END $f$;
