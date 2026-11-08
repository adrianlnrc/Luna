-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_period(p_user bigint, p_offset integer, OUT p_start date, OUT p_end date)
-- Origem da definicao atual: 008_financas.sql (linha 89)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:89
CREATE OR REPLACE FUNCTION f_fin_period(p_user bigint, p_offset integer DEFAULT 0, OUT p_start date, OUT p_end date)
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE d integer; today date; base date;
BEGIN
  SELECT fin_closing_day INTO d FROM users WHERE id = p_user;
  today := f_fin_today(p_user);
  IF extract(day FROM today) >= d THEN base := date_trunc('month', today)::date + (d - 1);
  ELSE base := (date_trunc('month', today) - interval '1 month')::date + (d - 1);
  END IF;
  p_start := (base + make_interval(months => p_offset))::date;
  p_end := ((p_start + interval '1 month')::date) - 1;
END $$;
