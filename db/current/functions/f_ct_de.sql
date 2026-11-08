-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ct_de(p text)
-- Origem da definicao atual: 014_contatos_convites.sql (linha 45)
-- Definicoes (migracao:linha), da mais antiga a atual: 014_contatos_convites.sql:45
CREATE OR REPLACE FUNCTION f_ct_de(p text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT CASE WHEN right(f_norm(split_part(trim(COALESCE(p, '')), ' ', 1)), 1) = 'a' THEN 'da ' ELSE 'do ' END || f_ct_disp(p);
$$;
