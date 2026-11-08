-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_range(p_user bigint, p_period text, OUT r_start date, OUT r_end date, OUT r_label text)
-- Origem da definicao atual: 008_financas.sql (linha 432)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:432
CREATE OR REPLACE FUNCTION f_fin_range(p_user bigint, p_period text, OUT r_start date, OUT r_end date, OUT r_label text)
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE today date := f_fin_today(p_user);
BEGIN
  IF p_period = 'today' THEN r_start := today; r_end := today; r_label := 'hoje';
  ELSIF p_period = 'yesterday' THEN r_start := today - 1; r_end := today - 1; r_label := 'ontem';
  ELSIF p_period = 'week' THEN r_start := today - 6; r_end := today; r_label := 'últimos 7 dias';
  ELSIF p_period = 'previous' THEN SELECT p_start, p_end INTO r_start, r_end FROM f_fin_period(p_user, -1); r_label := 'mês anterior';
  ELSE SELECT p_start, p_end INTO r_start, r_end FROM f_fin_period(p_user, 0); r_label := 'mês atual';
  END IF;
END $$;
