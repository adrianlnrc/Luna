-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_notes(p_user bigint, p jsonb)
-- Origem da definicao atual: 016_listas_notas.sql (linha 335)
-- Definicoes (migracao:linha), da mais antiga a atual: 016_listas_notas.sql:335
CREATE OR REPLACE FUNCTION f_notes(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE
  nl text := chr(10);
  act text := lower(COALESCE(NULLIF(btrim(p->>'note_action'), ''), 'list'));
  v_body text; q text; tzn text; r record; out_t text := ''; k int := 0; tot bigint := 0; pid bigint; nid bigint; nbody text;
BEGIN
  SELECT COALESCE(NULLIF(timezone, ''), 'America/Sao_Paulo') INTO tzn FROM users WHERE id = p_user;
  IF tzn IS NULL THEN RETURN f_ls_msg('Não achei seu cadastro.'); END IF;
  IF act NOT IN ('save','search','list','delete') THEN act := 'list'; END IF;
  q := btrim(COALESCE(p->>'note_query', ''));

  IF act = 'save' THEN
    v_body := btrim(COALESCE(NULLIF(btrim(p->>'note_text'), ''), p->>'text', ''));
    IF f_norm(v_body) = '' THEN RETURN f_ls_msg('O que eu anoto? Por exemplo: "anota a ideia da assinatura anual".'); END IF;
    IF length(v_body) > 4000 THEN v_body := left(v_body, 4000); END IF;
    IF EXISTS (SELECT 1 FROM notes WHERE user_id = p_user AND body_norm = f_norm(v_body) AND created_at > now() - interval '2 minutes') THEN
      RETURN f_ls_msg('Essa nota eu acabei de guardar.');
    END IF;
    INSERT INTO notes (user_id, body, body_norm) VALUES (p_user, v_body, f_norm(v_body)) RETURNING id INTO nid;
    RETURN f_ls_msg('Anotado: "' || f_nt_snip(v_body, 120) || '"');
  END IF;

  IF act = 'search' OR act = 'list' THEN
    IF act = 'list' THEN q := ''; END IF;
    FOR r IN SELECT * FROM f_nt_search(p_user, q, CASE WHEN act = 'list' THEN 8 ELSE 5 END) LOOP
      k := k + 1; tot := r.total;
      out_t := out_t || k || ') ' || to_char(r.created_at AT TIME ZONE tzn, 'DD/MM/YYYY') || ': ' || f_nt_snip(r.body, CASE WHEN act = 'list' THEN 110 ELSE 160 END) || nl;
    END LOOP;
    IF k = 0 THEN
      RETURN f_ls_msg(CASE WHEN act = 'list' OR f_norm(q) = '' THEN 'Você ainda não tem notas. Diga, por exemplo: "anota a ideia da assinatura anual".'
                           ELSE 'Não achei nenhuma nota sobre isso.' END);
    END IF;
    RETURN f_ls_msg((CASE WHEN act = 'list' THEN 'Suas últimas notas:' ELSE 'Achei ' || CASE WHEN tot = 1 THEN 'esta nota:' ELSE tot || ' notas' || CASE WHEN tot > 5 THEN ' (mostro as 5 mais recentes):' ELSE ':' END END END)
                    || nl || btrim(out_t, nl));
  END IF;

  -- apagar: acha por palavras (sem palavras = a ultima nota) e pede confirmacao
  FOR r IN SELECT * FROM f_nt_search(p_user, q, 5) LOOP
    k := k + 1; tot := r.total;
    IF k = 1 THEN nid := r.id; nbody := r.body; END IF;
    out_t := out_t || k || ') ' || to_char(r.created_at AT TIME ZONE tzn, 'DD/MM/YYYY') || ': ' || f_nt_snip(r.body, 110) || nl;
  END LOOP;
  IF k = 0 THEN RETURN f_ls_msg(CASE WHEN f_norm(q) = '' THEN 'Você não tem notas para apagar.' ELSE 'Não achei nenhuma nota sobre isso.' END); END IF;
  IF f_norm(q) <> '' AND tot > 1 THEN
    RETURN f_ls_msg('Achei ' || tot || ' notas parecidas:' || nl || btrim(out_t, nl) || nl || 'Diga mais palavras da nota que você quer apagar.');
  END IF;
  UPDATE list_pending SET state = 'cancelled' WHERE user_id = p_user AND state = 'open';
  INSERT INTO list_pending (user_id, kind, target_id, target_name) VALUES (p_user, 'delete_note', nid, f_nt_snip(nbody, 60)) RETURNING id INTO pid;
  RETURN jsonb_build_object('text', 'Apagar esta nota?' || nl || '"' || f_nt_snip(nbody, 200) || '"', 'kb', 'ls_confirm', 'rid', pid);
EXCEPTION WHEN OTHERS THEN
  RETURN f_ls_msg('Não consegui mexer nas notas agora. Tente de novo.');
END $$;
