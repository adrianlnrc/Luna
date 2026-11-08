-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_card_alert_title(p_card bigint, p_due_at timestamptz)
-- Origem da definicao atual: 013_extras.sql (linha 123)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:123
CREATE OR REPLACE FUNCTION f_card_alert_title(p_card bigint, p_due_at timestamptz) RETURNS text
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE c fin_cards%ROWTYPE; tz text; a date; dd date; cl date; pr date; amt numeric;
BEGIN
  SELECT * INTO c FROM fin_cards WHERE id = p_card;
  IF NOT FOUND THEN RETURN 'Fatura do cartão vence em breve'; END IF;
  SELECT timezone INTO tz FROM users WHERE id = c.user_id;
  a := (p_due_at AT TIME ZONE tz)::date;
  dd := f_card_due_gt(c.due_day, a + c.alert_days - 1);          -- vencimento a que este aviso se refere
  cl := f_card_close_le(c.closing_day, dd - 1);                   -- fechamento dessa fatura
  pr := f_card_close_le(c.closing_day, cl - 1);
  amt := f_card_sum(c.id, pr, cl);
  RETURN 'Fatura do cartão ' || c.name || ' vence dia ' || to_char(dd, 'DD/MM') || ' (' || f_days_text(dd - a) || ')' ||
    CASE WHEN amt > 0 THEN ': ' || f_brl(amt) || CASE WHEN cl > a THEN ' até agora (fecha dia ' || to_char(cl, 'DD/MM') || ')' ELSE '' END ELSE '' END;
END $$;
