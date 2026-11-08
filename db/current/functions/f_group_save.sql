-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_group_save(p_user bigint, p_group text, p_names text [ ])
-- Origem da definicao atual: 014_contatos_convites.sql (linha 60)
-- Definicoes (migracao:linha), da mais antiga a atual: 007_contatos.sql:41, 014_contatos_convites.sql:60
CREATE OR REPLACE FUNCTION f_group_save(p_user bigint, p_group text, p_names text[])
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE g bigint; n text; cid bigint; missing text[] := '{}'; added text[] := '{}'; cname text;
BEGIN
  g := f_ct_group_find(p_user, p_group);
  IF g IS NULL THEN
    INSERT INTO contact_groups(user_id, name) VALUES (p_user, lower(trim(p_group)))
    ON CONFLICT (user_id, name) DO UPDATE SET name = EXCLUDED.name RETURNING id INTO g;
  END IF;
  DELETE FROM contact_group_members WHERE group_id = g;
  FOREACH n IN ARRAY COALESCE(p_names, '{}') LOOP
    IF trim(COALESCE(n, '')) = '' THEN CONTINUE; END IF;
    cid := f_ct_find(p_user, n);
    IF cid IS NULL THEN
      IF NOT (lower(trim(n)) = ANY (missing)) THEN missing := missing || lower(trim(n)); END IF;
    ELSE
      INSERT INTO contact_group_members VALUES (g, cid) ON CONFLICT DO NOTHING;
      SELECT name INTO cname FROM contacts WHERE id = cid;
      IF NOT (cname = ANY (added)) THEN added := added || cname; END IF;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'group', (SELECT name FROM contact_groups WHERE id = g), 'members', to_jsonb(added), 'missing', to_jsonb(missing));
END $$;
