-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_place_cb(p_user bigint, p_data text)
-- Origem da definicao atual: 023_locais_pergunta.sql (linha 175)
-- Definicoes (migracao:linha), da mais antiga a atual: 023_locais_pergunta.sql:175
CREATE OR REPLACE FUNCTION f_place_cb(p_user bigint, p_data text) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE a text := split_part(p_data, ':', 1); v_id bigint; pp place_pending%ROWTYPE; nx jsonb; pre text := '';
BEGIN
  BEGIN v_id := NULLIF(split_part(p_data, ':', 2), '')::bigint; EXCEPTION WHEN OTHERS THEN v_id := NULL; END;
  IF a NOT IN ('plskip', 'plnever') OR v_id IS NULL THEN
    RETURN jsonb_build_object('text', 'Não entendi esse botão.', 'kb', 'none', 'rid', 0);
  END IF;
  SELECT * INTO pp FROM place_pending WHERE id = v_id AND user_id = p_user FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Não encontrei essa pergunta.', 'kb', 'none', 'rid', 0); END IF;
  IF pp.state <> 'open' THEN RETURN jsonb_build_object('text', 'Essa pergunta já foi respondida.', 'kb', 'none', 'rid', 0); END IF;
  IF pp.created_at < now() - interval '30 minutes' THEN
    UPDATE place_pending SET state = 'cancelled' WHERE id = v_id;
    RETURN jsonb_build_object('text', 'Essa pergunta expirou. Peça o compromisso de novo.', 'kb', 'none', 'rid', 0);
  END IF;
  UPDATE place_pending SET state = 'done' WHERE id = v_id;
  IF a = 'plnever' THEN
    INSERT INTO places (user_id, name, norm_name, address)
    VALUES (p_user, lower(left(pp.name, 60)), pp.norm_name, left(pp.name, 200))
    ON CONFLICT (user_id, norm_name) DO NOTHING;
    pre := 'Ok, não pergunto mais o endereço de ' || pp.name || E'.\n\n';
  END IF;
  nx := f_invite_prepare(p_user, pp.payload || jsonb_build_object('place_checked', true));
  RETURN jsonb_build_object('text', pre || (nx->>'text'), 'kb', nx->'kb', 'rid', nx->'rid');
END $$;
