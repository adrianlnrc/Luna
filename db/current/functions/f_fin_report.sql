-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_report(p_user bigint, p jsonb)
-- Origem da definicao atual: 008_financas.sql (linha 456)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:456
CREATE OR REPLACE FUNCTION f_fin_report(p_user bigint, p jsonb) RETURNS jsonb LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE
  act text := coalesce(p->>'action', 'summary'); today date := f_fin_today(p_user);
  rs date; re date; lbl text; v_exp numeric; v_inc numeric; t text; r record; ps date; pe date; cs date;
  cur_total numeric; prev_same numeric; prev_full numeric; days_elapsed integer; k integer;
BEGIN
  PERFORM f_fin_seed(p_user);
  SELECT r_start, r_end, r_label INTO rs, re, lbl FROM f_fin_range(p_user, coalesce(nullif(p->>'period', ''), 'current'));

  IF act = 'compare' THEN
    SELECT p_start INTO cs FROM f_fin_period(p_user, 0);
    SELECT p_start, p_end INTO ps, pe FROM f_fin_period(p_user, -1);
    days_elapsed := today - cs;
    SELECT coalesce(sum(amount), 0) INTO cur_total FROM fin_entries WHERE user_id = p_user AND kind = 'expense' AND status = 'paid' AND occurred_on BETWEEN cs AND today;
    SELECT coalesce(sum(amount), 0) INTO prev_same FROM fin_entries WHERE user_id = p_user AND kind = 'expense' AND status = 'paid' AND occurred_on BETWEEN ps AND ps + days_elapsed;
    SELECT coalesce(sum(amount), 0) INTO prev_full FROM fin_entries WHERE user_id = p_user AND kind = 'expense' AND status = 'paid' AND occurred_on BETWEEN ps AND pe;
    IF cur_total = 0 AND prev_full = 0 THEN RETURN jsonb_build_object('text', 'Ainda não tenho gastos registrados nesses dois períodos para comparar.', 'kb', 'none'); END IF;
    t := 'Mês atual (' || to_char(cs, 'DD/MM') || ' a hoje): ' || f_brl(cur_total) || E'\nMês anterior, mesmo trecho (' || to_char(ps, 'DD/MM') || ' a ' || to_char(ps + days_elapsed, 'DD/MM') || '): ' || f_brl(prev_same) ||
      CASE WHEN prev_same > 0 THEN E'\nVariação: ' || CASE WHEN cur_total >= prev_same THEN '+' ELSE '' END || round((cur_total - prev_same) / prev_same * 100) || '%' ELSE '' END ||
      E'\nMês anterior fechado (' || to_char(ps, 'DD/MM') || ' a ' || to_char(pe, 'DD/MM') || '): ' || f_brl(prev_full);
    k := 0;
    FOR r IN
      SELECT c.name, coalesce(a.s, 0) AS cur, coalesce(b.s, 0) AS prev
      FROM fin_categories c
      LEFT JOIN (SELECT category_id, sum(amount) s FROM fin_entries WHERE user_id = p_user AND kind = 'expense' AND status = 'paid' AND occurred_on BETWEEN cs AND today GROUP BY 1) a ON a.category_id = c.id
      LEFT JOIN (SELECT category_id, sum(amount) s FROM fin_entries WHERE user_id = p_user AND kind = 'expense' AND status = 'paid' AND occurred_on BETWEEN ps AND ps + days_elapsed GROUP BY 1) b ON b.category_id = c.id
      WHERE c.user_id = p_user AND c.kind = 'expense' AND (coalesce(a.s, 0) > 0 OR coalesce(b.s, 0) > 0)
      ORDER BY abs(coalesce(a.s, 0) - coalesce(b.s, 0)) DESC LIMIT 5
    LOOP
      IF k = 0 THEN t := t || E'\n\nO que mais mudou:'; END IF;
      k := k + 1;
      t := t || E'\n- ' || r.name || ': ' || f_brl(r.cur) || ' (antes ' || f_brl(r.prev) || ')';
    END LOOP;
    RETURN jsonb_build_object('text', t, 'kb', 'none');
  END IF;

  IF act = 'top' THEN
    t := 'Maiores despesas (' || lbl || ', ' || to_char(rs, 'DD/MM') || ' a ' || to_char(re, 'DD/MM') || '):';
    k := 0;
    FOR r IN SELECT e.description, e.amount, e.occurred_on, c.name AS cat FROM fin_entries e LEFT JOIN fin_categories c ON c.id = e.category_id
             WHERE e.user_id = p_user AND e.kind = 'expense' AND e.status = 'paid' AND e.occurred_on BETWEEN rs AND re ORDER BY e.amount DESC LIMIT 5 LOOP
      k := k + 1; t := t || E'\n' || k || ') ' || r.description || ' ' || f_brl(r.amount) || ' (' || coalesce(r.cat, 'Outros') || ', ' || to_char(r.occurred_on, 'DD/MM') || ')';
    END LOOP;
    IF k = 0 THEN RETURN jsonb_build_object('text', 'Nenhum gasto registrado em ' || lbl || '.', 'kb', 'none'); END IF;
    RETURN jsonb_build_object('text', t, 'kb', 'none');
  END IF;

  IF act = 'by_day' THEN
    t := 'Gastos por dia (' || lbl || ', ' || to_char(rs, 'DD/MM') || ' a ' || to_char(re, 'DD/MM') || '):';
    k := 0;
    FOR r IN SELECT occurred_on, sum(amount) s, count(*) n FROM fin_entries WHERE user_id = p_user AND kind = 'expense' AND status = 'paid' AND occurred_on BETWEEN rs AND re
             GROUP BY 1 ORDER BY 1 DESC LIMIT 15 LOOP
      k := k + 1; t := t || E'\n- ' || to_char(r.occurred_on, 'DD/MM') || ': ' || f_brl(r.s) || ' (' || r.n || ' lançamento(s))';
    END LOOP;
    IF k = 0 THEN RETURN jsonb_build_object('text', 'Nenhum gasto registrado em ' || lbl || '.', 'kb', 'none'); END IF;
    RETURN jsonb_build_object('text', t, 'kb', 'none');
  END IF;

  -- summary
  SELECT coalesce(sum(amount) FILTER (WHERE kind = 'expense'), 0), coalesce(sum(amount) FILTER (WHERE kind = 'income'), 0) INTO v_exp, v_inc
  FROM fin_entries WHERE user_id = p_user AND status = 'paid' AND occurred_on BETWEEN rs AND re;
  t := 'Resumo (' || lbl || ', ' || to_char(rs, 'DD/MM') || ' a ' || to_char(re, 'DD/MM') || '):' ||
       E'\nGastos: ' || f_brl(v_exp) || E'\nReceitas: ' || f_brl(v_inc) || E'\nSaldo: ' || CASE WHEN v_inc - v_exp < 0 THEN '-' ELSE '' END || f_brl(abs(v_inc - v_exp));
  k := 0;
  FOR r IN SELECT coalesce(c.name, 'Outros') AS name, sum(e.amount) s, c.budget FROM fin_entries e LEFT JOIN fin_categories c ON c.id = e.category_id
           WHERE e.user_id = p_user AND e.kind = 'expense' AND e.status = 'paid' AND e.occurred_on BETWEEN rs AND re GROUP BY c.name, c.budget ORDER BY 2 DESC LIMIT 10 LOOP
    IF k = 0 THEN t := t || E'\n\nGastos por categoria:'; END IF;
    k := k + 1;
    t := t || E'\n- ' || r.name || ': ' || f_brl(r.s) || ' (' || round(r.s / v_exp * 100) || '%)' ||
         CASE WHEN r.budget IS NOT NULL THEN ', orçamento ' || f_brl(r.budget) || ' (' || round(r.s / r.budget * 100) || '%)' ELSE '' END;
  END LOOP;
  IF k = 0 AND v_inc = 0 THEN t := 'Nenhum lançamento em ' || lbl || ' (' || to_char(rs, 'DD/MM') || ' a ' || to_char(re, 'DD/MM') || '). Para começar, diga por exemplo: "gastei 42 no mercado".'; END IF;
  t := t || f_fin_pending_text(p_user);
  RETURN jsonb_build_object('text', t, 'kb', 'none');
END $$;
