-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_claim_due()
-- Origem da definicao atual: 013_extras.sql (linha 335)
-- Definicoes (migracao:linha), da mais antiga a atual: 003_functions.sql:191, 005_doses.sql:71, 008_financas.sql:724, 013_extras.sql:335
CREATE OR REPLACE FUNCTION f_claim_due() RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE v jsonb; v_claimed jsonb; x record;
BEGIN
  PERFORM f_enqueue_doses();
  PERFORM f_fin_materialize();
  WITH claimed AS (
    UPDATE notifications n SET state = 'sent', sent_at = now()
    WHERE n.id IN (
      SELECT y.id FROM notifications y
      WHERE y.state = 'pending' AND y.fire_at <= now()
        AND (y.reminder_id IS NULL OR EXISTS (SELECT 1 FROM reminders r WHERE r.id = y.reminder_id AND r.status = 'pending'))
        AND (y.dose_id IS NULL OR EXISTS (SELECT 1 FROM supply_doses dd WHERE dd.id = y.dose_id AND dd.status = 'pending'))
      ORDER BY y.fire_at LIMIT 20 FOR UPDATE SKIP LOCKED)
    RETURNING n.*)
  SELECT coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb) INTO v_claimed FROM claimed;

  -- lembrete que se repete: agenda a proxima ocorrencia (e fecha a anterior)
  FOR x IN SELECT c.reminder_id FROM jsonb_populate_recordset(NULL::notifications, v_claimed) c WHERE c.type = 'reminder' AND c.reminder_id IS NOT NULL LOOP
    BEGIN
      PERFORM f_reminder_advance(x.reminder_id);
    EXCEPTION WHEN others THEN
      RAISE WARNING 'f_reminder_advance(%): %', x.reminder_id, SQLERRM;
    END;
  END LOOP;

  INSERT INTO notifications(user_id, reminder_id, type, fire_at)
  SELECT c.user_id, c.reminder_id, 'repeat', now() + interval '15 minutes'
  FROM jsonb_populate_recordset(NULL::notifications, v_claimed) c WHERE c.type = 'reminder';
  INSERT INTO notifications(user_id, supply_id, dose_id, type, fire_at)
  SELECT c.user_id, c.supply_id, c.dose_id, 'dose', now() + interval '10 minutes'
  FROM jsonb_populate_recordset(NULL::notifications, v_claimed) c JOIN users u ON u.id = c.user_id
  WHERE c.type = 'dose' AND (now() AT TIME ZONE u.timezone)::time < time '23:30';

  SELECT jsonb_agg(jsonb_build_object(
      'notification_id', c.id, 'type', c.type, 'chat_id', u.telegram_id, 'user_name', u.name,
      'reminder_id', c.reminder_id,
      'title', CASE WHEN r.card_id IS NOT NULL THEN f_card_alert_title(r.card_id, r.due_at) ELSE r.title END,
      'due', to_char(r.due_at AT TIME ZONE u.timezone, 'DD/MM HH24:MI'),
      'offset_minutes', c.offset_minutes, 'supply_id', c.supply_id, 'dose_id', c.dose_id, 'item', s.item,
      'days_left', (s.runs_out_on - CURRENT_DATE)))
  INTO v
  FROM jsonb_populate_recordset(NULL::notifications, v_claimed) c JOIN users u ON u.id = c.user_id
  LEFT JOIN reminders r ON r.id = c.reminder_id
  LEFT JOIN supplies_status s ON s.id = c.supply_id;
  RETURN v;
END $$;
