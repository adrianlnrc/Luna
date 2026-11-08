-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_cat_note(p_user bigint, p_cat bigint, p_added numeric, p_on date)
-- Origem da definicao atual: 008_financas.sql (linha 182)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:182
-- Renomeada de f_fin_budget_note para f_fin_cat_note em 011_planejamento.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_fin_cat_note).
CREATE OR REPLACE FUNCTION f_fin_budget_note(p_user bigint, p_cat bigint, p_added numeric, p_on date) RETURNS text
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE c fin_categories%ROWTYPE; ps date; pe date; after numeric; before numeric; pa numeric; pb numeric;
BEGIN
  SELECT * INTO c FROM fin_categories WHERE id = p_cat AND user_id = p_user;
  IF NOT FOUND OR c.budget IS NULL OR c.kind <> 'expense' THEN RETURN ''; END IF;
  SELECT p_start, p_end INTO ps, pe FROM f_fin_period(p_user, 0);
  IF p_on NOT BETWEEN ps AND pe THEN RETURN ''; END IF;
  after := f_fin_spent(p_user, p_cat, ps, pe);
  before := after - p_added;
  pa := after / c.budget * 100; pb := before / c.budget * 100;
  IF pa >= 100 AND pb < 100 THEN
    RETURN E'\nAtenção: você passou o orçamento de ' || c.name || ': ' || f_brl(after) || ' de ' || f_brl(c.budget) || ' (' || round(pa) || '%).';
  ELSIF pa >= 80 AND pb < 80 THEN
    RETURN E'\nAtenção: ' || c.name || ' já está em ' || round(pa) || '% do orçamento (' || f_brl(after) || ' de ' || f_brl(c.budget) || ').';
  END IF;
  RETURN '';
END $$;
