-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ag_fmt(p timestamptz, p_tz text)
-- Origem da definicao atual: 012_agenda.sql (linha 60)
-- Definicoes (migracao:linha), da mais antiga a atual: 012_agenda.sql:60
CREATE OR REPLACE FUNCTION f_ag_fmt(p timestamptz, p_tz text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente', 'public' AS $$
  SELECT f_ag_dayname((p AT TIME ZONE p_tz)::date) || ' ' || to_char(p AT TIME ZONE p_tz, 'DD/MM') || ' às ' || to_char(p AT TIME ZONE p_tz, 'HH24:MI')
$$;
