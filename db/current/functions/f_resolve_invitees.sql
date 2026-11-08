-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_resolve_invitees(p_user bigint, p_names text [ ])
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 532)
-- Definicoes (migracao:linha), da mais antiga a atual: 007_contatos.sql:57, 014_contatos_convites.sql:84, 035_memoria_unificada.sql:532
CREATE OR REPLACE FUNCTION agente.f_resolve_invitees(p_user bigint, p_names text[]) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE n text; found jsonb := '[]'; unknown text[] := '{}'; g bigint; cid bigint;
BEGIN
  FOREACH n IN ARRAY COALESCE(p_names, '{}') LOOP
    n := lower(trim(COALESCE(n, '')));
    IF n = '' THEN CONTINUE; END IF;
    g := f_ct_group_find(p_user, n);
    IF g IS NOT NULL THEN
      found := found || COALESCE((SELECT jsonb_agg(jsonb_build_object('name', c.name, 'email', c.email) ORDER BY c.name)
        FROM contact_group_members m JOIN contacts c ON c.id = m.contact_id WHERE m.group_id = g AND c.email <> ''), '[]'::jsonb);
      CONTINUE;
    END IF;
    cid := f_ct_find(p_user, n);
    IF cid IS NOT NULL AND EXISTS (SELECT 1 FROM contacts WHERE id = cid AND email <> '') THEN
      found := found || (SELECT jsonb_build_array(jsonb_build_object('name', name, 'email', email)) FROM contacts WHERE id = cid);
    ELSIF n ~ '^[^@ ]+@[^@ ]+\.[^@ ]+$' THEN
      found := found || jsonb_build_array(jsonb_build_object('name', n, 'email', n));
    ELSE unknown := unknown || n; END IF;
  END LOOP;
  RETURN jsonb_build_object('invitees', found, 'unknown', to_jsonb(unknown));
END $$;
