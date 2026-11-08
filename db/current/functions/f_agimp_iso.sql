-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agimp_iso(p_day date, p_hm text, p_tz text)
-- Origem da definicao atual: 031_agenda_import.sql (linha 29)
-- Definicoes (migracao:linha), da mais antiga a atual: 031_agenda_import.sql:29
CREATE OR REPLACE FUNCTION f_agimp_iso(p_day date, p_hm text, p_tz text) RETURNS text
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE l timestamp := p_day::timestamp + p_hm::time; u timestamp; mins int;
BEGIN
  u := (l AT TIME ZONE coalesce(nullif(p_tz, ''), 'America/Sao_Paulo')) AT TIME ZONE 'UTC';
  mins := (extract(epoch FROM (l - u)) / 60)::int;
  RETURN to_char(l, 'YYYY-MM-DD"T"HH24:MI:SS') || CASE WHEN mins < 0 THEN '-' ELSE '+' END
    || lpad((abs(mins) / 60)::text, 2, '0') || ':' || lpad((abs(mins) % 60)::text, 2, '0');
END $$;
