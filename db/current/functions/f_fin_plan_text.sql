-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_plan_text(p_user bigint)
-- Origem da definicao atual: 011_planejamento.sql (linha 123)
-- Definicoes (migracao:linha), da mais antiga a atual: 011_planejamento.sql:123
CREATE OR REPLACE FUNCTION f_fin_plan_text(p_user bigint) RETURNS text
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE u users%ROWTYPE; ps date; pe date; today date := f_fin_today(p_user); inc numeric; sp numeric; com numeric; goals numeric := 0; sobra numeric; r record; m integer; falta numeric; t text; inc_src text;
BEGIN
  SELECT * INTO u FROM users WHERE id = p_user;
  SELECT p_start, p_end INTO ps, pe FROM f_fin_period(p_user, 0);
  IF u.fin_income IS NOT NULL THEN inc := u.fin_income; inc_src := 'renda prevista';
  ELSE SELECT coalesce(sum(amount), 0) INTO inc FROM fin_entries WHERE user_id = p_user AND kind = 'income' AND status = 'paid' AND occurred_on BETWEEN ps AND pe; inc_src := 'receitas recebidas'; END IF;
  SELECT coalesce(sum(amount), 0) INTO sp FROM fin_entries WHERE user_id = p_user AND kind = 'expense' AND status = 'paid' AND occurred_on BETWEEN ps AND least(today, pe);
  SELECT coalesce(sum(amount), 0) INTO com FROM fin_entries WHERE user_id = p_user AND kind = 'expense' AND
    ((status = 'pending' AND due_on <= pe) OR (status = 'paid' AND occurred_on > today AND occurred_on <= pe));
  FOR r IN SELECT * FROM fin_goals WHERE user_id = p_user AND deadline IS NOT NULL AND deadline >= today LOOP
    falta := greatest(r.target - f_fin_goal_saved(r.id), 0);
    m := greatest(1, (extract(year FROM r.deadline)::int - extract(year FROM today)::int) * 12 + extract(month FROM r.deadline)::int - extract(month FROM today)::int);
    goals := goals + ceil(falta / m);
  END LOOP;
  sobra := inc - sp - com - goals;
  t := 'Planejamento do mês (' || to_char(ps, 'DD/MM') || ' a ' || to_char(pe, 'DD/MM') || E'):\n- Renda (' || inc_src || '): ' || f_brl(inc) ||
       E'\n- Gasto até agora: ' || f_brl(sp) || E'\n- Já comprometido (contas a pagar e parcelas): ' || f_brl(com) ||
       E'\n- Metas pedem neste mês: ' || f_brl(goals) || E'\n= Sobra para gastar: ' || f_brl(sobra);
  IF u.fin_total_limit IS NOT NULL THEN
    t := t || E'\nLimite geral: ' || f_brl(u.fin_total_limit) || CASE WHEN sobra > u.fin_total_limit - sp - com THEN '; pelo limite, o teto de gasto restante é ' || f_brl(greatest(u.fin_total_limit - sp - com, 0)) ELSE '' END || '.';
  END IF;
  IF u.fin_income IS NULL THEN t := t || E'\nDefina a renda com "minha renda é 5000" para o cálculo ficar completo.'; END IF;
  RETURN t;
END $$;
