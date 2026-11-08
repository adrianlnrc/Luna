-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_doc_search(p_user bigint, p_q text, p_folder bigint, p_limit integer)
-- Origem da definicao atual: 015_documentos.sql (linha 69)
-- Definicoes (migracao:linha), da mais antiga a atual: 015_documentos.sql:69
CREATE OR REPLACE FUNCTION agente.f_doc_search(p_user bigint, p_q text, p_folder bigint DEFAULT NULL, p_limit integer DEFAULT 10)
RETURNS TABLE(doc_id bigint, score integer, exact_hit boolean)
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $f$
DECLARE v_tok text[] := f_doc_tokens(p_q); n integer; w_photo boolean; w_pdf boolean; nq text := f_norm(p_q);
BEGIN
  n := cardinality(v_tok);
  w_photo := nq ~ '(^| )(foto|fotos|imagem|imagens|print|prints|screenshot)( |$)';
  w_pdf   := nq ~ '(^| )pdf( |$)';
  RETURN QUERY
  SELECT s.id, s.m, (s.m = n) FROM (
    SELECT d.id, d.created_at,
           (SELECT count(*) FROM unnest(v_tok) t WHERE z.h LIKE '%' || t || '%')::integer AS m,
           ((w_photo AND (d.tg_type = 'photo' OR coalesce(d.mime, '') LIKE 'image/%'))
             OR (w_pdf AND (coalesce(d.mime, '') ILIKE '%pdf' OR coalesce(d.file_name, '') ILIKE '%.pdf'))) AS tm
    FROM documents d LEFT JOIN doc_folders f ON f.id = d.folder_id
    CROSS JOIN LATERAL (SELECT f_norm(d.title || ' ' || coalesce(d.description, '') || ' ' || coalesce(d.file_name, '') || ' ' || coalesce(f.name, '')) AS h) z
    WHERE d.user_id = p_user AND (p_folder IS NULL OR d.folder_id = p_folder)
  ) s
  WHERE (n = 0 AND (NOT (w_photo OR w_pdf) OR s.tm)) OR (n > 0 AND s.m > 0)
  ORDER BY (s.m = n) DESC, s.tm DESC, s.m DESC, s.created_at DESC
  LIMIT greatest(p_limit, 1);
END $f$;
