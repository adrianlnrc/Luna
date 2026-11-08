-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agenda_after_create(p_user bigint, p_req jsonb, p_result jsonb)
-- Origem da definicao atual: 012_agenda.sql (linha 527)
-- Definicoes (migracao:linha), da mais antiga a atual: 012_agenda.sql:527
CREATE OR REPLACE FUNCTION f_agenda_after_create(p_user bigint, p_req jsonb, p_result jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  tz text; v_due timestamptz := f_ag_ts(p_req->>'due_iso'); v_fin timestamptz := f_ag_ts(p_req->>'end_iso');
  v_title text := coalesce(p_req->>'title', ''); v_freq text := coalesce(p_req->>'repeat_freq', ''); v_ev text := nullif(p_result->>'event_id', '');
  v_rem jsonb; v_rid bigint; v_lead int := nullif(p_req->>'lead_str', '')::int; t text := ''; kb text := 'none'; conf text; pid bigint;
  v_until date; v_count int; v_first date; v_promote bigint := nullif(p_req->>'promote_reminder_id', '')::bigint; err text; v_att text := coalesce(p_req->>'attendees', '');
  nl text := E'\n';
BEGIN
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  IF coalesce(p_result->>'ok', '') <> 'true' THEN
    err := CASE WHEN jsonb_typeof(p_result->'error') = 'string' THEN left(p_result->>'error', 140) ELSE NULL END;
    RETURN jsonb_build_object('text', 'Não consegui criar "' || v_title || '" no Google Agenda' || CASE WHEN err IS NOT NULL THEN ' (' || err || ')' ELSE '' END
                              || '. Nada foi marcado; pode tentar de novo.', 'kb', 'none', 'rid', 0);
  END IF;
  IF coalesce(p_result->>'conflict', '') = 'true' THEN
    INSERT INTO agenda_pending(user_id, kind, calendar_key, title, new_start, new_end, payload)
    VALUES (p_user, 'create', coalesce(p_req->>'calendar_key', ''), v_title, v_due, v_fin,
            jsonb_build_object('summary', v_title, 'start', p_req->>'due_iso', 'end', p_req->>'end_iso', 'location', coalesce(p_req->>'location', ''),
                               'attendees', v_att, 'meet', coalesce(p_req->>'meet', 'false') = 'true', 'repeat_freq', v_freq,
                               'repeat_until', coalesce(p_req->>'repeat_until', ''), 'repeat_count', coalesce(p_req->>'repeat_count', ''),
                               'lead_str', coalesce(p_req->>'lead_str', ''), 'source', coalesce(p_req->>'source', 'text'), 'force', false,
                               'conflicts', coalesce(p_result->'conflicts', '[]'::jsonb), 'promote_reminder_id', p_req->'promote_reminder_id'))
    RETURNING id INTO pid;
    SELECT string_agg((c->>'title') || ' (' || to_char(f_ag_ts(c->>'start') AT TIME ZONE tz, 'HH24:MI') || '–' || to_char(f_ag_ts(c->>'end') AT TIME ZONE tz, 'HH24:MI') || ')', ', ')
      INTO conf FROM jsonb_array_elements(coalesce(p_result->'conflicts', '[]'::jsonb)) c;
    RETURN jsonb_build_object('text', 'Atenção: "' || v_title || '" (' || f_ag_fmt(v_due, tz) || ') conflita com ' || coalesce(conf, 'outro compromisso') || '. Marco mesmo assim?',
                              'kb', 'ag_conflict', 'rid', pid);
  END IF;

  IF v_promote IS NOT NULL THEN
    UPDATE reminders SET calendar_event_id = v_ev WHERE id = v_promote AND user_id = p_user;
  ELSE
    v_rem := f_create_reminder(p_user, v_title, v_due, false, v_lead, 'event', v_ev, coalesce(nullif(p_req->>'source', ''), 'text'));
    v_rid := (v_rem->>'reminder_id')::bigint;
    IF coalesce((v_rem->>'ask_lead')::boolean, false) THEN kb := 'lead'; END IF;
  END IF;

  IF v_freq IN ('daily', 'weekly', 'monthly') AND v_due IS NOT NULL THEN
    v_first := (v_due AT TIME ZONE tz)::date;
    v_until := CASE WHEN coalesce(p_req->>'repeat_until', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN (p_req->>'repeat_until')::date END;
    v_count := nullif(p_req->>'repeat_count', '')::int;
    IF v_until IS NULL AND v_count IS NOT NULL AND v_count > 0 THEN
      v_until := CASE v_freq WHEN 'daily' THEN v_first + (v_count - 1) WHEN 'weekly' THEN v_first + 7 * (v_count - 1)
                           ELSE (v_first + make_interval(months => v_count - 1))::date END;
    END IF;
    INSERT INTO agenda_series(user_id, title, norm_title, start_time, freq, weekday, dom, first_date, until, duration_min, calendar_event_id)
    VALUES (p_user, v_title, f_norm(v_title), (v_due AT TIME ZONE tz)::time, v_freq, extract(isodow FROM v_first)::int, extract(day FROM v_first)::int, v_first, v_until,
            coalesce(round(extract(epoch FROM (v_fin - v_due)) / 60)::int, 60), v_ev);
  END IF;

  t := 'Agendado no seu Google Calendar: "' || v_title || '" - ' || f_ag_fmt(v_due, tz)
       || CASE WHEN coalesce(p_req->>'location', '') <> '' THEN ' em ' || (p_req->>'location') ELSE '' END || '.';
  IF v_freq IN ('daily', 'weekly', 'monthly') THEN
    t := t || nl || 'Repete ' || CASE v_freq WHEN 'daily' THEN 'todo dia' WHEN 'weekly' THEN 'toda semana (' || f_ag_dayname((v_due AT TIME ZONE tz)::date) || ')'
                                      ELSE 'todo mês (dia ' || extract(day FROM (v_due AT TIME ZONE tz))::int || ')' END
         || CASE WHEN v_until IS NOT NULL THEN ', até ' || to_char(v_until, 'DD/MM/YYYY') ELSE '' END || '.';
  END IF;
  IF v_att <> '' THEN t := t || nl || 'Os convidados foram avisados pelo Google.'; END IF;
  IF nullif(p_result->>'meet_link', '') IS NOT NULL THEN t := t || nl || 'Meet: ' || (p_result->>'meet_link'); END IF;
  IF v_lead IS NOT NULL AND v_lead > 0 AND v_promote IS NULL THEN t := t || nl || 'Aviso ' || v_lead || ' min antes' || CASE WHEN v_freq <> '' THEN ' (só da próxima ocorrência)' ELSE '' END || '.'; END IF;
  IF v_promote IS NOT NULL THEN t := t || nl || 'Seu lembrete daqui continua ativo.'; END IF;
  IF kb = 'lead' THEN t := t || nl || 'Quer que eu te lembre antes?'; END IF;
  RETURN jsonb_build_object('text', t, 'kb', kb, 'rid', coalesce(v_rid, 0));
EXCEPTION WHEN others THEN
  RETURN jsonb_build_object('text', 'O evento foi criado no Google, mas tive um problema ao registrar os avisos aqui. Confira sua agenda.', 'kb', 'none', 'rid', 0, 'err', SQLERRM);
END $$;
