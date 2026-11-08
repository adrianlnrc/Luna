-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_contacts_list(p_user bigint)
-- Origem da definicao atual: 007_contatos.sql (linha 77)
-- Definicoes (migracao:linha), da mais antiga a atual: 007_contatos.sql:77
CREATE OR REPLACE FUNCTION f_contacts_list(p_user bigint) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    'contacts', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', name, 'email', email, 'favorite', favorite) ORDER BY favorite DESC, name)
                          FROM contacts WHERE user_id = p_user), '[]'::jsonb),
    'groups', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', g.name,
                          'members', (SELECT COALESCE(jsonb_agg(c.name ORDER BY c.name), '[]'::jsonb) FROM contact_group_members m JOIN contacts c ON c.id = m.contact_id WHERE m.group_id = g.id)) ORDER BY g.name)
                        FROM contact_groups g WHERE g.user_id = p_user), '[]'::jsonb));
$$;
