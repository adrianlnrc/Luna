-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_card_close_le(p_closing integer, p_d date)
-- Origem da definicao atual: 013_extras.sql (linha 43)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:43
CREATE OR REPLACE FUNCTION f_card_close_le(p_closing integer, p_d date) RETURNS date
LANGUAGE plpgsql IMMUTABLE SET search_path TO 'agente','public' AS $$
DECLARE c date; q date;
BEGIN
  c := f_card_date(extract(year FROM p_d)::int, extract(month FROM p_d)::int, p_closing);
  IF c > p_d THEN
    q := (date_trunc('month', p_d) - interval '1 month')::date;
    c := f_card_date(extract(year FROM q)::int, extract(month FROM q)::int, p_closing);
  END IF;
  RETURN c;
END $$;
