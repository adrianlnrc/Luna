-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_card_next_alert(p_card bigint, p_after timestamptz)
-- Origem da definicao atual: 013_extras.sql (linha 106)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:106
CREATE OR REPLACE FUNCTION f_card_next_alert(p_card bigint, p_after timestamptz DEFAULT now()) RETURNS timestamptz
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE c fin_cards%ROWTYPE; tz text; dd date; ts timestamptz; n integer := 0; lim timestamptz := greatest(coalesce(p_after, now()), now());
BEGIN
  SELECT * INTO c FROM fin_cards WHERE id = p_card;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT timezone INTO tz FROM users WHERE id = c.user_id;
  dd := f_card_due_gt(c.due_day, (now() AT TIME ZONE tz)::date - 1);
  LOOP
    ts := ((dd - c.alert_days) + time '09:00') AT TIME ZONE tz;
    EXIT WHEN ts > lim OR n > 6;
    dd := f_card_due_gt(c.due_day, dd); n := n + 1;
  END LOOP;
  RETURN ts;
END $$;
