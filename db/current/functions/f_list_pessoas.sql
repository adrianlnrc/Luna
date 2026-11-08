-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_list_pessoas(p_user bigint)
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 233)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:233
CREATE OR REPLACE FUNCTION agente.f_list_pessoas(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE r record; t text; g text; nc int; ng int;
BEGIN
  SELECT count(*) INTO nc FROM contacts WHERE user_id = p_user;
  SELECT count(*) INTO ng FROM contact_groups WHERE user_id = p_user;
  t := 'Pessoas (' || nc || '):';
  IF nc = 0 THEN t := t || E'\n- nenhuma ainda. Ex.: "salva o e-mail da Claudia: claudia@x.com"'; END IF;
  FOR r IN SELECT c.name, c.email, c.favorite, c.relation,
                  (SELECT string_agg(f_ct_disp(a), ', ') FROM unnest(c.aliases) a) AS apelidos
             FROM contacts c WHERE c.user_id = p_user ORDER BY c.favorite DESC, c.name LOOP
    t := t || E'\n- ' || f_ct_disp(r.name)
         || CASE WHEN r.relation <> '' THEN ' (' || r.relation || ')' ELSE '' END
         || CASE WHEN r.favorite THEN ' (favorito)' ELSE '' END
         || CASE WHEN r.email <> '' THEN ' - ' || r.email ELSE ' - sem e-mail' END
         || CASE WHEN r.apelidos IS NOT NULL THEN ' [apelidos: ' || r.apelidos || ']' ELSE '' END;
  END LOOP;
  g := 'Grupos (' || ng || '):';
  IF ng = 0 THEN g := g || E'\n- nenhum ainda. Ex.: "cria o grupo família com Ana e Bia"'; END IF;
  FOR r IN SELECT cg.name, (SELECT string_agg(f_ct_disp(ct.name), ', ' ORDER BY ct.name)
                              FROM contact_group_members m JOIN contacts ct ON ct.id = m.contact_id WHERE m.group_id = cg.id) AS membros
             FROM contact_groups cg WHERE cg.user_id = p_user ORDER BY cg.name LOOP
    g := g || E'\n- ' || f_ct_disp(r.name) || ': ' || coalesce(r.membros, 'sem ninguém');
  END LOOP;
  RETURN jsonb_build_object('text', t || E'\n\n' || g, 'pessoas', nc, 'grupos', ng);
END $$;
