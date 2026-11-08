-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ct_iso(p timestamptz, p_tz text)
-- Origem da definicao atual: 014_contatos_convites.sql (linha 51)
-- Definicoes (migracao:linha), da mais antiga a atual: 014_contatos_convites.sql:51
CREATE OR REPLACE FUNCTION f_ct_iso(p timestamptz, p_tz text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT to_char(p AT TIME ZONE p_tz, 'YYYY-MM-DD"T"HH24:MI:SS')
    || CASE WHEN o < interval '0' THEN '-' ELSE '+' END
    || lpad((abs(extract(epoch FROM o))::int / 3600)::text, 2, '0') || ':' || lpad(((abs(extract(epoch FROM o))::int % 3600) / 60)::text, 2, '0')
  FROM (SELECT (p AT TIME ZONE p_tz) - (p AT TIME ZONE 'UTC') AS o) x;
$$;
