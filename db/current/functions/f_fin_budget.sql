-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_budget(p_user bigint, p jsonb)
-- Origem da definicao atual: 008_financas.sql (linha 543)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:543
CREATE OR REPLACE FUNCTION f_fin_budget(p_user bigint, p jsonb) RETURNS jsonb LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE
  act text := p->>'action'; v_hint text := btrim(coalesce(nullif(p->>'category', ''), p->>'title', '')); v_amt numeric := round(nullif(p->>'budget_amount', '')::numeric, 2);
  v_cat bigint; c fin_categories%ROWTYPE; ps date; pe date; sp numeric; t text := ''; r record; k integer := 0; left_days integer; a1 numeric; a2 numeric; n1 integer; n2 integer;
  s1 date; e1 date; s2 date; e2 date;
BEGIN
  PERFORM f_fin_seed(p_user);
  SELECT p_start, p_end INTO ps, pe FROM f_fin_period(p_user, 0);
  IF act = 'budget_set' THEN
    IF v_amt IS NULL OR v_amt <= 0 THEN RETURN jsonb_build_object('text', 'Qual o valor do orçamento mensal? Ex.: "orçamento de mercado 800".', 'kb', 'none'); END IF;
    IF v_hint = '' THEN RETURN jsonb_build_object('text', 'Para qual categoria? Ex.: "orçamento de mercado 800".', 'kb', 'none'); END IF;
    v_cat := f_fin_cat_find(p_user, 'expense', v_hint, '');
    IF v_cat IS NULL THEN
      INSERT INTO fin_categories (user_id, name, kind) VALUES (p_user, initcap(left(v_hint, 60)), 'expense') ON CONFLICT DO NOTHING;
      v_cat := f_fin_cat_find(p_user, 'expense', v_hint, '');
    END IF;
    UPDATE fin_categories SET budget = v_amt WHERE id = v_cat RETURNING * INTO c;
    sp := f_fin_spent(p_user, c.id, ps, pe);
    RETURN jsonb_build_object('text', 'Orçamento de ' || c.name || ': ' || f_brl(v_amt) || ' por mês (mês financeiro ' || to_char(ps, 'DD/MM') || ' a ' || to_char(pe, 'DD/MM') || '). Até agora: ' ||
      f_brl(sp) || ' (' || round(sp / v_amt * 100) || '%). Aviso quando chegar a 80% e a 100%.', 'kb', 'none');
  END IF;

  -- budget_status
  IF v_hint <> '' THEN
    v_cat := f_fin_cat_find(p_user, 'expense', v_hint, '');
    IF v_cat IS NULL THEN RETURN jsonb_build_object('text', 'Não conheço a categoria "' || v_hint || '". Diga "minhas categorias" para ver a lista.', 'kb', 'none'); END IF;
    SELECT * INTO c FROM fin_categories WHERE id = v_cat;
    sp := f_fin_spent(p_user, c.id, ps, pe);
    left_days := greatest(pe - f_fin_today(p_user) + 1, 1);
    IF c.budget IS NOT NULL THEN
      RETURN jsonb_build_object('text', c.name || ': gasto ' || f_brl(sp) || ' de ' || f_brl(c.budget) || ' (' || round(sp / c.budget * 100) || '%). ' ||
        CASE WHEN c.budget > sp THEN 'Restam ' || f_brl(c.budget - sp) || ' para ' || left_days || ' dia(s), cerca de ' || f_brl((c.budget - sp) / left_days) || ' por dia.'
             ELSE 'Passou ' || f_brl(sp - c.budget) || ' do orçamento.' END, 'kb', 'none');
    END IF;
    SELECT p_start, p_end INTO s1, e1 FROM f_fin_period(p_user, -1);
    SELECT p_start, p_end INTO s2, e2 FROM f_fin_period(p_user, -2);
    a1 := f_fin_spent(p_user, c.id, s1, e1); a2 := f_fin_spent(p_user, c.id, s2, e2);
    RETURN jsonb_build_object('text', c.name || ' ainda não tem orçamento. Gasto no mês atual: ' || f_brl(sp) || '.' ||
      CASE WHEN a1 > 0 AND a2 > 0 THEN ' Nos 2 meses anteriores você gastou em média ' || f_brl(round((a1 + a2) / 2)) || '. Para definir: "orçamento de ' || lower(c.name) || ' ' || round((a1 + a2) / 2) || '".'
           ELSE ' Para definir: "orçamento de ' || lower(c.name) || ' 500".' END, 'kb', 'none');
  END IF;
  FOR r IN SELECT name, budget, f_fin_spent(p_user, id, ps, pe) AS sp FROM fin_categories WHERE user_id = p_user AND kind = 'expense' AND budget IS NOT NULL ORDER BY name LOOP
    k := k + 1;
    t := t || E'\n- ' || r.name || ': ' || f_brl(r.sp) || ' de ' || f_brl(r.budget) || ' (' || round(r.sp / r.budget * 100) || '%)' ||
         CASE WHEN r.budget > r.sp THEN ', restam ' || f_brl(r.budget - r.sp) ELSE ', passou ' || f_brl(r.sp - r.budget) END;
  END LOOP;
  IF k = 0 THEN RETURN jsonb_build_object('text', 'Você ainda não definiu orçamentos. Ex.: "orçamento de mercado 800" ou "orçamento de lazer 300".', 'kb', 'none'); END IF;
  RETURN jsonb_build_object('text', 'Orçamentos (' || to_char(ps, 'DD/MM') || ' a ' || to_char(pe, 'DD/MM') || '):' || t, 'kb', 'none');
END $$;
