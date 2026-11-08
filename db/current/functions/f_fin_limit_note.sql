-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_limit_note(p_user bigint, p_added numeric, p_on date)
-- Origem da definicao atual: 011_planejamento.sql (linha 84)
-- Definicoes (migracao:linha), da mais antiga a atual: 011_planejamento.sql:84
CREATE OR REPLACE FUNCTION f_fin_limit_note(p_user bigint, p_added numeric, p_on date) RETURNS text
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE lim numeric; ps date; pe date; after numeric; pa numeric; pb numeric;
BEGIN
  SELECT fin_total_limit INTO lim FROM users WHERE id = p_user;
  IF lim IS NULL THEN RETURN ''; END IF;
  SELECT p_start, p_end INTO ps, pe FROM f_fin_period(p_user, 0);
  IF p_on NOT BETWEEN ps AND pe THEN RETURN ''; END IF;
  after := f_fin_total_spent(p_user, ps, pe);
  pa := after / lim * 100; pb := (after - p_added) / lim * 100;
  IF pa >= 100 AND pb < 100 THEN
    RETURN E'\nAtenção: você passou o limite geral do mês: ' || f_brl(after) || ' de ' || f_brl(lim) || ' (' || round(pa) || '%).';
  ELSIF pa >= 80 AND pb < 80 THEN
    RETURN E'\nAtenção: você já usou ' || round(pa) || '% do limite geral do mês (' || f_brl(after) || ' de ' || f_brl(lim) || ').';
  END IF;
  RETURN '';
END $$;
