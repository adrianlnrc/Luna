-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_doc_expiry_apply(p_user bigint, p_doc bigint, p_exp date, p_days integer)
-- Origem da definicao atual: 015_documentos.sql (linha 155)
-- Definicoes (migracao:linha), da mais antiga a atual: 015_documentos.sql:155
CREATE OR REPLACE FUNCTION agente.f_doc_expiry_apply(p_user bigint, p_doc bigint, p_exp date, p_days integer DEFAULT 7)
RETURNS text LANGUAGE plpgsql SET search_path TO 'agente','public' AS $f$
DECLARE d documents%ROWTYPE; tz text; v_today date; v_due timestamptz; v_adj boolean := false; v_days integer := least(greatest(coalesce(p_days, 7), 0), 365); v_rid bigint; v_ttl text;
BEGIN
  SELECT * INTO d FROM documents WHERE id = p_doc AND user_id = p_user;
  IF NOT FOUND THEN RETURN 'Não achei esse documento.'; END IF;
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  v_today := (now() AT TIME ZONE tz)::date;
  PERFORM f_doc_unremind(p_doc);
  UPDATE documents SET expires_on = p_exp WHERE id = p_doc;
  IF p_exp < v_today THEN
    RETURN 'Guardei a validade de "' || d.title || '" (' || to_char(p_exp, 'DD/MM/YYYY') || '), mas essa data já passou, então não marquei aviso.';
  END IF;
  v_due := ((p_exp - v_days)::timestamp + time '09:00') AT TIME ZONE tz;
  IF v_due <= now() THEN
    v_adj := true;
    IF p_exp >= v_today + 1 THEN v_due := ((v_today + 1)::timestamp + time '09:00') AT TIME ZONE tz;
    ELSE v_due := now() + interval '2 minutes'; END IF;
  END IF;
  v_ttl := 'Vencimento: ' || d.title || ' (vence em ' || to_char(p_exp, 'DD/MM/YYYY') || ')';
  INSERT INTO reminders(user_id, kind, title, due_at, status, source) VALUES (p_user, 'reminder', v_ttl, v_due, 'pending', 'text') RETURNING id INTO v_rid;
  INSERT INTO notifications(user_id, reminder_id, type, fire_at) VALUES (p_user, v_rid, 'reminder', v_due);
  UPDATE documents SET reminder_id = v_rid WHERE id = p_doc;
  RETURN '"' || d.title || '" vence em ' || to_char(p_exp, 'DD/MM/YYYY') || '. Vou te avisar em ' || to_char(v_due AT TIME ZONE tz, 'DD/MM/YYYY "às" HH24:MI')
         || CASE WHEN NOT v_adj THEN ' (' || v_days || CASE WHEN v_days = 1 THEN ' dia' ELSE ' dias' END || ' antes).' ELSE '.' END;
END $f$;
