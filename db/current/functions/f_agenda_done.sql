-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agenda_done(p_user bigint, p_pid bigint, p_result jsonb)
-- Origem da definicao atual: 012_agenda.sql (linha 433)
-- Definicoes (migracao:linha), da mais antiga a atual: 012_agenda.sql:433
CREATE OR REPLACE FUNCTION f_agenda_done(p_user bigint, p_pid bigint, p_result jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  pd agenda_pending%ROWTYPE; tz text; ok boolean; v_ids bigint[]; rid bigint; offs int[]; o int; v_kind text; t text; n_av int := 0;
  scope text; req jsonb; conf text; err text; rec text;
BEGIN
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  SELECT * INTO pd FROM agenda_pending WHERE id = p_pid AND user_id = p_user;
  IF NOT FOUND OR pd.state <> 'open' THEN
    RETURN jsonb_build_object('text', 'Essa ação já foi resolvida.', 'kb', 'none', 'rid', 0);
  END IF;
  ok := coalesce(p_result->>'ok', '') = 'true';
  IF NOT ok THEN
    err := CASE WHEN jsonb_typeof(p_result->'error') = 'string' THEN left(p_result->>'error', 140) ELSE NULL END;
    UPDATE agenda_pending SET payload = payload - 'dispatched_at' WHERE id = pd.id;
    RETURN jsonb_build_object('text', 'Não consegui fazer isso no Google Agenda' || CASE WHEN err IS NOT NULL THEN ' (' || err || ')' ELSE '' END
                              || '. Nada foi alterado; pode tentar de novo.', 'kb', 'none', 'rid', 0);
  END IF;
  rec := coalesce(pd.payload->>'recurring_id', '');
  scope := coalesce(pd.payload->>'scope', '');

  IF pd.kind = 'create' THEN
    IF coalesce(p_result->>'conflict', '') = 'true' THEN
      UPDATE agenda_pending SET payload = (payload - 'dispatched_at') || jsonb_build_object('conflicts', coalesce(p_result->'conflicts', '[]'::jsonb), 'force', false) WHERE id = pd.id;
      SELECT string_agg((c->>'title') || ' (' || to_char(f_ag_ts(c->>'start') AT TIME ZONE tz, 'HH24:MI') || '–' || to_char(f_ag_ts(c->>'end') AT TIME ZONE tz, 'HH24:MI') || ')', ', ')
        INTO conf FROM jsonb_array_elements(coalesce(p_result->'conflicts', '[]'::jsonb)) c;
      RETURN jsonb_build_object('text', 'Atenção: "' || coalesce(pd.payload->>'summary', pd.title) || '" (' || f_ag_fmt(coalesce(f_ag_ts(pd.payload->>'start'), pd.new_start), tz)
                                || ') conflita com ' || coalesce(conf, 'outro compromisso') || '. Marco mesmo assim?', 'kb', 'ag_conflict', 'rid', pd.id);
    END IF;
    UPDATE agenda_pending SET state = 'done' WHERE id = pd.id;
    req := jsonb_build_object('title', coalesce(pd.payload->>'summary', pd.title), 'due_iso', coalesce(pd.payload->>'start', f_ag_iso(pd.new_start)),
      'end_iso', coalesce(pd.payload->>'end', f_ag_iso(pd.new_end)), 'location', coalesce(pd.payload->>'location', ''),
      'lead_str', coalesce(pd.payload->>'lead_str', ''), 'source', coalesce(pd.payload->>'source', 'text'), 'calendar_key', pd.calendar_key,
      'repeat_freq', coalesce(pd.payload->>'repeat_freq', ''), 'repeat_until', coalesce(pd.payload->>'repeat_until', ''),
      'repeat_count', coalesce(pd.payload->>'repeat_count', ''), 'attendees', coalesce(pd.payload->>'attendees', ''),
      'meet', coalesce(pd.payload->>'meet', 'false'), 'promote_reminder_id', pd.payload->'promote_reminder_id');
    RETURN f_agenda_after_create(p_user, req, p_result || jsonb_build_object('conflict', false));

  ELSIF pd.kind = 'move' THEN
    v_ids := f_ag_links(p_user, pd.event_id, rec, pd.title, pd.old_start, '1');
    FOREACH rid IN ARRAY v_ids LOOP
      SELECT kind INTO v_kind FROM reminders WHERE id = rid;
      SELECT array_agg(DISTINCT offset_minutes) INTO offs FROM notifications
        WHERE reminder_id = rid AND type = 'pre_alert' AND state <> 'cancelled' AND offset_minutes > 0;
      UPDATE notifications SET state = 'cancelled' WHERE reminder_id = rid AND state = 'pending' AND type IN ('pre_alert', 'reminder', 'repeat');
      UPDATE reminders SET due_at = pd.new_start WHERE id = rid;
      IF v_kind = 'reminder' THEN
        INSERT INTO notifications(user_id, reminder_id, type, fire_at) VALUES (p_user, rid, 'reminder', pd.new_start);
      END IF;
      IF offs IS NOT NULL THEN
        FOREACH o IN ARRAY offs LOOP
          IF pd.new_start - make_interval(mins => o) > now() THEN
            INSERT INTO notifications(user_id, reminder_id, type, fire_at, offset_minutes)
            VALUES (p_user, rid, 'pre_alert', pd.new_start - make_interval(mins => o), o);
          END IF;
        END LOOP;
      END IF;
      n_av := n_av + 1;
    END LOOP;
    UPDATE agenda_pending SET state = 'done' WHERE id = pd.id;
    UPDATE agenda_pending SET state = 'cancelled' WHERE user_id = p_user AND state = 'open' AND grp IS NOT NULL AND grp = pd.grp AND id <> pd.id;
    t := 'Pronto, movi "' || pd.title || '" para ' || f_ag_fmt(pd.new_start, tz) || '.';
    IF rec <> '' THEN t := t || ' Só esta ocorrência; a série continua igual.'; END IF;
    IF n_av > 0 THEN t := t || ' Ajustei os avisos daqui também.'; END IF;
    IF (CASE WHEN pd.payload->>'attendees' ~ '^[0-9]+$' THEN (pd.payload->>'attendees')::int ELSE 0 END) > 0 THEN t := t || ' Os convidados foram avisados.'; END IF;
    RETURN jsonb_build_object('text', t, 'kb', 'none', 'rid', 0);

  ELSIF pd.kind = 'cancel' THEN
    v_ids := f_ag_links(p_user, CASE WHEN scope = 'a' THEN rec ELSE pd.event_id END, rec, pd.title, pd.old_start, CASE WHEN scope = 'a' THEN 'a' ELSE '1' END);
    UPDATE reminders SET status = 'cancelled' WHERE id = ANY (v_ids);
    UPDATE notifications SET state = 'cancelled' WHERE reminder_id = ANY (v_ids) AND state = 'pending';
    n_av := cardinality(v_ids);
    IF scope = 'a' AND rec <> '' THEN
      UPDATE agenda_series SET active = false WHERE user_id = p_user AND calendar_event_id = rec;
    END IF;
    UPDATE agenda_pending SET state = 'done' WHERE id = pd.id;
    UPDATE agenda_pending SET state = 'cancelled' WHERE user_id = p_user AND state = 'open' AND grp IS NOT NULL AND grp = pd.grp AND id <> pd.id;
    t := 'Cancelei "' || pd.title || '"' || CASE WHEN scope = 'a' THEN ' (a série inteira)' WHEN rec <> '' THEN ' (só ' || f_ag_fmt(pd.old_start, tz) || ')' ELSE ' (' || f_ag_fmt(pd.old_start, tz) || ')' END || ' no Google Agenda.';
    IF n_av > 0 THEN t := t || ' Cancelei ' || n_av || ' aviso(s)/lembrete(s) daqui.'; END IF;
    IF (CASE WHEN pd.payload->>'attendees' ~ '^[0-9]+$' THEN (pd.payload->>'attendees')::int ELSE 0 END) > 0 THEN t := t || ' Os convidados foram avisados.'; END IF;
    RETURN jsonb_build_object('text', t, 'kb', 'none', 'rid', 0);

  ELSIF pd.kind = 'respond' THEN
    UPDATE agenda_pending SET state = 'done' WHERE id = pd.id;
    RETURN jsonb_build_object('text', CASE WHEN coalesce(pd.payload->>'response', '') = 'declined' THEN 'Recusei' ELSE 'Aceitei' END
                              || ' o convite "' || pd.title || '" (' || f_ag_fmt(pd.old_start, tz) || ').', 'kb', 'none', 'rid', 0);
  END IF;
  RETURN jsonb_build_object('text', 'Pronto.', 'kb', 'none', 'rid', 0);
EXCEPTION WHEN others THEN
  RETURN jsonb_build_object('text', 'O Google respondeu, mas tive um problema ao atualizar meus registros. Confira sua agenda.', 'kb', 'none', 'rid', 0, 'err', SQLERRM);
END $$;
