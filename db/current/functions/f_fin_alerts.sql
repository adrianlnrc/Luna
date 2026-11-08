-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_alerts(p_user bigint, p_entry bigint)
-- Origem da definicao atual: 026_recibo_alertas.sql (linha 96)
-- Definicoes (migracao:linha), da mais antiga a atual: 026_recibo_alertas.sql:96
CREATE OR REPLACE FUNCTION agente.f_fin_alerts(p_user bigint, p_entry bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE e fin_entries%ROWTYPE; d fin_entries%ROWTYPE; prev fin_entries%ROWTYPE; prev2 fin_entries%ROWTYPE; t text := ''; NL text := chr(10);
        today date; cat text; rec boolean; wh text;
BEGIN
  SELECT * INTO e FROM fin_entries WHERE id = p_entry AND user_id = p_user;
  IF NOT FOUND OR e.kind <> 'expense' OR e.status NOT IN ('paid', 'pending') THEN RETURN ''; END IF;
  today := f_fin_today(p_user);
  -- (b) cobranca possivelmente duplicada: mesmo titulo e valor nas ultimas 48 horas (lancamentos anteriores, nao os da mesma mensagem)
  SELECT * INTO d FROM fin_entries
   WHERE user_id = p_user AND id <> e.id AND kind = 'expense' AND status IN ('paid', 'pending')
     AND norm_desc = e.norm_desc AND amount = e.amount
     AND created_at < e.created_at AND created_at > e.created_at - interval '48 hours'
     AND (series_id IS NULL OR e.series_id IS NULL OR series_id <> e.series_id)
   ORDER BY id DESC LIMIT 1;
  IF FOUND THEN
    wh := CASE WHEN d.occurred_on = today THEN 'hoje' WHEN d.occurred_on = today - 1 THEN 'ontem' ELSE 'em ' || to_char(d.occurred_on, 'DD/MM') END;
    t := t || NL || 'Parece repetido: já lancei ' || f_brl(d.amount) || ' em ' || d.description || ' ' || wh || '. Toque em Desfazer se foi sem querer.';
  END IF;
  -- (a) assinatura ou gasto recorrente com valor diferente do mes anterior (mesmo titulo, 20 a 50 dias antes)
  IF e.installments IS NULL THEN
    SELECT * INTO prev FROM fin_entries
     WHERE user_id = p_user AND id <> e.id AND kind = 'expense' AND status IN ('paid', 'pending') AND installments IS NULL
       AND norm_desc = e.norm_desc AND occurred_on BETWEEN e.occurred_on - 50 AND e.occurred_on - 20
     ORDER BY occurred_on DESC, id DESC LIMIT 1;
    IF FOUND AND prev.amount <> e.amount THEN
      SELECT name INTO cat FROM fin_categories WHERE id = e.category_id;
      rec := prev.recurring_id IS NOT NULL OR e.recurring_id IS NOT NULL OR lower(coalesce(cat, '')) LIKE 'assinatura%';
      IF NOT rec THEN
        -- preco estavel nos dois meses anteriores = comportamento de assinatura
        SELECT * INTO prev2 FROM fin_entries
         WHERE user_id = p_user AND id <> prev.id AND kind = 'expense' AND status IN ('paid', 'pending') AND installments IS NULL
           AND norm_desc = e.norm_desc AND amount = prev.amount AND occurred_on BETWEEN prev.occurred_on - 50 AND prev.occurred_on - 20
         LIMIT 1;
        rec := FOUND;
      END IF;
      IF rec THEN
        t := t || NL || e.description || CASE WHEN e.amount > prev.amount THEN ' subiu de ' ELSE ' baixou de ' END || f_brl(prev.amount) || ' para ' || f_brl(e.amount) || '.';
      END IF;
    END IF;
  END IF;
  RETURN t;
EXCEPTION WHEN others THEN
  RAISE WARNING 'f_fin_alerts: %', SQLERRM;
  RETURN '';
END $function$;
