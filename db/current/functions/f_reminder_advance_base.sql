-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_reminder_advance_base(p_rid bigint)
-- Origem da definicao atual: 013_extras.sql (linha 238)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:238
-- Renomeada de f_reminder_advance para f_reminder_advance_base em 028_custo_ia_anuais.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_reminder_advance_base).
CREATE OR REPLACE FUNCTION f_reminder_advance(p_rid bigint) RETURNS bigint
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE r reminders%ROWTYPE; root reminders%ROWTYPE; c fin_cards%ROWTYPE; tz text; v_chain bigint; v_loc timestamp; v_nxt timestamptz;
        v_left integer; v_lead integer; v_new bigint; v_anchor integer; m date; n integer := 0; v_title text;
BEGIN
  SELECT * INTO r FROM reminders WHERE id = p_rid;
  IF NOT FOUND OR r.repeat_rule IS NULL OR r.status <> 'pending' THEN RETURN NULL; END IF;
  v_chain := coalesce(r.repeat_of, r.id);
  -- a ocorrencia anterior (ainda aberta) fecha quando a nova dispara: nao acumula repeticoes
  UPDATE notifications SET state = 'cancelled'
   WHERE state = 'pending' AND reminder_id IN (SELECT id FROM reminders WHERE coalesce(repeat_of, id) = v_chain AND id < r.id AND user_id = r.user_id);
  UPDATE reminders SET status = 'done' WHERE coalesce(repeat_of, id) = v_chain AND id < r.id AND user_id = r.user_id AND status = 'pending';
  -- ja existe uma proxima (ex.: o lembrete foi adiado e disparou de novo)
  IF EXISTS (SELECT 1 FROM reminders WHERE coalesce(repeat_of, id) = v_chain AND id > r.id AND user_id = r.user_id AND status = 'pending') THEN RETURN NULL; END IF;
  SELECT timezone INTO tz FROM users WHERE id = r.user_id;
  IF r.card_id IS NOT NULL THEN
    SELECT * INTO c FROM fin_cards WHERE id = r.card_id AND active;
    IF NOT FOUND THEN RETURN NULL; END IF;
    v_nxt := f_card_next_alert(c.id, r.due_at);
    v_title := 'Fatura do cartão ' || c.name || ' vence dia ' || c.due_day;
    v_left := NULL;
  ELSE
    SELECT * INTO root FROM reminders WHERE id = v_chain;
    v_anchor := extract(day FROM (coalesce(root.due_at, r.due_at) AT TIME ZONE tz))::int;
    v_loc := r.due_at AT TIME ZONE tz;
    v_left := r.repeat_left;
    LOOP
      n := n + 1;
      IF n > 800 THEN RETURN NULL; END IF;
      IF v_left IS NOT NULL AND v_left <= 0 THEN RETURN NULL; END IF;
      IF r.repeat_rule = 'daily' THEN v_loc := v_loc + interval '1 day';
      ELSIF r.repeat_rule = 'weekly' THEN v_loc := v_loc + interval '7 days';
      ELSE
        m := (date_trunc('month', v_loc) + interval '1 month')::date;
        v_loc := (m + (least(v_anchor, extract(day FROM (m + interval '1 month - 1 day'))::int) - 1)) + v_loc::time;
      END IF;
      v_nxt := v_loc AT TIME ZONE tz;
      IF v_left IS NOT NULL THEN v_left := v_left - 1; END IF;
      EXIT WHEN v_nxt > now();      -- se o robo ficou fora do ar, pula as ocorrencias que ja passaram
    END LOOP;
    IF r.repeat_until IS NOT NULL AND v_loc::date > r.repeat_until THEN RETURN NULL; END IF;
    v_title := r.title;
  END IF;
  INSERT INTO reminders (user_id, kind, title, due_at, status, shared_group, source, repeat_rule, repeat_until, repeat_left, repeat_of, card_id)
  VALUES (r.user_id, 'reminder', v_title, v_nxt, 'pending', r.shared_group, r.source, r.repeat_rule, r.repeat_until, v_left, v_chain, r.card_id)
  RETURNING id INTO v_new;
  INSERT INTO notifications (user_id, reminder_id, type, fire_at) VALUES (r.user_id, v_new, 'reminder', v_nxt);
  SELECT offset_minutes INTO v_lead FROM notifications WHERE reminder_id = r.id AND type = 'pre_alert' ORDER BY id LIMIT 1;
  IF v_lead IS NOT NULL AND v_lead > 0 AND v_nxt - make_interval(mins => v_lead) > now() THEN
    INSERT INTO notifications (user_id, reminder_id, type, fire_at, offset_minutes)
    VALUES (r.user_id, v_new, 'pre_alert', v_nxt - make_interval(mins => v_lead), v_lead);
  END IF;
  RETURN v_new;
END $$;
