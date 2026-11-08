-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_card_invoice_alert(p_card bigint)
-- Origem da definicao atual: 026_recibo_alertas.sql (linha 46)
-- Definicoes (migracao:linha), da mais antiga a atual: 026_recibo_alertas.sql:46
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
