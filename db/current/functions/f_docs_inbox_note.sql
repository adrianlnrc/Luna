-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_docs_inbox_note(p_user bigint, p_req jsonb)
-- Origem da definicao atual: 015_documentos.sql (linha 189)
-- Definicoes (migracao:linha), da mais antiga a atual: 015_documentos.sql:189
CREATE OR REPLACE FUNCTION agente.f_docs_inbox_note(p_user bigint, p_req jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'agente','public' AS $f$
DECLARE v_type text := coalesce(nullif(p_req->>'tg_type', ''), 'document');
BEGIN
  IF p_user IS NULL OR p_user <= 0 OR coalesce(p_req->>'file_id', '') = '' THEN RETURN jsonb_build_object('ok', false); END IF;
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user) THEN RETURN jsonb_build_object('ok', false); END IF;
  IF v_type NOT IN ('photo','document','video') THEN v_type := 'document'; END IF;
  DELETE FROM doc_inbox WHERE received_at < now() - interval '2 days';
  INSERT INTO doc_inbox(user_id, file_id, tg_type, mime, file_name, file_size, caption)
  VALUES (p_user, p_req->>'file_id', v_type, nullif(p_req->>'mime', ''), nullif(p_req->>'file_name', ''),
          CASE WHEN coalesce(p_req->>'file_size', '') ~ '^[0-9]{1,15}$' THEN (p_req->>'file_size')::bigint END, nullif(left(p_req->>'caption', 500), ''));
  RETURN jsonb_build_object('ok', true);
EXCEPTION WHEN others THEN
  RAISE WARNING 'f_docs_inbox_note: %', SQLERRM;
  RETURN jsonb_build_object('ok', false);
END $f$;
