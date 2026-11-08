-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_series_next(p_series bigint)
-- Origem da definicao atual: 012_agenda.sql (linha 99)
-- Definicoes (migracao:linha), da mais antiga a atual: 012_agenda.sql:99
CREATE OR REPLACE FUNCTION f_series_next(p_series bigint) RETURNS timestamptz
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE s agenda_series%ROWTYPE; tz text; v_today date; d date; ts timestamptz; i int; last_dom int;
BEGIN
  SELECT * INTO s FROM agenda_series WHERE id = p_series AND active;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT timezone INTO tz FROM users WHERE id = s.user_id;
  v_today := (now() AT TIME ZONE tz)::date;
  d := greatest(v_today, s.first_date);
  IF s.freq = 'daily' THEN
    ts := (d + s.start_time) AT TIME ZONE tz;
    IF ts <= now() THEN d := d + 1; END IF;
  ELSIF s.freq = 'weekly' THEN
    d := d + ((s.weekday - extract(isodow FROM d)::int + 7) % 7);
    ts := (d + s.start_time) AT TIME ZONE tz;
    IF ts <= now() THEN d := d + 7; END IF;
  ELSE
    d := NULL;
    FOR i IN 0..24 LOOP
      last_dom := extract(day FROM (date_trunc('month', greatest(v_today, s.first_date)) + make_interval(months => i + 1) - interval '1 day'))::int;
      d := (date_trunc('month', greatest(v_today, s.first_date)) + make_interval(months => i))::date + (least(s.dom, last_dom) - 1);
      IF d >= greatest(v_today, s.first_date) AND (d + s.start_time) AT TIME ZONE tz > now() THEN EXIT; END IF;
      d := NULL;
    END LOOP;
    IF d IS NULL THEN RETURN NULL; END IF;
  END IF;
  IF s.until IS NOT NULL AND d > s.until THEN RETURN NULL; END IF;
  RETURN (d + s.start_time) AT TIME ZONE tz;
END $$;
