-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_doc_caption(p_title text, p_folder text)
-- Origem da definicao atual: 015_documentos.sql (linha 183)
-- Definicoes (migracao:linha), da mais antiga a atual: 015_documentos.sql:183
CREATE OR REPLACE FUNCTION agente.f_doc_caption(p_title text, p_folder text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $f$
  SELECT left(regexp_replace(coalesce(p_title, '') || CASE WHEN coalesce(p_folder, '') <> '' THEN ' - ' || p_folder ELSE '' END, '[<>&]', '', 'g'), 200)
$f$;
