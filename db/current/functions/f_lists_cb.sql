-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_lists_cb(p_user bigint, p_data text)
-- Origem da definicao atual: 016_listas_notas.sql (linha 390)
-- Definicoes (migracao:linha), da mais antiga a atual: 016_listas_notas.sql:390
CREATE OR REPLACE FUNCTION f_lists_cb(p_user bigint, p_data text) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE a text := split_part(p_data, ':', 1); v_id bigint; pd list_pending%ROWTYPE; n int;
BEGIN
  BEGIN v_id := NULLIF(split_part(p_data, ':', 2), '')::bigint; EXCEPTION WHEN OTHERS THEN v_id := NULL; END;
  IF a NOT IN ('lsok', 'lsno') OR v_id IS NULL THEN RETURN f_ls_msg('Não entendi esse botão.'); END IF;
  SELECT * INTO pd FROM list_pending WHERE id = v_id AND user_id = p_user FOR UPDATE;
  IF NOT FOUND THEN RETURN f_ls_msg('Não encontrei essa confirmação.'); END IF;
  IF pd.state <> 'open' THEN RETURN f_ls_msg('Essa confirmação já foi respondida.'); END IF;
  IF pd.created_at < now() - interval '1 day' THEN
    UPDATE list_pending SET state = 'cancelled' WHERE id = v_id;
    RETURN f_ls_msg('Essa confirmação expirou. Peça de novo.');
  END IF;
  IF a = 'lsno' THEN
    UPDATE list_pending SET state = 'cancelled' WHERE id = v_id;
    RETURN f_ls_msg('Ok, não apaguei nada.');
  END IF;
  IF pd.kind = 'delete_list' THEN
    DELETE FROM lists WHERE id = pd.target_id AND user_id = p_user;
    GET DIAGNOSTICS n = ROW_COUNT;
    UPDATE list_pending SET state = 'done' WHERE id = v_id;
    RETURN f_ls_msg(CASE WHEN n > 0 THEN 'Pronto, apaguei a lista ' || pd.target_name || '.' ELSE 'A lista ' || pd.target_name || ' já não existia.' END);
  ELSIF pd.kind = 'clear_list' THEN
    DELETE FROM list_items WHERE list_id = pd.target_id AND user_id = p_user;
    GET DIAGNOSTICS n = ROW_COUNT;
    UPDATE list_pending SET state = 'done' WHERE id = v_id;
    RETURN f_ls_msg('Pronto, esvaziei a lista ' || pd.target_name || ' (' || n || CASE WHEN n = 1 THEN ' item).' ELSE ' itens).' END);
  ELSE
    DELETE FROM notes WHERE id = pd.target_id AND user_id = p_user;
    GET DIAGNOSTICS n = ROW_COUNT;
    UPDATE list_pending SET state = 'done' WHERE id = v_id;
    RETURN f_ls_msg(CASE WHEN n > 0 THEN 'Pronto, apaguei a nota.' ELSE 'Essa nota já não existia.' END);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RETURN f_ls_msg('Não consegui concluir agora. Tente de novo.');
END $$;
