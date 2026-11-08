-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_card_due_gt(p_due integer, p_d date)
-- Origem da definicao atual: 013_extras.sql (linha 66)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:66
CREATE OR REPLACE FUNCTION f_card_due_gt(p_due integer, p_d date) RETURNS date
LANGUAGE plpgsql IMMUTABLE SET search_path TO 'agente','public' AS $$
DECLARE d date; q date;
BEGIN
  d := f_card_date(extract(year FROM p_d)::int, extract(month FROM p_d)::int, p_due);
  IF d <= p_d THEN
    q := (date_trunc('month', p_d) + interval '1 month')::date;
    d := f_card_date(extract(year FROM q)::int, extract(month FROM q)::int, p_due);
  END IF;
  RETURN d;
END $$;
