-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_doc_unremind(p_doc bigint)
-- Origem da definicao atual: 015_documentos.sql (linha 142)
-- Definicoes (migracao:linha), da mais antiga a atual: 015_documentos.sql:142
CREATE OR REPLACE FUNCTION agente.f_doc_unremind(p_doc bigint) RETURNS void
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $f$
DECLARE v_rid bigint;
BEGIN
  SELECT reminder_id INTO v_rid FROM documents WHERE id = p_doc;
  IF v_rid IS NOT NULL THEN
    UPDATE notifications SET state = 'cancelled' WHERE reminder_id = v_rid AND state = 'pending';
    UPDATE reminders SET status = 'cancelled' WHERE id = v_rid AND status IN ('pending','awaiting_time');
  END IF;
  UPDATE documents SET reminder_id = NULL WHERE id = p_doc;
END $f$;
