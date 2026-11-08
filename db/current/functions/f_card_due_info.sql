-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_card_due_info(p_card bigint)
-- Origem da definicao atual: 013_extras.sql (linha 192)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:192
CREATE OR REPLACE FUNCTION f_card_due_info(p_card bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE c fin_cards%ROWTYPE; today date; s date; pv date; amt numeric; dd date;
BEGIN
  SELECT * INTO c FROM fin_cards WHERE id = p_card AND active;
  IF NOT FOUND THEN RETURN NULL; END IF;
  today := f_fin_today(c.user_id);
  s := f_card_close_le(c.closing_day, today);
  pv := f_card_close_le(c.closing_day, s - 1);
  dd := f_card_due_gt(c.due_day, s);
  amt := f_card_sum(c.id, pv, s);
  IF amt > 0 AND dd - today BETWEEN 0 AND 3 THEN
    RETURN jsonb_build_object('name', c.name, 'amount', amt, 'due', to_char(dd, 'DD/MM'), 'days', dd - today);
  END IF;
  RETURN NULL;
END $$;
