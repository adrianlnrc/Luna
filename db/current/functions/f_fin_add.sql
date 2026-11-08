-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_add(p_user bigint, p jsonb)
-- Origem da definicao atual: 008_financas.sql (linha 245)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:245
CREATE OR REPLACE FUNCTION f_fin_add(p_user bigint, p jsonb) RETURNS jsonb LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE
  today date := f_fin_today(p_user);
  v_kind text := CASE WHEN p->>'kind' = 'income' THEN 'income' ELSE 'expense' END;
  v_amt numeric := round(nullif(p->>'amount', '')::numeric, 2);
  v_title text := left(btrim(coalesce(p->>'title', '')), 120);
  v_norm text; v_cat bigint; v_catname text;
  v_method text := nullif(p->>'method', '');
  n integer := least(greatest(coalesce(nullif(p->>'installments', '')::int, 1), 1), 36);
  v_paid boolean := coalesce((p->>'paid')::boolean, true);
  d date := coalesce(f_safe_date(p->>'date'), today);
  rday integer := nullif(p->>'recurring_day', '')::int;
  v_person text := nullif(btrim(coalesce(p->>'person', '')), '');
  v_src text := coalesce(p->>'source', 'text');
  v_id bigint; v_first bigint; v_rec bigint; v_series uuid; i integer; v_txt text; v_label text;
BEGIN
  IF v_amt IS NULL OR v_amt <= 0 THEN
    RETURN jsonb_build_object('text', 'Qual foi o valor? Me diga o valor para eu registrar.', 'kb', 'none');
  END IF;
  IF v_title = '' THEN v_title := CASE WHEN v_kind = 'income' THEN 'Recebimento' ELSE 'Gasto' END; END IF;
  IF v_method IS NOT NULL AND v_method NOT IN ('pix', 'debito', 'credito', 'dinheiro', 'boleto') THEN v_method := NULL; END IF;
  v_norm := f_norm(v_title);
  v_cat := f_fin_cat(p_user, v_kind, p->>'category', v_norm, coalesce((p->>'category_stated')::boolean, false));
  SELECT name INTO v_catname FROM fin_categories WHERE id = v_cat;
  v_label := CASE WHEN v_kind = 'income' THEN 'receita' ELSE 'gasto' END;

  -- conta ou receita que se repete todo mes
  IF rday IS NOT NULL AND rday BETWEEN 1 AND 31 THEN
    INSERT INTO fin_recurring (user_id, kind, amount, description, category_id, method, day_of_month, person)
    VALUES (p_user, v_kind, v_amt, v_title, v_cat, v_method, rday, v_person) RETURNING id INTO v_rec;
    v_id := f_fin_gen(v_rec);
    SELECT due_on INTO d FROM fin_entries WHERE id = v_id;
    RETURN jsonb_build_object('text', 'Anotei ' || CASE WHEN v_kind = 'income' THEN 'a receita' ELSE 'a conta' END || ' fixa: ' || v_title || ' ' || f_brl(v_amt) ||
      ' todo dia ' || rday || ' (' || v_catname || '). Próximo vencimento: ' || to_char(d, 'DD/MM') ||
      '. Te aviso no dia e você toca Feito quando ' || CASE WHEN v_kind = 'income' THEN 'receber.' ELSE 'pagar.' END, 'kb', 'fin_undo', 'rid', v_id);
  END IF;

  -- compra parcelada: cada parcela entra no mes dela
  IF n > 1 THEN
    v_series := gen_random_uuid();
    FOR i IN 1..n LOOP
      INSERT INTO fin_entries (user_id, kind, amount, description, norm_desc, category_id, method, status, occurred_on, paid_on, person, installment_no, installments, series_id, source)
      VALUES (p_user, v_kind, v_amt, v_title, v_norm, v_cat, coalesce(v_method, 'credito'), 'paid', (d + make_interval(months => i - 1))::date, (d + make_interval(months => i - 1))::date, v_person, i, n, v_series, v_src)
      RETURNING id INTO v_id;
      IF i = 1 THEN v_first := v_id; END IF;
    END LOOP;
    RETURN jsonb_build_object('text', 'Registrei: ' || v_title || ' em ' || n || 'x de ' || f_brl(v_amt) || ' (total ' || f_brl(v_amt * n) || '), categoria ' || v_catname ||
      '. As parcelas entram mês a mês, a primeira em ' || to_char(d, 'DD/MM') || '.' || f_fin_budget_note(p_user, v_cat, v_amt, d), 'kb', 'fin_undo', 'rid', v_first);
  END IF;

  -- foto ou arquivo (recibo, boleto): confirma antes de gravar; se for conta a pagar, guarda o vencimento no rascunho
  IF v_src = 'photo' THEN
    INSERT INTO fin_entries (user_id, kind, amount, description, norm_desc, category_id, method, status, occurred_on, due_on, person, source)
    VALUES (p_user, v_kind, v_amt, v_title, v_norm, v_cat, v_method, 'draft', d, CASE WHEN NOT v_paid THEN d END, v_person, v_src) RETURNING id INTO v_id;
    IF v_paid THEN
      RETURN jsonb_build_object('text', 'Li no documento: ' || f_brl(v_amt) || ' em "' || v_title || '", categoria ' || v_catname || ', data ' || to_char(d, 'DD/MM') ||
        '. Confirma?', 'kb', 'fin_confirm', 'rid', v_id);
    END IF;
    RETURN jsonb_build_object('text', 'Li no documento: conta de ' || f_brl(v_amt) || ' "' || v_title || '", vence ' || to_char(d, 'DD/MM') || ', categoria ' || v_catname ||
      '. Anoto como a pagar e te aviso no dia. Confirma?', 'kb', 'fin_confirm', 'rid', v_id);
  END IF;

  -- conta a pagar / receita a receber / alguem te deve
  IF NOT v_paid THEN
    INSERT INTO fin_entries (user_id, kind, amount, description, norm_desc, category_id, method, status, occurred_on, due_on, person, source)
    VALUES (p_user, v_kind, v_amt, v_title, v_norm, v_cat, v_method, 'pending', d, d, v_person, v_src) RETURNING id INTO v_id;
    PERFORM f_fin_remind(v_id);
    IF v_kind = 'income' AND v_person IS NOT NULL THEN
      v_txt := 'Anotei: ' || v_person || ' te deve ' || f_brl(v_amt) || ' (' || v_title || ', desde ' || to_char(d, 'DD/MM') || '). Quando pagar, diga "' || v_person || ' pagou".';
    ELSIF v_kind = 'income' THEN
      v_txt := 'Anotei a receber: ' || v_title || ' ' || f_brl(v_amt) || ', previsto para ' || to_char(d, 'DD/MM') || '. Te aviso no dia.';
    ELSE
      v_txt := 'Anotei a pagar: ' || v_title || ' ' || f_brl(v_amt) || ', vence ' || to_char(d, 'DD/MM') || ' (' || v_catname || '). Te aviso no dia; depois é só tocar Feito ou dizer "já paguei".';
    END IF;
    RETURN jsonb_build_object('text', v_txt, 'kb', 'fin_undo', 'rid', v_id);
  END IF;

  -- lancamento simples ja pago
  INSERT INTO fin_entries (user_id, kind, amount, description, norm_desc, category_id, method, status, occurred_on, paid_on, person, source)
  VALUES (p_user, v_kind, v_amt, v_title, v_norm, v_cat, v_method, 'paid', d, d, v_person, v_src) RETURNING id INTO v_id;
  RETURN jsonb_build_object('text', 'Registrei: ' || v_label || ' de ' || f_brl(v_amt) || ' em ' || v_title || ' (' || v_catname || ')' ||
    CASE WHEN v_method IS NOT NULL THEN ', ' || v_method ELSE '' END ||
    CASE WHEN d <> today THEN ', ' || to_char(d, 'DD/MM') ELSE '' END || '.' ||
    CASE WHEN v_kind = 'expense' THEN f_fin_budget_note(p_user, v_cat, v_amt, d) ELSE '' END, 'kb', 'fin_undo', 'rid', v_id);
END $$;
