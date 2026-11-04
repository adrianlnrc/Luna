-- 026: recibo com Desfazer + Editar (24 horas) e alertas de variacao (modulo M2 da onda 2)
-- Idempotente. Cada wrapper so e criado quando a funcao viva ainda nao foi embrulhada por esta migration
-- (o DO renomeia e cria o wrapper no mesmo bloco, para uma reexecucao nunca sobrescrever wrappers de outros modulos).
--   f_fin               -> f_fin_pre_m2               (alertas no lancamento novo, teclado fin_recibo)
--   f_fin_correct       -> f_fin_correct_pre_m2       (correcao de data)
--   f_callback          -> f_callback_pre_m2          (botao fedit, validade de 24h do fundo, alertas apos fok)
--   f_card_status_text  -> f_card_status_text_pre_m2  (fatura acima da media)
--   f_summary_data      -> f_summary_data_pre_m2      (fatura acima da media no extras_text)
--   f_menu              -> f_menu_pre_m2              (texto da area Dinheiro)
-- Funcoes novas: f_fin_expired, f_fin_alerts, f_card_inv_avg, f_card_invoice_alert, f_card_alerts_user, f_fin_edit_cb.

SET search_path TO agente, public;

-- ---------- helpers ----------
CREATE OR REPLACE FUNCTION agente.f_fin_expired(p_entry bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'agente', 'public'
AS $function$
  SELECT coalesce((SELECT created_at < now() - interval '24 hours' FROM fin_entries WHERE id = p_entry), false)
$function$;

-- media das ate 3 faturas FECHADAS que terminam em p_before (retorna {media, quantidade})
CREATE OR REPLACE FUNCTION agente.f_card_inv_avg(p_card bigint, p_before date)
 RETURNS numeric[]
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE c fin_cards%ROWTYPE; pe date := p_before; ps date; x numeric; tot numeric := 0; n integer := 0; k integer;
BEGIN
  SELECT * INTO c FROM fin_cards WHERE id = p_card;
  IF NOT FOUND THEN RETURN ARRAY[0, 0]::numeric[]; END IF;
  FOR k IN 1..3 LOOP
    ps := f_card_close_le(c.closing_day, pe - 1);
    x := f_card_sum(c.id, ps, pe);
    IF x > 0 THEN tot := tot + x; n := n + 1; END IF;
    pe := ps;
  END LOOP;
  IF n = 0 THEN RETURN ARRAY[0, 0]::numeric[]; END IF;
  RETURN ARRAY[round(tot / n, 2), n]::numeric[];
END $function$;

-- linhas de alerta de um cartao: fatura aberta e fatura fechada a pagar, 30% ou mais acima da media (minimo 2 faturas de base)
CREATE OR REPLACE FUNCTION agente.f_card_invoice_alert(p_card bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE c fin_cards%ROWTYPE; today date; s date; e date; pv date; cur numeric; closed numeric; a numeric[]; t text := ''; NL text := chr(10); due_closed date;
BEGIN
  SELECT * INTO c FROM fin_cards WHERE id = p_card;
  IF NOT FOUND THEN RETURN ''; END IF;
  today := f_fin_today(c.user_id);
  s := f_card_close_le(c.closing_day, today);
  e := f_card_close_gt(c.closing_day, today);
  pv := f_card_close_le(c.closing_day, s - 1);
  -- fatura aberta contra as 3 fechadas anteriores
  cur := f_card_sum(c.id, s, e);
  a := f_card_inv_avg(c.id, s);
  IF a[2] >= 2 AND a[1] > 0 AND cur >= a[1] * 1.3 THEN
    t := t || 'Atenção: a fatura aberta do cartão ' || c.name || ' (' || f_brl(cur) || ') já está ' || round((cur / a[1] - 1) * 100) ||
         '% acima da média das últimas faturas (' || f_brl(a[1]) || ').';
  END IF;
  -- ultima fatura fechada (ainda a pagar) contra as 3 anteriores a ela
  closed := f_card_sum(c.id, pv, s);
  due_closed := f_card_due_gt(c.due_day, s);
  IF closed > 0 AND today <= due_closed THEN
    a := f_card_inv_avg(c.id, pv);
    IF a[2] >= 2 AND a[1] > 0 AND closed >= a[1] * 1.3 THEN
      t := t || CASE WHEN t <> '' THEN NL ELSE '' END || 'Atenção: a última fatura do cartão ' || c.name || ' (' || f_brl(closed) || ') veio ' ||
           round((closed / a[1] - 1) * 100) || '% acima da média das faturas anteriores (' || f_brl(a[1]) || ').';
    END IF;
  END IF;
  RETURN t;
END $function$;

CREATE OR REPLACE FUNCTION agente.f_card_alerts_user(p_user bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE c record; t text := ''; x text; NL text := chr(10);
BEGIN
  FOR c IN SELECT id FROM fin_cards WHERE user_id = p_user AND active ORDER BY id LOOP
    x := f_card_invoice_alert(c.id);
    IF x <> '' THEN t := t || CASE WHEN t <> '' THEN NL ELSE '' END || x; END IF;
  END LOOP;
  RETURN t;
END $function$;

-- alertas de um lancamento recem criado: texto que comeca com quebra de linha (ou vazio). Nunca bloqueia.
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

-- botao Editar: instrucoes curtas; guarda no estado qual lancamento esta sendo editado
CREATE OR REPLACE FUNCTION agente.f_fin_edit_cb(p_user bigint, p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE e fin_entries%ROWTYPE; cat text;
BEGIN
  SELECT * INTO e FROM fin_entries WHERE id = p_id AND user_id = p_user;
  IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Esse lançamento já foi desfeito ou apagado.', 'kb', 'none'); END IF;
  IF f_fin_expired(p_id) THEN
    RETURN jsonb_build_object('text', 'Esse lançamento já passou de 24h; diga o que corrigir, por exemplo: corrige o gasto do mercado de ontem para 50', 'kb', 'none');
  END IF;
  SELECT name INTO cat FROM fin_categories WHERE id = e.category_id;
  RETURN jsonb_build_object('text',
    'Editar ' || e.description || ' ' || f_brl(e.amount) || ' (' || coalesce(cat, 'Outros') || ', ' || to_char(e.occurred_on, 'DD/MM') || E').\nDiga: "corrige para 50", "isso é Lazer" ou "foi dia 12".',
    'kb', 'none',
    'state', jsonb_build_object('kind', 'clarify', 'original',
      'Quero corrigir o lançamento "' || e.description || '" de ' || f_brl(e.amount) || ' do dia ' || to_char(e.occurred_on, 'DD/MM') || '.')::text);
END $function$;

-- ---------- wrappers (criados uma unica vez) ----------
DO $mig$
BEGIN
  -- f_fin: alertas e teclado novo
  IF to_regproc('agente.f_fin_pre_m2') IS NULL THEN
    ALTER FUNCTION agente.f_fin(bigint, jsonb) RENAME TO f_fin_pre_m2;
    EXECUTE $w$
CREATE FUNCTION agente.f_fin(p_user bigint, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE res jsonb := f_fin_pre_m2(p_user, p); rid bigint; al text := '';
BEGIN
  IF coalesce(p->>'action', '') = 'add' AND res->>'kb' = 'fin_undo' THEN
    rid := nullif(res->>'rid', '')::bigint;
    IF rid IS NOT NULL THEN
      BEGIN al := f_fin_alerts(p_user, rid); EXCEPTION WHEN others THEN al := ''; END;
    END IF;
    res := jsonb_set(res, '{text}', to_jsonb((res->>'text') || al));
    res := jsonb_set(res, '{kb}', '"fin_recibo"'::jsonb);
  END IF;
  RETURN res;
END $function$
$w$;
  END IF;

  -- f_fin_correct: data
  IF to_regproc('agente.f_fin_correct_pre_m2') IS NULL THEN
    ALTER FUNCTION agente.f_fin_correct(bigint, jsonb) RENAME TO f_fin_correct_pre_m2;
    EXECUTE $w$
CREATE FUNCTION agente.f_fin_correct(p_user bigint, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE d date := f_safe_date(p->>'date'); e fin_entries%ROWTYPE; v_title text := btrim(coalesce(p->>'title', '')); v_found boolean := false;
        r jsonb; v_amt numeric := round(nullif(p->>'amount', '')::numeric, 2); has_other boolean;
BEGIN
  IF d IS NULL THEN RETURN f_fin_correct_pre_m2(p_user, p); END IF;
  IF v_title <> '' THEN
    SELECT * INTO e FROM fin_entries WHERE user_id = p_user AND status <> 'draft' AND norm_desc LIKE '%' || f_norm(v_title) || '%' ORDER BY id DESC LIMIT 1;
    v_found := FOUND;
  END IF;
  IF NOT v_found THEN
    SELECT * INTO e FROM fin_entries WHERE user_id = p_user AND status <> 'draft' ORDER BY id DESC LIMIT 1;
    IF NOT FOUND THEN RETURN f_fin_correct_pre_m2(p_user, p); END IF;
  END IF;
  IF e.series_id IS NOT NULL THEN
    RETURN jsonb_build_object('text', 'Esse lançamento é parcelado; para mudar a data, apague com "desfaz" e lance de novo com a data certa.', 'kb', 'none');
  END IF;
  IF e.status = 'pending' THEN
    RETURN jsonb_build_object('text', 'Essa conta ainda está a pagar; o vencimento tem aviso próprio. Apague e lance de novo com a data certa, ou diga "já paguei" quando pagar.', 'kb', 'none');
  END IF;
  UPDATE fin_entries SET occurred_on = d, paid_on = CASE WHEN status = 'paid' THEN d ELSE paid_on END WHERE id = e.id;
  has_other := (v_amt IS NOT NULL AND v_amt > 0) OR btrim(coalesce(p->>'category', '')) <> '';
  IF has_other THEN
    r := f_fin_correct_pre_m2(p_user, p - 'date');
    RETURN jsonb_set(r, '{text}', to_jsonb(rtrim(r->>'text') || ' Data: ' || to_char(d, 'DD/MM') || '.'));
  END IF;
  RETURN jsonb_build_object('text', 'Corrigido: ' || e.description || ' agora com data ' || to_char(d, 'DD/MM') || '.', 'kb', 'none');
END $function$
$w$;
  END IF;

  -- f_callback: fedit, validade de 24h do fundo, reinicio do relogio e alertas na confirmacao da foto
  IF to_regproc('agente.f_callback_pre_m2') IS NULL THEN
    ALTER FUNCTION agente.f_callback(bigint, text) RENAME TO f_callback_pre_m2;
    EXECUTE $w$
CREATE FUNCTION agente.f_callback(p_user bigint, p_data text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE a text := split_part(p_data, ':', 1); v_id bigint := CASE WHEN split_part(p_data, ':', 2) ~ '^[0-9]+$' THEN split_part(p_data, ':', 2)::bigint END; res jsonb; al text := '';
BEGIN
  IF a = 'fedit' THEN
    RETURN f_fin_edit_cb(p_user, coalesce(v_id, 0));
  END IF;
  IF a = 'fundo' AND v_id IS NOT NULL AND EXISTS (SELECT 1 FROM fin_entries WHERE id = v_id AND user_id = p_user) AND f_fin_expired(v_id) THEN
    RETURN jsonb_build_object('text', 'Esse lançamento já passou de 24h; diga o que corrigir, por exemplo: corrige o gasto do mercado de ontem para 50', 'kb', 'none');
  END IF;
  res := f_callback_pre_m2(p_user, p_data);
  IF a = 'fok' AND v_id IS NOT NULL AND res->>'kb' = 'fin_undo' THEN
    -- a foto confirmada passa a valer como lancamento agora: o relogio das 24h comeca aqui
    UPDATE fin_entries SET created_at = now() WHERE id = v_id AND user_id = p_user AND status IN ('paid', 'pending');
    BEGIN al := f_fin_alerts(p_user, v_id); EXCEPTION WHEN others THEN al := ''; END;
    res := jsonb_set(res, '{text}', to_jsonb((res->>'text') || al));
    res := jsonb_set(res, '{kb}', '"fin_recibo"'::jsonb);
  END IF;
  RETURN res;
END $function$
$w$;
  END IF;

  -- status do cartao: alerta de fatura
  IF to_regproc('agente.f_card_status_text_pre_m2') IS NULL THEN
    ALTER FUNCTION agente.f_card_status_text(bigint) RENAME TO f_card_status_text_pre_m2;
    EXECUTE $w$
CREATE FUNCTION agente.f_card_status_text(p_card bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE t text := f_card_status_text_pre_m2(p_card); al text := '';
BEGIN
  BEGIN al := f_card_invoice_alert(p_card); EXCEPTION WHEN others THEN al := ''; END;
  IF al <> '' THEN t := t || chr(10) || al; END IF;
  RETURN t;
END $function$
$w$;
  END IF;

  -- resumo: alerta de fatura no extras_text
  IF to_regproc('agente.f_summary_data_pre_m2') IS NULL THEN
    ALTER FUNCTION agente.f_summary_data(bigint) RENAME TO f_summary_data_pre_m2;
    EXECUTE $w$
CREATE FUNCTION agente.f_summary_data(p_user bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE v jsonb := f_summary_data_pre_m2(p_user); al text := ''; ex text;
BEGIN
  BEGIN al := f_card_alerts_user(p_user); EXCEPTION WHEN others THEN al := ''; END;
  IF al <> '' THEN
    ex := coalesce(v->>'extras_text', '');
    v := v || jsonb_build_object('extras_text', al || CASE WHEN ex <> '' THEN chr(10) || chr(10) || ex ELSE '' END);
  END IF;
  RETURN v;
END $function$
$w$;
  END IF;

  -- menu: texto da area Dinheiro
  IF to_regproc('agente.f_menu_pre_m2') IS NULL THEN
    ALTER FUNCTION agente.f_menu(bigint, text) RENAME TO f_menu_pre_m2;
    EXECUTE $w$
CREATE FUNCTION agente.f_menu(p_user bigint, p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE r jsonb := f_menu_pre_m2(p_user, p_key); t text := r->>'text'; x text;
BEGIN
  IF lower(coalesce(btrim(p_key), '')) = 'dinheiro' THEN
    t := replace(t, 'O botão Desfazer apaga o último lançamento.',
      E'Cada lançamento vem com Desfazer e Editar, que valem por 24 horas. Depois disso, ou para outro lançamento, diga: "corrige para 50", "isso é Lazer" ou "foi dia 12".');
    IF position('Editar' in t) = 0 THEN
      t := t || E'\n\nCada lançamento vem com Desfazer e Editar, que valem por 24 horas. Para corrigir: "corrige para 50", "isso é Lazer" ou "foi dia 12".';
    END IF;
    x := E'\n\nAvisos automáticos (sem bloquear nada): assinatura que mudou de valor ("Spotify subiu de R$ 21,90 para R$ 27,90"), cobrança que parece repetida e fatura do cartão 30% ou mais acima da média.';
    IF position(E'\n\nDica:' in t) > 0 THEN
      t := replace(t, E'\n\nDica:', x || E'\n\nDica:');
    ELSE
      t := t || x;
    END IF;
  END IF;
  RETURN jsonb_set(r, '{text}', to_jsonb(t));
END $function$
$w$;
  END IF;
END $mig$;
