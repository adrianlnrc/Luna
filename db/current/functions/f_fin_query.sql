-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_query(p_user bigint, p jsonb)
-- Origem da definicao atual: 013_extras.sql (linha 402)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:402
CREATE OR REPLACE FUNCTION f_fin_query(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE act text := coalesce(p->>'action', ''); ms date; me date; lbl text; today date := f_fin_today(p_user);
        hint text; cat bigint; catname text; bud numeric; v_sum numeric; v_n integer; t text := ''; r record; v_meth text; v_com numeric := 0; v_inst numeric := 0; k integer := 0;
BEGIN
  SELECT m_start, m_end, m_label INTO ms, me, lbl FROM f_fin_month(p_user, coalesce(p->>'month', ''), coalesce(p->>'period', ''));

  IF act = 'category_total' THEN
    hint := coalesce(nullif(btrim(p->>'category'), ''), nullif(btrim(p->>'title'), ''), '');
    IF hint = '' THEN
      RETURN jsonb_build_object('text', 'De qual categoria? Ex.: "quanto foi de mercado em agosto?".', 'kb', 'none');
    END IF;
    cat := f_fin_cat_find(p_user, 'expense', hint, f_norm(hint));
    IF cat IS NOT NULL THEN
      SELECT name, budget INTO catname, bud FROM fin_categories WHERE id = cat;
      SELECT coalesce(sum(amount), 0), count(*) INTO v_sum, v_n FROM fin_entries
       WHERE user_id = p_user AND kind = 'expense' AND status = 'paid' AND category_id = cat AND occurred_on BETWEEN ms AND me;
      t := catname || ' ' || lbl || ': ' || f_brl(v_sum) || CASE WHEN v_n > 0 THEN ' (' || v_n || ' lançamento' || CASE WHEN v_n > 1 THEN 's' ELSE '' END || ')' ELSE ' (nenhum lançamento)' END || '.';
      IF bud IS NOT NULL THEN t := t || ' Orçamento ' || f_brl(bud) || ': ' || round(v_sum / bud * 100) || '%.'; END IF;
      FOR r IN SELECT description, amount, occurred_on FROM fin_entries WHERE user_id = p_user AND kind = 'expense' AND status = 'paid' AND category_id = cat AND occurred_on BETWEEN ms AND me ORDER BY amount DESC LIMIT 3 LOOP
        IF k = 0 THEN t := t || E'\nMaiores:'; END IF; k := k + 1;
        t := t || E'\n- ' || r.description || ' ' || f_brl(r.amount) || ' (' || to_char(r.occurred_on, 'DD/MM') || ')';
      END LOOP;
      RETURN jsonb_build_object('text', t, 'kb', 'none');
    END IF;
    -- sem categoria com esse nome: procura na descricao dos lancamentos
    SELECT coalesce(sum(amount), 0), count(*) INTO v_sum, v_n FROM fin_entries
     WHERE user_id = p_user AND kind = 'expense' AND status = 'paid' AND norm_desc LIKE '%' || f_norm(hint) || '%' AND occurred_on BETWEEN ms AND me;
    IF v_n > 0 THEN
      RETURN jsonb_build_object('text', 'Não tenho categoria "' || hint || '", mas lançamentos com esse nome ' || lbl || ' somam ' || f_brl(v_sum) || ' (' || v_n || ').', 'kb', 'none');
    END IF;
    SELECT string_agg(name, ', ' ORDER BY name) INTO t FROM fin_categories WHERE user_id = p_user AND kind = 'expense';
    RETURN jsonb_build_object('text', 'Não achei a categoria "' || hint || '". Suas categorias: ' || coalesce(t, '-') || '.', 'kb', 'none');
  END IF;

  IF act = 'method_total' THEN
    v_meth := nullif(p->>'method', '');
    IF v_meth IS NULL THEN
      FOR r IN SELECT coalesce(method, 'sem forma') AS m, sum(amount) s, count(*) n FROM fin_entries
               WHERE user_id = p_user AND kind = 'expense' AND status = 'paid' AND occurred_on BETWEEN ms AND me GROUP BY 1 ORDER BY 2 DESC LOOP
        k := k + 1; t := t || E'\n- ' || r.m || ': ' || f_brl(r.s) || ' (' || r.n || ')';
      END LOOP;
      IF k = 0 THEN RETURN jsonb_build_object('text', 'Nenhum gasto registrado ' || lbl || '.', 'kb', 'none'); END IF;
      RETURN jsonb_build_object('text', 'Gastos por forma de pagamento ' || lbl || ':' || t, 'kb', 'none');
    END IF;
    SELECT coalesce(sum(amount), 0), count(*) INTO v_sum, v_n FROM fin_entries
     WHERE user_id = p_user AND kind = 'expense' AND status = 'paid' AND method = v_meth AND occurred_on BETWEEN ms AND me;
    t := 'Gastos ' || CASE v_meth WHEN 'credito' THEN 'no crédito' WHEN 'debito' THEN 'no débito' WHEN 'pix' THEN 'no Pix' WHEN 'dinheiro' THEN 'em dinheiro' WHEN 'boleto' THEN 'no boleto' ELSE v_meth END ||
         ' ' || lbl || ': ' || f_brl(v_sum) || ' (' || v_n || ' lançamento' || CASE WHEN v_n <> 1 THEN 's' ELSE '' END || ').';
    FOR r IN SELECT description, amount, occurred_on FROM fin_entries WHERE user_id = p_user AND kind = 'expense' AND status = 'paid' AND method = v_meth AND occurred_on BETWEEN ms AND me ORDER BY amount DESC LIMIT 3 LOOP
      IF k = 0 THEN t := t || E'\nMaiores:'; END IF; k := k + 1;
      t := t || E'\n- ' || r.description || ' ' || f_brl(r.amount) || ' (' || to_char(r.occurred_on, 'DD/MM') || ')';
    END LOOP;
    RETURN jsonb_build_object('text', t, 'kb', 'none');
  END IF;

  IF act = 'left_to_close' THEN
    SELECT p_end INTO me FROM f_fin_period(p_user, 0);
    RETURN jsonb_build_object('text', f_fin_plan_text(p_user) || E'\n\nO mês financeiro vai até ' || to_char(me, 'DD/MM') || ' (faltam ' || (me - today + 1) || ' dia' || CASE WHEN me - today + 1 <> 1 THEN 's' ELSE '' END || ', contando hoje).', 'kb', 'none');
  END IF;

  IF act = 'committed' THEN
    -- sem mes informado: o proximo periodo (o que ainda vem pela frente)
    IF coalesce(p->>'month', '') !~ '^[0-9]{4}-[0-9]{2}$' THEN
      SELECT p_start, p_end INTO ms, me FROM f_fin_period(p_user, 1);
      lbl := 'no próximo mês (' || to_char(ms, 'DD/MM') || ' a ' || to_char(me, 'DD/MM') || ')';
    END IF;
    SELECT coalesce(sum(amount), 0) INTO v_com FROM fin_entries WHERE user_id = p_user AND kind = 'expense' AND status = 'pending' AND due_on BETWEEN ms AND me;
    SELECT coalesce(sum(amount), 0) INTO v_inst FROM fin_entries WHERE user_id = p_user AND kind = 'expense' AND status = 'paid' AND occurred_on > today AND occurred_on BETWEEN ms AND me;
    IF v_com + v_inst = 0 THEN
      RETURN jsonb_build_object('text', 'Nada comprometido ' || lbl || ' (sem contas a pagar nem parcelas com data nesse período).', 'kb', 'none');
    END IF;
    t := 'Comprometido ' || lbl || ': ' || f_brl(v_com + v_inst) || E'\n- Contas a pagar: ' || f_brl(v_com) || E'\n- Parcelas e lançamentos futuros: ' || f_brl(v_inst);
    FOR r IN SELECT description, amount, coalesce(due_on, occurred_on) AS d, status, installment_no, installments FROM fin_entries
             WHERE user_id = p_user AND kind = 'expense' AND ((status = 'pending' AND due_on BETWEEN ms AND me) OR (status = 'paid' AND occurred_on > today AND occurred_on BETWEEN ms AND me))
             ORDER BY coalesce(due_on, occurred_on), id LIMIT 8 LOOP
      IF k = 0 THEN t := t || E'\nItens:'; END IF; k := k + 1;
      t := t || E'\n- ' || r.description || ' ' || f_brl(r.amount) || ' (' || to_char(r.d, 'DD/MM') || CASE WHEN r.installments IS NOT NULL THEN ', parcela ' || r.installment_no || '/' || r.installments ELSE '' END || ')';
    END LOOP;
    RETURN jsonb_build_object('text', t, 'kb', 'none');
  END IF;

  RETURN jsonb_build_object('text', 'Não entendi essa consulta.', 'kb', 'none');
EXCEPTION WHEN others THEN
  RAISE WARNING 'f_fin_query: %', SQLERRM;
  RETURN jsonb_build_object('text', 'Não consegui calcular isso agora. Tente de novo em instantes.', 'kb', 'none');
END $$;
