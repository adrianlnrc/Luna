-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_place_find(p_user bigint, p_name text)
-- Origem da definicao atual: 021_locais_comandos.sql (linha 17)
-- Definicoes (migracao:linha), da mais antiga a atual: 021_locais_comandos.sql:17
CREATE OR REPLACE FUNCTION f_place_find(p_user bigint, p_name text) RETURNS bigint
LANGUAGE sql STABLE SET search_path TO 'agente','public' AS $$
  SELECT id FROM places
   WHERE user_id = p_user
     AND norm_name = regexp_replace(f_norm(coalesce(p_name, '')), '^(a|o|na|no|da|do|de|em) ', '')
     AND f_norm(coalesce(p_name, '')) <> ''
   ORDER BY id LIMIT 1;
$$;
