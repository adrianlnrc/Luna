-- Assessor (PRD RF-08): retrato unificado. Uma chamada devolve o estado de todas as areas no horizonte.
-- Leva totais e sinais, nao lancamentos brutos. Sem IA. Idempotente. NAO aplicado em producao.
-- Os compromissos do Google sao anexados por quem chama (servico ou n8n): a agenda mora no Google.
SET search_path = agente, public;

CREATE OR REPLACE FUNCTION f_assessor_snapshot(p_user bigint, p_dias int DEFAULT 14) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE
  u users%ROWTYPE; today date; ate date; ps date; pe date; v_dias int := greatest(coalesce(p_dias, 14), 1);
  sp numeric; inc numeric; dias_rest int; r record;
  j_din jsonb; j_cats jsonb := '[]'; j_contas jsonb := '[]'; j_fat jsonb := '[]'; j_metas jsonb := '[]';
  j_proj jsonb; j_atras jsonb := '[]'; j_prazos jsonb := '[]'; j_est jsonb := '[]'; j_docs jsonb := '[]'; j_lemb jsonb := '[]';
  t text := ''; sec text; s date; pv date; dd date; fechada numeric; aberta numeric; n int;
BEGIN
  SELECT * INTO u FROM users WHERE id = p_user;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'usuario', 'text', ''); END IF;
  today := f_fin_today(p_user);
  ate := today + v_dias;
  SELECT p_start, p_end INTO ps, pe FROM f_fin_period(p_user, 0);

  -- ---- dinheiro ----
  sp := f_fin_total_spent(p_user, ps, pe);
  SELECT coalesce(sum(amount), 0) INTO inc FROM fin_entries
   WHERE user_id = p_user AND kind = 'income' AND status = 'paid' AND occurred_on BETWEEN ps AND pe;
  dias_rest := greatest(pe - today + 1, 1);

  FOR r IN SELECT c.name, c.budget, f_fin_spent(p_user, c.id, ps, pe) AS gasto FROM fin_categories c
            WHERE c.user_id = p_user AND c.kind = 'expense' AND coalesce(c.budget, 0) > 0 ORDER BY c.name LOOP
    IF r.gasto >= r.budget * 0.8 THEN
      j_cats := j_cats || jsonb_build_object('categoria', r.name, 'orcamento', r.budget, 'gasto', r.gasto, 'pct', round(r.gasto / r.budget * 100));
    END IF;
  END LOOP;

  FOR r IN SELECT description, amount, due_on FROM fin_entries
            WHERE user_id = p_user AND kind = 'expense' AND status = 'pending' AND due_on IS NOT NULL AND due_on <= ate
            ORDER BY due_on, id LIMIT 12 LOOP
    j_contas := j_contas || jsonb_build_object('descricao', r.description, 'valor', r.amount, 'vence', to_char(r.due_on, 'DD/MM'),
                                               'dias', r.due_on - today, 'atrasada', r.due_on < today);
  END LOOP;

  FOR r IN SELECT * FROM fin_cards WHERE user_id = p_user AND active ORDER BY name LOOP
    s := f_card_close_le(r.closing_day, today);
    pv := f_card_close_le(r.closing_day, s - 1);
    dd := f_card_due_gt(r.due_day, s);
    fechada := f_card_sum(r.id, pv, s);
    aberta := f_card_sum(r.id, s, today + 400);
    j_fat := j_fat || jsonb_build_object('cartao', r.name, 'fatura_fechada', fechada, 'vence', to_char(dd, 'DD/MM'), 'dias', dd - today,
      'fatura_aberta', aberta, 'limite', r.card_limit,
      'limite_disponivel', CASE WHEN r.card_limit IS NULL THEN NULL
                                ELSE greatest(r.card_limit - aberta - CASE WHEN dd >= today THEN fechada ELSE 0 END, 0) END);
  END LOOP;

  FOR r IN SELECT g.id, g.name, g.target, g.deadline, f_fin_goal_saved(g.id) AS saved FROM fin_goals g WHERE g.user_id = p_user ORDER BY g.id LOOP
    j_metas := j_metas || jsonb_build_object('meta', r.name, 'alvo', r.target, 'guardado', r.saved, 'falta', greatest(r.target - r.saved, 0),
                                             'prazo', CASE WHEN r.deadline IS NULL THEN NULL ELSE to_char(r.deadline, 'DD/MM/YYYY') END);
  END LOOP;

  j_din := jsonb_build_object(
    'mes', to_char(ps, 'DD/MM') || ' a ' || to_char(pe, 'DD/MM'), 'gasto_mes', sp, 'receitas_mes', inc, 'renda_prevista', u.fin_income,
    'limite_mes', u.fin_total_limit,
    'limite_pct', CASE WHEN coalesce(u.fin_total_limit, 0) > 0 THEN round(sp / u.fin_total_limit * 100) ELSE NULL END,
    'pode_gastar', CASE WHEN u.fin_total_limit IS NULL THEN NULL ELSE greatest(u.fin_total_limit - sp, 0) END,
    'pode_gastar_por_dia', CASE WHEN u.fin_total_limit IS NULL THEN NULL ELSE round(greatest(u.fin_total_limit - sp, 0) / dias_rest, 2) END,
    'dias_restantes', dias_rest, 'categorias_no_teto', j_cats, 'contas_a_pagar', j_contas, 'cartoes', j_fat, 'metas', j_metas);

  -- ---- projetos ----
  FOR r IN SELECT p.name AS projeto, t2.title, t2.due_date, t2.urgent FROM project_tasks t2 JOIN projects p ON p.id = t2.project_id
            WHERE t2.user_id = p_user AND NOT t2.done AND t2.due_date IS NOT NULL AND t2.due_date < today
            ORDER BY t2.due_date, t2.id LIMIT 10 LOOP
    j_atras := j_atras || jsonb_build_object('projeto', r.projeto, 'tarefa', r.title, 'prazo', to_char(r.due_date, 'DD/MM'),
                                             'dias_atraso', today - r.due_date, 'urgente', r.urgent);
  END LOOP;
  FOR r IN SELECT p.id, p.name, p.due_date,
                  (SELECT count(*) FROM project_tasks x WHERE x.project_id = p.id AND NOT x.done) AS abertas,
                  (SELECT count(*) FROM project_tasks x WHERE x.project_id = p.id) AS total
             FROM projects p WHERE p.user_id = p_user AND p.due_date IS NOT NULL AND p.due_date BETWEEN today AND ate
            ORDER BY p.due_date, p.id LIMIT 10 LOOP
    j_prazos := j_prazos || jsonb_build_object('projeto', r.name, 'prazo', to_char(r.due_date, 'DD/MM'), 'dias', r.due_date - today,
                                               'tarefas_abertas', r.abertas, 'tarefas_total', r.total);
  END LOOP;
  j_proj := jsonb_build_object('tarefas_atrasadas', j_atras, 'prazos', j_prazos);

  -- ---- estoque ----
  FOR r IN SELECT item, kind, units_left, runs_out_on FROM supplies_status
            WHERE user_id = p_user AND status = 'active' AND runs_out_on IS NOT NULL AND runs_out_on <= ate
            ORDER BY runs_out_on, id LIMIT 10 LOOP
    j_est := j_est || jsonb_build_object('item', r.item, 'tipo', r.kind, 'restam', r.units_left,
                                         'acaba_em', to_char(r.runs_out_on, 'DD/MM'), 'dias', r.runs_out_on - today);
  END LOOP;

  -- ---- documentos (horizonte minimo de 30 dias: vencimento pede antecedencia) ----
  FOR r IN SELECT d.title, d.expires_on, d.reminder_id FROM documents d
            WHERE d.user_id = p_user AND d.expires_on IS NOT NULL AND d.expires_on BETWEEN today AND today + greatest(v_dias, 30)
            ORDER BY d.expires_on, d.id LIMIT 10 LOOP
    j_docs := j_docs || jsonb_build_object('documento', r.title, 'vence', to_char(r.expires_on, 'DD/MM/YYYY'), 'dias', r.expires_on - today,
                                           'tem_lembrete', r.reminder_id IS NOT NULL);
  END LOOP;

  -- ---- lembretes ----
  FOR r IN SELECT title, due_at, person FROM reminders
            WHERE user_id = p_user AND kind = 'reminder' AND status = 'pending' AND due_at IS NOT NULL
              AND due_at < ((ate + 1)::timestamp AT TIME ZONE u.timezone)
            ORDER BY due_at, id LIMIT 15 LOOP
    j_lemb := j_lemb || jsonb_build_object('titulo', r.title, 'quando', to_char(r.due_at AT TIME ZONE u.timezone, 'DD/MM HH24:MI'),
                                           'atrasado', r.due_at < now(), 'pessoa', r.person);
  END LOOP;

  -- ---- texto compacto ----
  t := 'RETRATO (hoje ' || to_char(today, 'DD/MM/YYYY') || ', proximos ' || v_dias || ' dias)';
  t := t || E'\nDINHEIRO (mes ' || (j_din->>'mes') || '): gasto ' || f_brl(sp)
         || CASE WHEN u.fin_total_limit IS NOT NULL THEN ' de ' || f_brl(u.fin_total_limit) || ' (' || (j_din->>'limite_pct') || '%); pode gastar '
                 || f_brl(greatest(u.fin_total_limit - sp, 0)) || ', ' || f_brl((j_din->>'pode_gastar_por_dia')::numeric) || '/dia por ' || dias_rest || ' dia(s)'
                 ELSE '; sem limite geral definido' END
         || CASE WHEN u.fin_income IS NOT NULL THEN '; renda prevista ' || f_brl(u.fin_income) ELSE '' END || '.';
  SELECT string_agg((x->>'categoria') || ' ' || (x->>'pct') || '% (' || f_brl((x->>'gasto')::numeric) || ' de ' || f_brl((x->>'orcamento')::numeric) || ')', '; ')
    INTO sec FROM jsonb_array_elements(j_cats) x;
  IF sec IS NOT NULL THEN t := t || E'\nCategorias no teto (>=80%): ' || sec || '.'; END IF;
  SELECT string_agg((x->>'descricao') || ' ' || f_brl((x->>'valor')::numeric) || ' vence ' || (x->>'vence')
                    || CASE WHEN (x->>'atrasada')::boolean THEN ' (ATRASADA)' ELSE '' END, '; ')
    INTO sec FROM jsonb_array_elements(j_contas) x;
  IF sec IS NOT NULL THEN t := t || E'\nContas a pagar: ' || sec || '.'; END IF;
  SELECT string_agg((x->>'cartao') || ': fatura fechada ' || f_brl((x->>'fatura_fechada')::numeric) || ' vence ' || (x->>'vence')
                    || ', aberta ' || f_brl((x->>'fatura_aberta')::numeric)
                    || CASE WHEN x->>'limite_disponivel' IS NOT NULL THEN ', limite disponivel ' || f_brl((x->>'limite_disponivel')::numeric) ELSE '' END, '; ')
    INTO sec FROM jsonb_array_elements(j_fat) x;
  IF sec IS NOT NULL THEN t := t || E'\nCartoes: ' || sec || '.'; END IF;
  SELECT string_agg((x->>'meta') || ': falta ' || f_brl((x->>'falta')::numeric) || CASE WHEN x->>'prazo' IS NOT NULL THEN ' ate ' || (x->>'prazo') ELSE '' END, '; ')
    INTO sec FROM jsonb_array_elements(j_metas) x;
  IF sec IS NOT NULL THEN t := t || E'\nMetas: ' || sec || '.'; END IF;

  SELECT string_agg((x->>'tarefa') || ' [' || (x->>'projeto') || '] ' || (x->>'dias_atraso') || ' dia(s) de atraso', '; ')
    INTO sec FROM jsonb_array_elements(j_atras) x;
  IF sec IS NOT NULL THEN t := t || E'\nPROJETOS, tarefas atrasadas: ' || sec || '.'; END IF;
  SELECT string_agg((x->>'projeto') || ' prazo ' || (x->>'prazo') || ' (' || (x->>'tarefas_abertas') || ' tarefa(s) aberta(s))', '; ')
    INTO sec FROM jsonb_array_elements(j_prazos) x;
  IF sec IS NOT NULL THEN t := t || E'\nPROJETOS, prazos proximos: ' || sec || '.'; END IF;

  SELECT string_agg((x->>'item') || ' acaba em ' || (x->>'acaba_em'), '; ') INTO sec FROM jsonb_array_elements(j_est) x;
  IF sec IS NOT NULL THEN t := t || E'\nESTOQUE acabando: ' || sec || '.'; END IF;

  SELECT string_agg((x->>'documento') || ' vence ' || (x->>'vence')
                    || CASE WHEN (x->>'tem_lembrete')::boolean THEN '' ELSE ' (sem lembrete)' END, '; ')
    INTO sec FROM jsonb_array_elements(j_docs) x;
  IF sec IS NOT NULL THEN t := t || E'\nDOCUMENTOS vencendo: ' || sec || '.'; END IF;

  SELECT string_agg((x->>'titulo') || ' ' || (x->>'quando') || CASE WHEN (x->>'atrasado')::boolean THEN ' (atrasado)' ELSE '' END, '; ')
    INTO sec FROM jsonb_array_elements(j_lemb) x;
  IF sec IS NOT NULL THEN t := t || E'\nLEMBRETES: ' || sec || '.'; END IF;

  -- teto de tamanho: ~2 mil tokens (PRD RF-08)
  IF length(t) > 7000 THEN t := left(t, 7000) || '...'; END IF;

  RETURN jsonb_build_object('ok', true, 'hoje', today, 'dias', v_dias, 'fuso', u.timezone,
    'expediente', to_char(u.work_start, 'HH24:MI') || '-' || to_char(u.work_end, 'HH24:MI'),
    'google_conectado', u.calendar_key IS NOT NULL,
    'dinheiro', j_din, 'projetos', j_proj, 'estoque', j_est, 'documentos', j_docs, 'lembretes', j_lemb, 'text', t);
END $$;
