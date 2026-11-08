-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ct_disp(p text)
-- Origem da definicao atual: 014_contatos_convites.sql (linha 38)
-- Definicoes (migracao:linha), da mais antiga a atual: 014_contatos_convites.sql:38
CREATE OR REPLACE FUNCTION f_ct_disp(p text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT COALESCE((SELECT string_agg(upper(left(w, 1)) || substr(w, 2), ' ' ORDER BY o)
                   FROM unnest(string_to_array(trim(COALESCE(p, '')), ' ')) WITH ORDINALITY AS t(w, o) WHERE w <> ''), '');
$$;
