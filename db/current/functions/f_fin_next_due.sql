-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_next_due(p_day integer, p_from date)
-- Origem da definicao atual: 008_financas.sql (linha 102)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:102
CREATE OR REPLACE FUNCTION f_fin_next_due(p_day integer, p_from date) RETURNS date LANGUAGE plpgsql IMMUTABLE SET search_path = agente, public AS $$
DECLARE m date := date_trunc('month', p_from)::date; d1 date; last1 integer;
BEGIN
  last1 := extract(day FROM (m + interval '1 month' - interval '1 day'))::int;
  d1 := m + (least(p_day, last1) - 1);
  IF d1 >= p_from THEN RETURN d1; END IF;
  m := (m + interval '1 month')::date;
  last1 := extract(day FROM (m + interval '1 month' - interval '1 day'))::int;
  RETURN m + (least(p_day, last1) - 1);
END $$;
