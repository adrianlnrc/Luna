-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_places(p_user bigint, p jsonb)
-- Origem da definicao atual: 023_locais_pergunta.sql (linha 124)
-- Definicoes (migracao:linha), da mais antiga a atual: 021_locais_comandos.sql:27, 023_locais_pergunta.sql:124
CREATE OR REPLACE FUNCTION f_places(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE
  act text := lower(coalesce(p->>'act', ''));
  nm text := btrim(regexp_replace(btrim(coalesce(p->>'name', '')), '^(a|o|na|no|da|do|de|em) ', '', 'i'));
  ad text := btrim(coalesce(p->>'address', ''));
  v_id bigint; t text; r record; n integer := 0;
  pp place_pending%ROWTYPE; nx jsonb; saved text;
BEGIN
  IF act = 'place_list' THEN
    FOR r IN SELECT name, address FROM places WHERE user_id = p_user ORDER BY name LOOP
      n := n + 1; t := coalesce(t, '') || E'\n- ' || r.name || ': ' || r.address;
    END LOOP;
    IF n = 0 THEN
      RETURN jsonb_build_object('text', 'Você ainda não salvou nenhum local. Ex.: "o local igreja é Rua das Flores, 120".', 'kb', 'none', 'rid', 0);
    END IF;
    RETURN jsonb_build_object('text', 'Seus locais:' || t, 'kb', 'none', 'rid', 0);
  END IF;
  IF nm = '' THEN
    RETURN jsonb_build_object('text', 'Qual o nome do local? Ex.: "o local igreja é Rua das Flores, 120".', 'kb', 'none', 'rid', 0);
  END IF;
  IF act = 'place_remove' THEN
    v_id := f_place_find(p_user, nm);
    IF v_id IS NULL THEN
      RETURN jsonb_build_object('text', 'Não achei o local "' || nm || '". Veja com /locais.', 'kb', 'none', 'rid', 0);
    END IF;
    DELETE FROM places WHERE id = v_id AND user_id = p_user;
    RETURN jsonb_build_object('text', 'Tirei o local ' || nm || ' da sua lista.', 'kb', 'none', 'rid', 0);
  END IF;
  -- place_save
  IF ad = '' THEN
    RETURN jsonb_build_object('text', 'Qual o endereço de "' || nm || '"? Ex.: "o local ' || nm || ' é Rua das Flores, 120".', 'kb', 'none', 'rid', 0);
  END IF;
  INSERT INTO places (user_id, name, norm_name, address)
  VALUES (p_user, lower(left(nm, 60)), f_norm(left(nm, 60)), left(ad, 200))
  ON CONFLICT (user_id, norm_name) DO UPDATE SET address = EXCLUDED.address;
  saved := 'Salvei o local ' || lower(left(nm, 60)) || ': ' || left(ad, 200) || '.';

  -- ha um compromisso esperando o endereco deste local? continua nele
  SELECT * INTO pp FROM place_pending
   WHERE user_id = p_user AND state = 'open' AND norm_name = f_norm(left(nm, 60)) AND created_at > now() - interval '30 minutes'
   ORDER BY id DESC LIMIT 1;
  IF FOUND THEN
    UPDATE place_pending SET state = 'done' WHERE id = pp.id;
    nx := f_invite_prepare(p_user, pp.payload || jsonb_build_object('place_checked', true));
    RETURN jsonb_build_object('text', saved || E'\n\n' || (nx->>'text'), 'kb', nx->'kb', 'rid', nx->'rid');
  END IF;
  RETURN jsonb_build_object('text', saved || ' Quando você marcar algo na ' || lower(left(nm, 60)) || ', eu uso esse endereço.', 'kb', 'none', 'rid', 0);
END $$;
