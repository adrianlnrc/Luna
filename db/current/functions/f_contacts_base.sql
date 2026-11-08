-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_contacts_base(p_user bigint, p jsonb)
-- Origem da definicao atual: 014_contatos_convites.sql (linha 109)
-- Definicoes (migracao:linha), da mais antiga a atual: 014_contatos_convites.sql:109
-- Renomeada de f_contacts para f_contacts_base em 021_locais_comandos.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_contacts_base).
CREATE OR REPLACE FUNCTION f_contacts(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE
  act text := lower(COALESCE(p->>'contact_action', ''));
  nm text := trim(COALESCE(p->>'contact_name', ''));
  em text := lower(trim(COALESCE(p->>'contact_email', '')));
  gn text := trim(COALESCE(p->>'group_name', ''));
  txt text := COALESCE(p->>'text', '');
  members text[] := COALESCE(ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'group_members') = 'array' THEN p->'group_members' ELSE '[]'::jsonb END)), '{}');
  fav boolean := NULL;
  cid bigint; gid bigint; c contacts%ROWTYPE; r jsonb; pid bigint; v_old text; lst text; cur text[]; miss text[]; i int; line text; cnt int;
BEGIN
  -- limpa membros vazios
  members := ARRAY(SELECT trim(x) FROM unnest(members) x WHERE trim(x) <> '');
  IF act = '' THEN
    IF gn <> '' AND array_length(members, 1) > 0 THEN act := 'group_save';
    ELSIF gn <> '' THEN act := 'group_list';
    ELSIF nm <> '' AND em <> '' THEN act := 'save';
    ELSE act := 'list'; END IF;
  END IF;
  -- favorito pela frase
  IF txt ~* 'favorit' THEN
    fav := NOT (txt ~* '(nao|não)[ ]+(e|é|eh|seja|mais)?[ ]*(mais[ ]+)?(a |o )?favorit|(tira|tirar|remove|remover|retira|retirar|desmarca|desmarcar)[^.]*favorit|desfavorit');
  END IF;
  -- "tira a Bia dos favoritos" nunca apaga o contato
  IF act = 'remove' AND fav IS NOT NULL THEN act := 'save'; END IF;

  IF act = 'save' THEN
    IF nm = '' AND em <> '' THEN
      RETURN jsonb_build_object('text', 'De quem é o e-mail ' || em || '? Diga: o e-mail da Cláudia é ' || em, 'kb', 'none', 'rid', 0);
    END IF;
    IF nm = '' THEN
      RETURN jsonb_build_object('text', 'Qual contato? Diga, por exemplo: o e-mail da Cláudia é claudia@dominio.com', 'kb', 'none', 'rid', 0);
    END IF;
    cid := f_ct_find(p_user, nm);
    IF em = '' THEN
      IF cid IS NULL THEN
        RETURN jsonb_build_object('text', 'Não tenho o e-mail de ' || f_ct_disp(nm) || '. Diga: o e-mail ' || f_ct_de(nm) || ' é fulano@dominio.com', 'kb', 'none', 'rid', 0);
      END IF;
      IF fav IS NULL THEN
        SELECT * INTO c FROM contacts WHERE id = cid;
        RETURN jsonb_build_object('text', f_ct_disp(c.name) || ' já está nos contatos (' || c.email || '). Para trocar o e-mail, diga o novo.', 'kb', 'none', 'rid', 0);
      END IF;
      UPDATE contacts SET favorite = fav WHERE id = cid RETURNING * INTO c;
      RETURN jsonb_build_object('text', CASE WHEN fav THEN f_ct_disp(c.name) || ' agora é favorito: vem primeiro na lista.' ELSE f_ct_disp(c.name) || ' saiu dos favoritos.' END, 'kb', 'none', 'rid', 0);
    END IF;
    IF em !~ '^[^@ ]+@[^@ ]+\.[^@ ]+$' THEN
      RETURN jsonb_build_object('text', 'Esse e-mail não parece válido (' || em || '). Pode conferir e mandar de novo?', 'kb', 'none', 'rid', 0);
    END IF;
    IF cid IS NOT NULL THEN
      SELECT email INTO v_old FROM contacts WHERE id = cid;
      UPDATE contacts SET email = em, favorite = COALESCE(fav, favorite) WHERE id = cid RETURNING * INTO c;
      RETURN jsonb_build_object('text', CASE WHEN v_old = em THEN 'Já estava salvo: ' ELSE 'Atualizei: ' END || f_ct_disp(c.name) || ', ' || c.email || CASE WHEN c.favorite THEN ' (favorito)' ELSE '' END || '.', 'kb', 'none', 'rid', 0);
    END IF;
    r := f_contact_save(p_user, nm, em, fav);
    IF NOT COALESCE((r->>'ok')::boolean, false) THEN
      RETURN jsonb_build_object('text', 'Não consegui salvar esse contato. Confira o e-mail e tente de novo.', 'kb', 'none', 'rid', 0);
    END IF;
    RETURN jsonb_build_object('text', 'Contato salvo: ' || f_ct_disp(r->>'name') || ', ' || (r->>'email') || CASE WHEN (r->>'favorite')::boolean THEN ' (favorito)' ELSE '' END || '.', 'kb', 'none', 'rid', 0);

  ELSIF act = 'list' THEN
    SELECT count(*) INTO cnt FROM contacts WHERE user_id = p_user;
    IF cnt = 0 THEN
      RETURN jsonb_build_object('text', 'Você ainda não salvou contatos. Diga, por exemplo: o e-mail da Cláudia é claudia@dominio.com', 'kb', 'none', 'rid', 0);
    END IF;
    lst := '';
    FOR c IN SELECT * FROM contacts WHERE user_id = p_user AND (NOT (txt ~* 'favorit') OR favorite OR NOT EXISTS (SELECT 1 FROM contacts x WHERE x.user_id = p_user AND x.favorite))
             ORDER BY favorite DESC, name LOOP
      lst := lst || E'\n- ' || f_ct_disp(c.name) || ': ' || c.email || CASE WHEN c.favorite THEN ' (favorito)' ELSE '' END
        || COALESCE((SELECT ' [grupos: ' || string_agg(g.name, ', ' ORDER BY g.name) || ']'
                     FROM contact_group_members m JOIN contact_groups g ON g.id = m.group_id WHERE m.contact_id = c.id), '');
    END LOOP;
    RETURN jsonb_build_object('text', 'Seus contatos:' || lst, 'kb', 'none', 'rid', 0);

  ELSIF act = 'remove' THEN
    cid := f_ct_find(p_user, nm);
    IF cid IS NULL THEN
      RETURN jsonb_build_object('text', CASE WHEN nm = '' THEN 'Qual contato você quer tirar?' ELSE 'Não encontrei ' || f_ct_disp(nm) || ' nos contatos.' END, 'kb', 'none', 'rid', 0);
    END IF;
    SELECT * INTO c FROM contacts WHERE id = cid;
    SELECT id INTO pid FROM contact_pending WHERE user_id = p_user AND kind = 'remove_contact' AND target_id = cid AND state = 'open' AND created_at > now() - interval '1 hour' ORDER BY id DESC LIMIT 1;
    IF pid IS NULL THEN
      INSERT INTO contact_pending(user_id, kind, target_id, target_name) VALUES (p_user, 'remove_contact', cid, c.name) RETURNING id INTO pid;
    END IF;
    RETURN jsonb_build_object('text', 'Tirar ' || f_ct_disp(c.name) || ' (' || c.email || ') dos contatos? Ele também sai dos grupos.', 'kb', 'ct_confirm', 'rid', pid);

  ELSIF act = 'group_save' THEN
    IF gn = '' THEN
      RETURN jsonb_build_object('text', 'Qual o nome do grupo? Diga, por exemplo: cria o grupo time com Douglas, Bia e Cláudia', 'kb', 'none', 'rid', 0);
    END IF;
    IF array_length(members, 1) IS NULL THEN
      RETURN jsonb_build_object('text', 'Quem entra no grupo ' || lower(gn) || '? Diga os nomes, por exemplo: cria o grupo ' || lower(gn) || ' com Douglas e Bia', 'kb', 'none', 'rid', 0);
    END IF;
    gid := f_ct_group_find(p_user, gn);
    IF gid IS NOT NULL AND txt ~* '(adiciona|adicionar|coloca|colocar|inclui|incluir|poe|põe|por )' AND txt !~* '(tira|tirar|remove|remover|retira|retirar)' THEN
      cur := ARRAY(SELECT c2.name FROM contact_group_members m JOIN contacts c2 ON c2.id = m.contact_id WHERE m.group_id = gid);
      members := cur || members;
    ELSIF gid IS NOT NULL AND txt ~* '(tira|tirar|remove|remover|retira|retirar)' THEN
      cur := ARRAY(SELECT c2.name FROM contact_group_members m JOIN contacts c2 ON c2.id = m.contact_id WHERE m.group_id = gid
                   AND NOT EXISTS (SELECT 1 FROM unnest(members) x WHERE f_ct_find(p_user, x) = c2.id));
      members := cur;
    END IF;
    r := f_group_save(p_user, gn, members);
    miss := COALESCE(ARRAY(SELECT jsonb_array_elements_text(r->'missing')), '{}');
    cur := COALESCE(ARRAY(SELECT jsonb_array_elements_text(r->'members')), '{}');
    line := 'Grupo ' || (r->>'group') || ': ' || CASE WHEN array_length(cur, 1) IS NULL THEN 'sem ninguém por enquanto' ELSE (SELECT string_agg(f_ct_disp(x), ', ') FROM unnest(cur) x) END || '.';
    IF array_length(miss, 1) > 0 THEN
      line := line || E'\nNão tenho cadastro de ' || (SELECT string_agg(f_ct_disp(x), ', ') FROM unnest(miss) x)
        || '. Diga: o e-mail ' || f_ct_de(miss[1]) || ' é fulano@dominio.com, e depois peça o grupo de novo.';
    END IF;
    RETURN jsonb_build_object('text', line, 'kb', 'none', 'rid', 0);

  ELSIF act = 'group_list' THEN
    IF gn <> '' THEN
      gid := f_ct_group_find(p_user, gn);
      IF gid IS NULL THEN
        RETURN jsonb_build_object('text', 'Não encontrei o grupo ' || lower(gn) || '.', 'kb', 'none', 'rid', 0);
      END IF;
      SELECT 'Grupo ' || g.name || ': ' || COALESCE((SELECT string_agg(f_ct_disp(c2.name) || ' (' || c2.email || ')', ', ' ORDER BY c2.name)
              FROM contact_group_members m JOIN contacts c2 ON c2.id = m.contact_id WHERE m.group_id = g.id), 'ninguém ainda') || '.'
        INTO line FROM contact_groups g WHERE g.id = gid;
      RETURN jsonb_build_object('text', line, 'kb', 'none', 'rid', 0);
    END IF;
    SELECT count(*) INTO cnt FROM contact_groups WHERE user_id = p_user;
    IF cnt = 0 THEN
      RETURN jsonb_build_object('text', 'Você ainda não tem grupos. Diga, por exemplo: cria o grupo time com Douglas, Bia e Cláudia', 'kb', 'none', 'rid', 0);
    END IF;
    lst := '';
    FOR gid, v_old IN SELECT g.id, g.name FROM contact_groups g WHERE g.user_id = p_user ORDER BY g.name LOOP
      lst := lst || E'\n- ' || v_old || ': ' || COALESCE((SELECT string_agg(f_ct_disp(c2.name), ', ' ORDER BY c2.name)
              FROM contact_group_members m JOIN contacts c2 ON c2.id = m.contact_id WHERE m.group_id = gid), 'ninguém ainda');
    END LOOP;
    RETURN jsonb_build_object('text', 'Seus grupos:' || lst, 'kb', 'none', 'rid', 0);

  ELSIF act = 'group_remove' THEN
    gid := f_ct_group_find(p_user, gn);
    IF gid IS NULL THEN
      RETURN jsonb_build_object('text', CASE WHEN gn = '' THEN 'Qual grupo você quer apagar?' ELSE 'Não encontrei o grupo ' || lower(gn) || '.' END, 'kb', 'none', 'rid', 0);
    END IF;
    SELECT name INTO v_old FROM contact_groups WHERE id = gid;
    SELECT id INTO pid FROM contact_pending WHERE user_id = p_user AND kind = 'remove_group' AND target_id = gid AND state = 'open' AND created_at > now() - interval '1 hour' ORDER BY id DESC LIMIT 1;
    IF pid IS NULL THEN
      INSERT INTO contact_pending(user_id, kind, target_id, target_name) VALUES (p_user, 'remove_group', gid, v_old) RETURNING id INTO pid;
    END IF;
    RETURN jsonb_build_object('text', 'Apagar o grupo ' || v_old || '? Os contatos continuam salvos.', 'kb', 'ct_confirm', 'rid', pid);
  END IF;

  RETURN jsonb_build_object('text', 'Não entendi o que fazer com os contatos. Exemplos: "meus contatos", "salva o e-mail da Cláudia: claudia@dominio.com", "cria o grupo time com Douglas e Bia".', 'kb', 'none', 'rid', 0);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('text', 'Não consegui mexer nos contatos agora. Tente de novo em instantes.', 'kb', 'none', 'rid', 0);
END $$;
