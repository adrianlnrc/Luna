-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_report_data(p_user bigint, p jsonb)
-- Origem da definicao atual: 027_relatorios.sql (linha 5)
-- Definicoes (migracao:linha), da mais antiga a atual: 027_relatorios.sql:5
CREATE OR REPLACE FUNCTION agente.f_report_data(p_user bigint, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE
  v_month text := coalesce(p->>'month', '');
  v_period text := coalesce(nullif(p->>'period', ''), 'current');
  ms date; me date; lbl text;
  is_ir boolean := coalesce(p->>'keywords', '') ~* '(imposto|irpf|declara|(^|[^a-z])ir([^a-z]|$))';
  v_count integer; v_trunc boolean := false;
  lines jsonb := '[]'::jsonb; r record; fm text;
  tot_exp numeric := 0; tot_inc numeric := 0; ir_tot numeric := 0;
  blank jsonb := jsonb_build_object('Data','','Descrição','','Categoria','','Forma de pagamento','','Cartão','','Parcela','','Valor','','Situação','','Tipo','');
BEGIN
  IF v_month ~ '^[0-9]{4}$' THEN
    ms := make_date(v_month::int, 1, 1); me := make_date(v_month::int, 12, 31);
    lbl := 'ano de ' || v_month || ' (' || to_char(ms, 'DD/MM') || ' a ' || to_char(me, 'DD/MM') || ')';
  ELSE
    SELECT m_start, m_end, m_label INTO ms, me, lbl FROM f_fin_month(p_user, v_month, v_period);
  END IF;
  IF is_ir THEN
    SELECT count(*) INTO v_count FROM fin_entries e JOIN fin_categories c ON c.id = e.category_id
     WHERE e.user_id = p_user AND e.kind = 'expense' AND e.status = 'paid' AND e.occurred_on BETWEEN ms AND me
       AND c.name ~* '^(sa.de|educa)';
  ELSE
    SELECT count(*) INTO v_count FROM fin_entries e
     WHERE e.user_id = p_user AND e.occurred_on BETWEEN ms AND me;
  END IF;
  IF v_count = 0 THEN
    RETURN jsonb_build_object('count', 0, 'label', lbl, 'ir', is_ir, 'lines', '[]'::jsonb);
  END IF;
  v_trunc := v_count > 5000;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'Data', to_char(x.occurred_on, 'DD/MM/YYYY'), 'Descrição', x.description,
      'Categoria', coalesce(x.cat, 'Sem categoria'),
      'Forma de pagamento', CASE x.method WHEN 'pix' THEN 'Pix' WHEN 'debito' THEN 'Débito' WHEN 'credito' THEN 'Crédito'
                                          WHEN 'dinheiro' THEN 'Dinheiro' WHEN 'boleto' THEN 'Boleto' ELSE coalesce(x.method, '') END,
      'Cartão', coalesce(x.card, ''),
      'Parcela', CASE WHEN coalesce(x.installments, 1) > 1 THEN x.installment_no || '/' || x.installments ELSE '' END,
      'Valor', x.amount, 'Situação', CASE x.status WHEN 'paid' THEN 'Pago' WHEN 'pending' THEN 'Pendente' ELSE x.status END,
      'Tipo', CASE x.kind WHEN 'income' THEN 'Receita' ELSE 'Despesa' END) ORDER BY x.occurred_on, x.id), '[]'::jsonb)
    INTO lines
    FROM (SELECT e.*, c.name AS cat, k.name AS card
            FROM fin_entries e
            LEFT JOIN fin_categories c ON c.id = e.category_id
            LEFT JOIN fin_cards k ON k.id = e.card_id
           WHERE e.user_id = p_user AND e.occurred_on BETWEEN ms AND me
             AND (NOT is_ir OR (e.kind = 'expense' AND e.status = 'paid' AND c.name ~* '^(sa.de|educa)'))
           ORDER BY e.occurred_on, e.id LIMIT 5000) x;

  -- segunda parte: totais por categoria e por mes (sobre as linhas incluidas)
  lines := lines || jsonb_build_array(blank, blank || jsonb_build_object('Descrição', 'TOTAL POR CATEGORIA'));
  FOR r IN
    SELECT (l->>'Categoria') AS cat, (l->>'Tipo') AS tipo, sum((l->>'Valor')::numeric) AS s, count(*) AS n
      FROM jsonb_array_elements(lines) l
     WHERE l->>'Valor' <> '' AND l->>'Data' <> ''
     GROUP BY 1, 2 ORDER BY 2, 3 DESC
  LOOP
    lines := lines || jsonb_build_array(blank || jsonb_build_object('Descrição', 'Total (' || r.n || CASE WHEN r.n = 1 THEN ' lançamento)' ELSE ' lançamentos)' END, 'Categoria', r.cat, 'Valor', r.s, 'Tipo', r.tipo));
  END LOOP;
  lines := lines || jsonb_build_array(blank, blank || jsonb_build_object('Descrição', 'TOTAL POR MÊS'));
  FOR r IN
    SELECT substr(l->>'Data', 7, 4) || '-' || substr(l->>'Data', 4, 2) AS mes, (l->>'Tipo') AS tipo, sum((l->>'Valor')::numeric) AS s
      FROM jsonb_array_elements(lines) l
     WHERE l->>'Valor' <> '' AND l->>'Data' ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' AND l->>'Descrição' NOT LIKE 'Total%'
     GROUP BY 1, 2 ORDER BY 1, 2
  LOOP
    lines := lines || jsonb_build_array(blank || jsonb_build_object('Data', r.mes, 'Descrição', 'Total do mês', 'Valor', r.s, 'Tipo', r.tipo));
  END LOOP;

  SELECT coalesce(sum((l->>'Valor')::numeric) FILTER (WHERE l->>'Tipo' = 'Despesa'), 0),
         coalesce(sum((l->>'Valor')::numeric) FILTER (WHERE l->>'Tipo' = 'Receita'), 0)
    INTO tot_exp, tot_inc
    FROM jsonb_array_elements(lines) l
   WHERE l->>'Valor' <> '' AND l->>'Data' ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$';
  IF is_ir THEN
    ir_tot := tot_exp;
    lines := lines || jsonb_build_array(blank,
      blank || jsonb_build_object('Descrição', 'TOTAL SAÚDE + EDUCAÇÃO (pago)', 'Valor', ir_tot, 'Tipo', 'Despesa'),
      blank || jsonb_build_object('Descrição', 'Ajuda para organizar os comprovantes; não é a declaração do imposto de renda.'));
  END IF;

  RETURN jsonb_build_object('count', v_count, 'truncated', v_trunc, 'label', lbl, 'ir', is_ir,
    'total_expense', tot_exp, 'total_income', tot_inc,
    'filename', CASE WHEN is_ir THEN 'ir-saude-educacao-' ELSE 'financas-' END || to_char(ms, 'YYYY-MM-DD') || '_a_' || to_char(me, 'YYYY-MM-DD'),
    'caption', CASE WHEN is_ir THEN 'Saúde e Educação pagos ' ELSE 'Lançamentos ' END || lbl || ': ' || least(v_count, 5000) || ' linhas. '
               || CASE WHEN is_ir THEN 'Total: ' || f_brl(tot_exp) || '. Ajuda para organizar, não é a declaração.'
                       ELSE 'Despesas ' || f_brl(tot_exp) || CASE WHEN tot_inc > 0 THEN ', receitas ' || f_brl(tot_inc) ELSE '' END || '.' END
               || CASE WHEN v_trunc THEN ' Limitei às primeiras 5.000 linhas.' ELSE '' END,
    'lines', lines);
END $function$;
