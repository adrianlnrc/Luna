-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_lists_base(p_user bigint, p jsonb)
-- Origem da definicao atual: 016_listas_notas.sql (linha 124)
-- Definicoes (migracao:linha), da mais antiga a atual: 016_listas_notas.sql:124
-- Renomeada de f_lists para f_lists_base em 025_listas_compras.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_lists_base).
CREATE OR REPLACE FUNCTION f_lists(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE
  nl text := chr(10);
  act text := lower(COALESCE(NULLIF(btrim(p->>'list_action'), ''), 'show'));
  lname text := f_ls_clean(p->>'list_name');
  items text[];
  v_list bigint; v_disp text; n_lists int; names text; it text; iid bigint; k int;
  added text[] := '{}'; dups text[] := '{}'; reop text[] := '{}'; changed text[] := '{}'; same text[] := '{}';
  nf text[] := '{}'; amb text[] := '{}'; parts text[] := '{}';
  pend int; tot int; pid bigint; created boolean := false;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user) THEN RETURN f_ls_msg('Não achei seu cadastro.'); END IF;
  IF act NOT IN ('create','show','add','remove','check','uncheck','clear','delete','lists') THEN act := 'show'; END IF;
  items := COALESCE(ARRAY(
    SELECT x FROM (
      SELECT (array_agg(btrim(left(e, 80)) ORDER BY o))[1] AS x, min(o) AS o
        FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'list_items') = 'array' THEN p->'list_items' ELSE '[]'::jsonb END) WITH ORDINALITY AS t(e, o)
       WHERE btrim(e) <> '' AND f_norm(e) <> '' GROUP BY f_norm(e)) s ORDER BY o LIMIT 30), '{}');

  SELECT count(*) INTO n_lists FROM lists WHERE user_id = p_user;
  SELECT string_agg(name, ', ' ORDER BY name) INTO names FROM lists WHERE user_id = p_user;

  -- minhas listas
  IF act = 'lists' THEN
    IF n_lists = 0 THEN
      RETURN f_ls_msg('Você ainda não tem listas. Diga, por exemplo: "lista de mercado: arroz, café e detergente".');
    END IF;
    SELECT string_agg('- ' || l.name || ': ' || COALESCE(c.pend, 0) || CASE WHEN COALESCE(c.pend, 0) = 1 THEN ' pendente' ELSE ' pendentes' END
                      || ' de ' || COALESCE(c.tot, 0), nl ORDER BY l.name)
      INTO names
      FROM lists l LEFT JOIN (SELECT list_id, count(*) AS tot, count(*) FILTER (WHERE NOT done) AS pend FROM list_items WHERE user_id = p_user GROUP BY list_id) c ON c.list_id = l.id
     WHERE l.user_id = p_user;
    RETURN f_ls_msg('Suas listas:' || nl || names);
  END IF;

  -- resolver a lista
  IF act = 'create' THEN
    IF lname = '' THEN
      IF cardinality(items) = 0 THEN RETURN f_ls_msg('Qual o nome da lista? Por exemplo: "lista de mercado: arroz, café".'); END IF;
      lname := 'mercado';
    END IF;
    v_list := f_ls_find(p_user, lname);
  ELSE
    IF act = 'add' AND cardinality(items) = 0 THEN RETURN f_ls_msg('Quais itens eu adiciono? Por exemplo: "adiciona sabão em pó na lista".'); END IF;
    IF act IN ('remove','check','uncheck') AND cardinality(items) = 0 THEN
      RETURN f_ls_msg('Qual item? Por exemplo: "marca o arroz" ou "tira o café da lista".');
    END IF;
    IF lname <> '' THEN
      v_list := f_ls_find(p_user, lname);
    ELSIF n_lists = 1 THEN
      SELECT id INTO v_list FROM lists WHERE user_id = p_user;
    ELSIF n_lists > 1 THEN
      RETURN f_ls_msg('De qual lista? Você tem: ' || names || '.');
    ELSIF act = 'add' THEN
      lname := 'mercado';
    ELSE
      RETURN f_ls_msg('Você ainda não tem listas. Diga, por exemplo: "lista de mercado: arroz, café e detergente".');
    END IF;
    IF v_list IS NULL AND act <> 'add' THEN
      RETURN f_ls_msg('Não achei essa lista.' || CASE WHEN n_lists > 0 THEN ' Suas listas: ' || names || '.' ELSE '' END);
    END IF;
  END IF;

  IF v_list IS NULL THEN
    IF f_norm(lname) = '' THEN RETURN f_ls_msg('Não entendi o nome da lista. Pode repetir?'); END IF;
    INSERT INTO lists (user_id, name, name_norm) VALUES (p_user, f_ls_disp(left(lname, 60)), f_norm(lname))
      ON CONFLICT (user_id, name_norm) DO NOTHING;
    SELECT id INTO v_list FROM lists WHERE user_id = p_user AND name_norm = f_norm(lname);
    created := true;
  END IF;
  SELECT name INTO v_disp FROM lists WHERE id = v_list AND user_id = p_user;
  IF v_disp IS NULL THEN RETURN f_ls_msg('Não achei essa lista.'); END IF;

  IF act IN ('create', 'add') THEN
    SELECT count(*) INTO tot FROM list_items WHERE list_id = v_list;
    IF tot + cardinality(items) > 300 THEN RETURN f_ls_msg('Essa lista já está muito grande (limite de 300 itens).'); END IF;
    FOREACH it IN ARRAY items LOOP
      iid := f_ls_item_find(v_list, it, true);
      IF iid IS NOT NULL AND iid > 0 THEN
        IF (SELECT done FROM list_items WHERE id = iid) THEN
          UPDATE list_items SET done = false, done_at = NULL WHERE id = iid;
          reop := reop || it;
        ELSE
          dups := dups || it;
        END IF;
      ELSE
        INSERT INTO list_items (list_id, user_id, name, name_norm) VALUES (v_list, p_user, it, f_norm(it));
        added := added || it;
      END IF;
    END LOOP;
    SELECT count(*) FILTER (WHERE NOT done), count(*) INTO pend, tot FROM list_items WHERE list_id = v_list;
    IF cardinality(added) > 0 THEN parts := parts || ('Adicionei na lista ' || v_disp || ': ' || array_to_string(added, ', ') || '.'); END IF;
    IF cardinality(reop) > 0 THEN parts := parts || ('Voltou para pendente: ' || array_to_string(reop, ', ') || '.'); END IF;
    IF cardinality(dups) > 0 THEN parts := parts || ('Já estava na lista: ' || array_to_string(dups, ', ') || '.'); END IF;
    IF cardinality(added) = 0 AND cardinality(reop) = 0 AND cardinality(dups) = 0 THEN
      parts := parts || ('Criei a lista ' || v_disp || ' (vazia). Diga "adiciona ... na lista ' || lower(v_disp) || '".');
    ELSIF created AND act = 'add' THEN
      parts := parts || ('(Criei a lista ' || v_disp || '.)');
    END IF;
    IF tot > 0 THEN parts := parts || ('Pendentes: ' || pend || ' de ' || tot || '.'); END IF;
    RETURN f_ls_msg(array_to_string(parts, ' '));
  END IF;

  IF act = 'remove' THEN
    FOREACH it IN ARRAY items LOOP
      iid := f_ls_item_find(v_list, it, false);
      IF iid IS NULL THEN nf := nf || it;
      ELSIF iid = 0 THEN amb := amb || it;
      ELSE
        changed := changed || (SELECT name FROM list_items WHERE id = iid);
        DELETE FROM list_items WHERE id = iid AND user_id = p_user AND list_id = v_list;
      END IF;
    END LOOP;
    SELECT count(*) FILTER (WHERE NOT done), count(*) INTO pend, tot FROM list_items WHERE list_id = v_list;
    IF cardinality(changed) > 0 THEN parts := parts || ('Tirei da lista ' || v_disp || ': ' || array_to_string(changed, ', ') || '.'); END IF;
    IF cardinality(nf) > 0 THEN parts := parts || ('Não achei na lista: ' || array_to_string(nf, ', ') || '.'); END IF;
    IF cardinality(amb) > 0 THEN parts := parts || ('Tem mais de um item parecido com: ' || array_to_string(amb, ', ') || '. Diga o nome completo.'); END IF;
    parts := parts || ('Restam ' || tot || CASE WHEN tot = 1 THEN ' item.' ELSE ' itens.' END);
    RETURN f_ls_msg(array_to_string(parts, ' '));
  END IF;

  IF act IN ('check', 'uncheck') THEN
    FOREACH it IN ARRAY items LOOP
      iid := f_ls_item_find(v_list, it, false);
      IF iid IS NULL THEN nf := nf || it;
      ELSIF iid = 0 THEN amb := amb || it;
      ELSE
        IF (SELECT done FROM list_items WHERE id = iid) = (act = 'check') THEN
          same := same || (SELECT name FROM list_items WHERE id = iid);
        ELSE
          UPDATE list_items SET done = (act = 'check'), done_at = CASE WHEN act = 'check' THEN now() ELSE NULL END
           WHERE id = iid AND user_id = p_user AND list_id = v_list;
          changed := changed || (SELECT name FROM list_items WHERE id = iid);
        END IF;
      END IF;
    END LOOP;
    SELECT count(*) FILTER (WHERE NOT done), count(*) INTO pend, tot FROM list_items WHERE list_id = v_list;
    IF cardinality(changed) > 0 THEN
      parts := parts || ((CASE WHEN act = 'check' THEN 'Marquei como comprado: ' ELSE 'Voltou para pendente: ' END) || array_to_string(changed, ', ') || '.');
    END IF;
    IF cardinality(same) > 0 THEN
      parts := parts || ('Já estava ' || CASE WHEN act = 'check' THEN 'marcado: ' ELSE 'pendente: ' END || array_to_string(same, ', ') || '.');
    END IF;
    IF cardinality(nf) > 0 THEN parts := parts || ('Não achei na lista ' || v_disp || ': ' || array_to_string(nf, ', ') || '.'); END IF;
    IF cardinality(amb) > 0 THEN parts := parts || ('Tem mais de um item parecido com: ' || array_to_string(amb, ', ') || '. Diga o nome completo.'); END IF;
    IF tot > 0 AND pend = 0 THEN parts := parts || 'Tudo comprado! Diga "limpa a lista" se quiser esvaziá-la.'::text;
    ELSE parts := parts || ('Pendentes: ' || pend || ' de ' || tot || '.'); END IF;
    RETURN f_ls_msg(array_to_string(parts, ' '));
  END IF;

  IF act = 'show' THEN
    RETURN f_ls_msg(f_ls_render(v_list));
  END IF;

  -- destrutivas: pedem confirmacao por botao
  SELECT count(*) INTO tot FROM list_items WHERE list_id = v_list;
  IF act = 'clear' AND tot = 0 THEN RETURN f_ls_msg('A lista ' || v_disp || ' já está vazia.'); END IF;
  UPDATE list_pending SET state = 'cancelled' WHERE user_id = p_user AND state = 'open';
  INSERT INTO list_pending (user_id, kind, target_id, target_name)
    VALUES (p_user, CASE WHEN act = 'clear' THEN 'clear_list' ELSE 'delete_list' END, v_list, v_disp)
    RETURNING id INTO pid;
  IF act = 'clear' THEN
    RETURN jsonb_build_object('text', 'Esvaziar a lista ' || v_disp || '? Os ' || tot || ' itens serão apagados (a lista continua existindo).', 'kb', 'ls_confirm', 'rid', pid);
  END IF;
  RETURN jsonb_build_object('text', 'Apagar a lista ' || v_disp || ' com ' || tot || CASE WHEN tot = 1 THEN ' item?' ELSE ' itens?' END, 'kb', 'ls_confirm', 'rid', pid);
EXCEPTION WHEN OTHERS THEN
  RETURN f_ls_msg('Não consegui mexer na lista agora. Tente de novo.');
END $$;
