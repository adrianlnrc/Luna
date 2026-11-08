-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ag_iso(p timestamptz)
-- Origem da definicao atual: 012_agenda.sql (linha 49)
-- Definicoes (migracao:linha), da mais antiga a atual: 012_agenda.sql:49
CREATE OR REPLACE FUNCTION f_ag_iso(p timestamptz) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente', 'public' AS $$
  SELECT to_char(p AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
$$;
