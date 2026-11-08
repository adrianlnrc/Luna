-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ct_group_find(p_user bigint, p_name text)
-- Origem da definicao atual: 014_contatos_convites.sql (linha 32)
-- Definicoes (migracao:linha), da mais antiga a atual: 014_contatos_convites.sql:32
CREATE OR REPLACE FUNCTION f_ct_group_find(p_user bigint, p_name text) RETURNS bigint
LANGUAGE sql STABLE SET search_path TO 'agente','public' AS $$
  SELECT id FROM contact_groups WHERE user_id = p_user AND f_norm(name) = f_norm(p_name) AND f_norm(p_name) <> '' ORDER BY id LIMIT 1;
$$;
