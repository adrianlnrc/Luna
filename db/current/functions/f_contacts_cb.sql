-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_contacts_cb(p_user bigint, p_data text)
-- Origem da definicao atual: 014_contatos_convites.sql (linha 262)
-- Definicoes (migracao:linha), da mais antiga a atual: 014_contatos_convites.sql:262
CREATE OR REPLACE FUNCTION f_contacts_cb(p_user bigint, p_data text) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE a text := split_part(p_data, ':', 1); v_id bigint; pd contact_pending%ROWTYPE; n int;
BEGIN
  BEGIN v_id := NULLIF(split_part(p_data, ':', 2), '')::bigint; EXCEPTION WHEN OTHERS THEN v_id := NULL; END;
  IF a NOT IN ('ctok', 'ctno') OR v_id IS NULL THEN
    RETURN jsonb_build_object('text', 'Não entendi esse botão.', 'kb', 'none', 'rid', 0);
  END IF;
  SELECT * INTO pd FROM contact_pending WHERE id = v_id AND user_id = p_user FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Não encontrei essa confirmação.', 'kb', 'none', 'rid', 0); END IF;
  IF pd.state <> 'open' THEN RETURN jsonb_build_object('text', 'Essa confirmação já foi respondida.', 'kb', 'none', 'rid', 0); END IF;
  IF a = 'ctno' THEN
    UPDATE contact_pending SET state = 'cancelled' WHERE id = v_id;
    RETURN jsonb_build_object('text', 'Ok, mantive ' || CASE WHEN pd.kind = 'remove_group' THEN 'o grupo ' || pd.target_name ELSE f_ct_disp(pd.target_name) END || '.', 'kb', 'none', 'rid', 0);
  END IF;
  IF pd.kind = 'remove_contact' THEN
    DELETE FROM contacts WHERE id = pd.target_id AND user_id = p_user;
    GET DIAGNOSTICS n = ROW_COUNT;
    UPDATE contact_pending SET state = 'done' WHERE id = v_id;
    RETURN jsonb_build_object('text', CASE WHEN n > 0 THEN 'Pronto, tirei ' || f_ct_disp(pd.target_name) || ' dos contatos.' ELSE f_ct_disp(pd.target_name) || ' já não estava nos contatos.' END, 'kb', 'none', 'rid', 0);
  ELSE
    DELETE FROM contact_groups WHERE id = pd.target_id AND user_id = p_user;
    GET DIAGNOSTICS n = ROW_COUNT;
    UPDATE contact_pending SET state = 'done' WHERE id = v_id;
    RETURN jsonb_build_object('text', CASE WHEN n > 0 THEN 'Pronto, apaguei o grupo ' || pd.target_name || '.' ELSE 'O grupo ' || pd.target_name || ' já não existia.' END, 'kb', 'none', 'rid', 0);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('text', 'Não consegui concluir agora. Tente de novo.', 'kb', 'none', 'rid', 0);
END $$;
