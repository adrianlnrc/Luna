-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_card_status_text_pre_m2(p_card bigint)
-- Origem da definicao atual: 013_extras.sql (linha 157)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:157
-- Renomeada de f_card_status_text para f_card_status_text_pre_m2 em 026_recibo_alertas.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_card_status_text_pre_m2).
CREATE OR REPLACE FUNCTION f_card_status_text(p_card bigint) RETURNS text
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE c fin_cards%ROWTYPE; today date; s date; e date; pv date; open_amt numeric; closed_amt numeric; due_closed date; due_open date;
        fut numeric; avail numeric; unpaid boolean; t text;
BEGIN
  SELECT * INTO c FROM fin_cards WHERE id = p_card;
  IF NOT FOUND THEN RETURN 'Não achei esse cartão.'; END IF;
  today := f_fin_today(c.user_id);
  s := f_card_close_le(c.closing_day, today);        -- fechamento mais recente (inicio da fatura aberta)
  e := f_card_close_gt(c.closing_day, today);        -- proximo fechamento
  pv := f_card_close_le(c.closing_day, s - 1);       -- fechamento anterior
  open_amt := f_card_sum(c.id, s, e);
  closed_amt := f_card_sum(c.id, pv, s);
  due_closed := f_card_due_gt(c.due_day, s);
  due_open := f_card_due_gt(c.due_day, e);
  unpaid := closed_amt > 0 AND today <= due_closed;
  fut := f_card_sum(c.id, e, date '9999-01-01');
  t := 'Cartão ' || c.name || ' (fecha dia ' || c.closing_day || ', vence dia ' || c.due_day || '):' ||
       E'\n- Fatura aberta: ' || f_brl(open_amt) || ' (fecha ' || to_char(e, 'DD/MM') || ', ' || f_days_text(e - today) || '; vence ' || to_char(due_open, 'DD/MM') || ')' ||
       E'\n- Última fatura (fechou ' || to_char(s, 'DD/MM') || '): ' ||
         CASE WHEN closed_amt = 0 THEN 'sem lançamentos'
              WHEN unpaid THEN f_brl(closed_amt) || ', vence ' || to_char(due_closed, 'DD/MM') || ' (' || f_days_text(due_closed - today) || ')'
              ELSE f_brl(closed_amt) || ', venceu ' || to_char(due_closed, 'DD/MM') || ' (considero paga)' END;
  IF c.card_limit IS NOT NULL THEN
    avail := c.card_limit - open_amt - CASE WHEN unpaid THEN closed_amt ELSE 0 END;
    t := t || E'\n- Limite ' || f_brl(c.card_limit) || ': disponível ' || CASE WHEN avail < 0 THEN '-' ELSE '' END || f_brl(abs(avail)) ||
         ' (limite menos fatura aberta' || CASE WHEN unpaid THEN ' e fatura fechada a pagar' ELSE '' END || ')';
  ELSE
    t := t || E'\n- Sem limite cadastrado (diga "limite do cartão ' || c.name || ' é 5000").';
  END IF;
  IF fut > 0 THEN t := t || E'\n- Parcelas e lançamentos de meses seguintes: ' || f_brl(fut); END IF;
  RETURN t;
END $$;
