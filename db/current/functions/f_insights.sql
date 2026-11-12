-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_insights(p_user bigint, p_events jsonb)
-- Origem da definicao atual: 039_insights.sql (linha 44)
-- Definicoes (migracao:linha), da mais antiga a atual: 039_insights.sql:44
CREATE OR REPLACE FUNCTION f_insights(p_user bigint, p_events jsonb DEFAULT '[]') RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE
  u users%ROWTYPE; today date; ps date; pe date; sp numeric; r record; r2 record;
  ev jsonb := CASE WHEN jsonb_typeof(p_events) = 'array' THEN p_events ELSE '[]'::jsonb END;
  out jsonb := '[]'; off text[]; sab date; n int; v_pct numeric; v_tit text; inc numeric; saldo numeric;
  s date; pv date; dd date; fechada numeric; lista text; v_norm text;
BEGIN
  SELECT * INTO u FROM users WHERE id = p_user;
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;
  today := f_fin_today(p_user);
  SELECT p_start, p_end INTO ps, pe FROM f_fin_period(p_user, 0);
  SELECT coalesce(regras_silenciadas, '{}') || coalesce(regras_desligadas, '{}') INTO off FROM insight_prefs WHERE user_id = p_user;
  off := coalesce(off, '{}');

  -- 1) lazer no fim de semana x orcamento de lazer
  IF NOT 'lazer_fim_de_semana' = ANY (off) THEN
    sab := today + ((6 - extract(dow FROM today)::int + 7) % 7);
    SELECT count(*), string_agg(x->>'title', ', ') INTO n, v_tit FROM jsonb_array_elements(ev) x
     WHERE (f_ag_ts(x->>'start') AT TIME ZONE u.timezone)::date IN (sab, sab + 1)
       AND f_norm(coalesce(x->>'title', '')) ~ '(jantar|almoco|festa|bar |bar$|cinema|show|churrasco|restaurante|aniversario|viagem|passeio|happy|balada|teatro|rodizio|pizza)';
    SELECT round(f_fin_spent(p_user, c.id, ps, pe) / c.budget * 100) INTO v_pct FROM fin_categories c
     WHERE c.user_id = p_user AND c.kind = 'expense' AND f_norm(c.name) = 'lazer' AND coalesce(c.budget, 0) > 0 LIMIT 1;
    IF n >= 2 AND coalesce(v_pct, 0) >= 80 THEN
      out := out || jsonb_build_object('chave', 'lazer:' || sab, 'regra', 'lazer_fim_de_semana', 'prioridade', 'normal',
        'texto', 'Seu fim de semana tem ' || n || ' programas (' || v_tit || ') e o orçamento de Lazer já está em ' || v_pct || '%.',
        'acao', NULL);
    END IF;
  END IF;

  -- 2) fatura fechada vencendo e o saldo do mes nao cobre
  IF NOT 'fatura_sem_saldo' = ANY (off) THEN
    SELECT coalesce(sum(amount), 0) INTO inc FROM fin_entries
     WHERE user_id = p_user AND kind = 'income' AND status = 'paid' AND occurred_on BETWEEN ps AND pe;
    inc := greatest(inc, coalesce(u.fin_income, 0));
    IF inc > 0 THEN
      sp := f_fin_total_spent(p_user, ps, pe);
      saldo := inc - sp;
      FOR r IN SELECT * FROM fin_cards WHERE user_id = p_user AND active LOOP
        s := f_card_close_le(r.closing_day, today);
        pv := f_card_close_le(r.closing_day, s - 1);
        dd := f_card_due_gt(r.due_day, s);
        fechada := f_card_sum(r.id, pv, s);
        IF fechada > 0 AND dd - today BETWEEN 0 AND 7 AND fechada > saldo THEN
          out := out || jsonb_build_object('chave', 'fatura:' || r.id || ':' || dd, 'regra', 'fatura_sem_saldo',
            'prioridade', CASE WHEN dd - today <= 1 THEN 'alta' ELSE 'normal' END,
            'texto', 'A fatura do ' || r.name || ' (' || f_brl(fechada) || ') vence em ' || to_char(dd, 'DD/MM')
                     || ' e o que sobrou do mês (' || f_brl(saldo) || ') não cobre.',
            'acao', NULL);
        END IF;
      END LOOP;
    END IF;
  END IF;

  -- 3) documento vencendo sem lembrete nem tarefa
  IF NOT 'documento_sem_lembrete' = ANY (off) THEN
    FOR r IN SELECT d.id, d.title, d.expires_on FROM documents d
              WHERE d.user_id = p_user AND d.expires_on BETWEEN today AND today + 30 AND d.reminder_id IS NULL
              ORDER BY d.expires_on LIMIT 5 LOOP
      v_norm := f_norm(r.title);
      CONTINUE WHEN EXISTS (SELECT 1 FROM reminders x WHERE x.user_id = p_user AND x.status = 'pending' AND length(v_norm) >= 4
                             AND position(v_norm IN f_norm(x.title)) > 0)
                 OR EXISTS (SELECT 1 FROM project_tasks x WHERE x.user_id = p_user AND NOT x.done AND length(v_norm) >= 4
                             AND position(v_norm IN x.norm_title) > 0);
      out := out || jsonb_build_object('chave', 'doc:' || r.id || ':' || r.expires_on, 'regra', 'documento_sem_lembrete',
        'prioridade', CASE WHEN r.expires_on - today <= 1 THEN 'alta' ELSE 'normal' END,
        'texto', '"' || r.title || '" vence em ' || to_char(r.expires_on, 'DD/MM') || ' (' || f_days_text(r.expires_on - today)
                 || ') e não há lembrete para isso.',
        'acao', jsonb_build_object('rotulo', 'Criar lembrete', 'ferramenta', 'lembretes', 'acao', 'criar',
          'args', jsonb_build_object('titulo', 'Renovar ' || r.title,
                                     'data', to_char(greatest(r.expires_on - 7, today + 1), 'YYYY-MM-DD'), 'hora', '09:00')));
    END LOOP;
  END IF;

  -- 4) item continuo acabando e fora da lista de compras
  IF NOT 'estoque_fora_da_lista' = ANY (off) THEN
    FOR r IN SELECT id, item, runs_out_on FROM supplies_status
              WHERE user_id = p_user AND status = 'active' AND runs_out_on IS NOT NULL AND runs_out_on BETWEEN today AND today + 7
              ORDER BY runs_out_on LIMIT 5 LOOP
      v_norm := f_norm(r.item);
      CONTINUE WHEN EXISTS (SELECT 1 FROM list_items li WHERE li.user_id = p_user AND NOT li.done
                             AND (position(v_norm IN li.name_norm) > 0 OR position(li.name_norm IN v_norm) > 0));
      SELECT l.name INTO lista FROM lists l WHERE l.user_id = p_user AND l.name_norm ~ '(mercado|compras|farmacia)'
       ORDER BY (l.name_norm ~ 'farmacia') DESC, l.id LIMIT 1;
      out := out || jsonb_build_object('chave', 'estoque:' || r.id || ':' || r.runs_out_on, 'regra', 'estoque_fora_da_lista',
        'prioridade', CASE WHEN r.runs_out_on - today <= 1 THEN 'alta' ELSE 'normal' END,
        'texto', initcap(left(r.item, 1)) || substr(r.item, 2) || ' acaba em ' || to_char(r.runs_out_on, 'DD/MM')
                 || ' e não está em nenhuma lista de compras.',
        'acao', jsonb_build_object('rotulo', 'Pôr na lista', 'ferramenta', 'listas_notas', 'acao', 'lista_adicionar',
          'args', jsonb_build_object('lista', coalesce(lista, 'compras'), 'itens', jsonb_build_array(r.item))));
    END LOOP;
  END IF;

  -- 5) prazo de projeto chegando com tarefas abertas
  IF NOT 'prazo_de_projeto' = ANY (off) THEN
    FOR r IN SELECT p.id, p.name, p.due_date, (SELECT count(*) FROM project_tasks x WHERE x.project_id = p.id AND NOT x.done) AS abertas
               FROM projects p WHERE p.user_id = p_user AND p.due_date BETWEEN today AND today + 7 ORDER BY p.due_date LIMIT 5 LOOP
      CONTINUE WHEN r.abertas = 0;
      out := out || jsonb_build_object('chave', 'proj:' || r.id || ':' || r.due_date, 'regra', 'prazo_de_projeto',
        'prioridade', CASE WHEN r.due_date - today <= 1 THEN 'alta' ELSE 'normal' END,
        'texto', 'O projeto ' || r.name || ' vence em ' || to_char(r.due_date, 'DD/MM') || ' (' || f_days_text(r.due_date - today)
                 || ') e ainda tem ' || r.abertas || ' tarefa(s) aberta(s).',
        'acao', NULL);
    END LOOP;
  END IF;

  -- 6) conflito de horario nos proximos 7 dias
  IF NOT 'conflito_de_agenda' = ANY (off) THEN
    FOR r IN
      SELECT a->>'id' AS ida, b->>'id' AS idb, a->>'title' AS ta, b->>'title' AS tb, f_ag_ts(a->>'start') AS sa
        FROM jsonb_array_elements(ev) a, jsonb_array_elements(ev) b
       WHERE (a->>'id') < (b->>'id')
         AND coalesce(a->>'all_day', 'false') <> 'true' AND coalesce(b->>'all_day', 'false') <> 'true'
         AND f_ag_ts(a->>'start') < f_ag_ts(b->>'end') AND f_ag_ts(b->>'start') < f_ag_ts(a->>'end')
         AND f_ag_ts(a->>'start') >= now() - interval '1 hour'
         AND (f_ag_ts(a->>'start') AT TIME ZONE u.timezone)::date <= today + 7
       ORDER BY f_ag_ts(a->>'start') LIMIT 3 LOOP
      out := out || jsonb_build_object('chave', 'conf:' || r.ida || ':' || r.idb, 'regra', 'conflito_de_agenda',
        'prioridade', CASE WHEN (r.sa AT TIME ZONE u.timezone)::date = today THEN 'alta' ELSE 'normal' END,
        'texto', '"' || r.ta || '" e "' || r.tb || '" estão no mesmo horário em ' || f_ag_fmt(r.sa, u.timezone) || '.',
        'acao', NULL);
    END LOOP;
  END IF;

  -- 7) limite geral do mes estourado
  IF NOT 'limite_estourado' = ANY (off) AND coalesce(u.fin_total_limit, 0) > 0 THEN
    sp := f_fin_total_spent(p_user, ps, pe);
    IF sp >= u.fin_total_limit THEN
      out := out || jsonb_build_object('chave', 'limite:' || ps, 'regra', 'limite_estourado', 'prioridade', 'alta',
        'texto', 'Você passou do limite do mês: gastou ' || f_brl(sp) || ' de ' || f_brl(u.fin_total_limit) || '.', 'acao', NULL);
    END IF;
  END IF;

  -- a mesma chave nao volta em 30 dias; prioridade alta primeiro
  RETURN coalesce((
    SELECT jsonb_agg(x ORDER BY (x->>'prioridade' = 'alta') DESC, x->>'chave')
      FROM jsonb_array_elements(out) x
     WHERE NOT EXISTS (SELECT 1 FROM insights_log l WHERE l.user_id = p_user AND l.chave = x->>'chave'
                                                      AND l.enviado_em > now() - interval '30 days')), '[]'::jsonb);
END $$;
