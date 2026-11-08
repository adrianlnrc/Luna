-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agenda_manage(p_user bigint, p jsonb)
-- Origem da definicao atual: 012_agenda.sql (linha 162)
-- Definicoes (migracao:linha), da mais antiga a atual: 012_agenda.sql:162
CREATE OR REPLACE FUNCTION f_agenda_manage(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  u users%ROWTYPE; tz text; act text := lower(coalesce(p->>'act', '')); q text := btrim(coalesce(p->>'title', ''));
  ck text := coalesce(p->>'calendar_key', '');
  ev jsonb := CASE WHEN jsonb_typeof(p->'events') = 'array' THEN p->'events' ELSE '[]'::jsonb END;
  cands jsonb; n int; c jsonb; i int; grp uuid; pid bigint; pids bigint[] := '{}';
  v_st timestamptz; v_en timestamptz; v_ns timestamptz; v_ne timestamptz; v_dur int; v_nt time; conf jsonb; v_cnt int := 0;
  lines text := ''; d date; d0 date; d1 date; ps time; pe time; ts_s timestamptz; ts_e timestamptz; cur timestamptz; cur_now timestamptz;
  b record; mins int; part text; blocks text; nl text := E'\n'; any_free boolean := false; clamped boolean := false; label text; r reminders%ROWTYPE;
  rn int; rbest int;
BEGIN
  SELECT * INTO u FROM users WHERE id = p_user;
  IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Não achei o seu cadastro.', 'kb', 'none'); END IF;
  tz := u.timezone;
  UPDATE agenda_pending SET state = 'cancelled' WHERE user_id = p_user AND state = 'open' AND kind <> 'respond' AND created_at < now() - interval '1 day';
  IF act NOT IN ('move', 'cancel', 'free', 'promote') THEN
    RETURN jsonb_build_object('text', 'Não entendi o que fazer na agenda. Diga, por exemplo: "muda a reunião de sexta para as 15h" ou "cancela o dentista".', 'kb', 'none');
  END IF;
  IF ck = '' THEN
    RETURN jsonb_build_object('text', 'Seu Google Calendar ainda não está conectado ao agente, então não consigo mexer na agenda por aqui.', 'kb', 'none');
  END IF;
  IF act <> 'promote' AND coalesce(p->>'ok', '') = 'false' THEN
    RETURN jsonb_build_object('text', 'Não consegui ler sua agenda agora' || CASE WHEN jsonb_typeof(p->'error') = 'string' THEN ' (' || left(p->>'error', 120) || ')' ELSE '' END || '. Tente de novo em instantes.', 'kb', 'none');
  END IF;

  -- ============================================================ cancelar / mover
  IF act IN ('cancel', 'move') THEN
    IF q = '' THEN
      RETURN jsonb_build_object('text', 'Qual compromisso? Me diga o nome (e o dia, se tiver mais de um).', 'kb', 'none');
    END IF;
    IF act = 'move' AND nullif(p->>'new_start', '') IS NULL AND nullif(p->>'new_time', '') IS NULL THEN
      RETURN jsonb_build_object('text', 'Para que horário eu movo "' || q || '"?', 'kb', 'none');
    END IF;
    WITH cc AS (
      SELECT e, f_ag_ts(e->>'start') st, f_ag_ts(e->>'end') en, coalesce(e->>'all_day', '') = 'true' ad, f_ag_match(q, e->>'title') m
      FROM jsonb_array_elements(ev) e
    ), ff AS (
      SELECT * FROM cc
      WHERE m > 0 AND st IS NOT NULL AND coalesce(e->>'self_status', '') <> 'declined' AND coalesce(e->>'id', '') <> ''
        AND (act = 'cancel' OR NOT ad)
        AND coalesce(en, st) > now() - (CASE WHEN ad THEN interval '1 day' ELSE interval '0' END)
    ), bm AS (SELECT min(m) mm FROM ff)
    SELECT jsonb_agg(jsonb_build_object('e', ff.e, 'st', ff.st, 'en', coalesce(ff.en, ff.st)) ORDER BY ff.st), count(*)
      INTO cands, n FROM ff, bm WHERE ff.m = bm.mm;
    IF n = 0 OR cands IS NULL THEN
      RETURN jsonb_build_object('text', 'Não achei nenhum compromisso com "' || q || '" no período buscado. Diga o dia ou o nome completo e eu tento de novo.', 'kb', 'none');
    END IF;
    IF n > 1 THEN grp := gen_random_uuid(); END IF;
    FOR i IN 0..least(n, 3) - 1 LOOP
      c := cands->i;
      v_st := (c->>'st')::timestamptz; v_en := (c->>'en')::timestamptz;
      conf := NULL; v_ns := NULL; v_ne := NULL;
      IF act = 'move' THEN
        v_ns := f_ag_ts(p->>'new_start');
        IF v_ns IS NULL THEN
          v_nt := (p->>'new_time')::time;
          v_ns := (((v_st AT TIME ZONE tz)::date + v_nt)::timestamp) AT TIME ZONE tz;
        END IF;
        v_dur := coalesce(nullif(p->>'duration_minutes', '')::int, round(extract(epoch FROM (v_en - v_st)) / 60)::int);
        IF v_dur IS NULL OR v_dur <= 0 THEN v_dur := 60; END IF;
        v_ne := v_ns + make_interval(mins => v_dur);
        IF v_ns <= now() THEN CONTINUE; END IF;
        SELECT jsonb_agg(jsonb_build_object('title', x->>'title', 'start', x->>'start', 'end', x->>'end')) INTO conf
        FROM jsonb_array_elements(ev) x
        WHERE coalesce(x->>'id', '') <> coalesce(c->'e'->>'id', '') AND coalesce(x->>'all_day', '') <> 'true'
          AND coalesce(x->>'self_status', '') <> 'declined'
          AND f_ag_ts(x->>'start') < v_ne AND f_ag_ts(x->>'end') > v_ns;
      END IF;
      INSERT INTO agenda_pending(user_id, kind, calendar_key, grp, event_id, title, old_start, old_end, new_start, new_end, payload)
      VALUES (p_user, act, ck, grp, c->'e'->>'id', coalesce(c->'e'->>'title', q), v_st, v_en, v_ns, v_ne,
              jsonb_build_object('recurring_id', coalesce(c->'e'->>'recurring_id', ''),
                                 'attendees', coalesce(nullif(c->'e'->>'attendees', '')::int, 0),
                                 'all_day', coalesce(c->'e'->>'all_day', '') = 'true',
                                 'location', coalesce(c->'e'->>'location', ''),
                                 'conflicts', coalesce(conf, '[]'::jsonb)))
      RETURNING id INTO pid;
      pids := pids || pid;
      v_cnt := v_cnt + 1;
      lines := lines || nl || v_cnt || ') ' || coalesce(c->'e'->>'title', q) || ' - ' || f_ag_fmt(v_st, tz);
    END LOOP;
    IF v_cnt = 0 THEN
      RETURN jsonb_build_object('text', 'Esse horário novo já passou. Para quando eu movo "' || q || '"?', 'kb', 'none');
    END IF;
    IF v_cnt = 1 THEN
      RETURN f_ag_confirm(pids[1]);
    END IF;
    RETURN jsonb_build_object('text', 'Achei ' || CASE WHEN n > 3 THEN 'mais de 3 compromissos (mostro os 3 mais próximos)' ELSE v_cnt || ' compromissos' END
                              || '. Qual deles?' || lines,
                              'kb', CASE WHEN v_cnt = 2 THEN 'ag_pick2' ELSE 'ag_pick3' END, 'rid', pids[1]);
  END IF;

  -- ============================================================ horario livre
  IF act = 'free' THEN
    d0 := coalesce((f_ag_ts(p->>'win_start') AT TIME ZONE tz)::date, f_fin_today(p_user));
    d1 := CASE WHEN f_ag_ts(p->>'win_end') IS NULL THEN d0 ELSE ((f_ag_ts(p->>'win_end') - interval '1 second') AT TIME ZONE tz)::date END;
    IF d1 < d0 THEN d1 := d0; END IF;
    IF d1 > d0 + 6 THEN d1 := d0 + 6; clamped := true; END IF;
    mins := least(greatest(coalesce(nullif(p->>'min_minutes', '')::int, 30), 5), 720);
    part := lower(btrim(coalesce(p->>'part', '')));
    label := CASE part WHEN 'manha' THEN ' (manhã)' WHEN 'tarde' THEN ' (tarde)' WHEN 'noite' THEN ' (noite)' ELSE '' END;
    cur_now := date_trunc('hour', now()) + ceil(extract(minute FROM now()) / 15.0) * interval '15 minutes';
    FOR d IN SELECT g::date FROM generate_series(d0::timestamp, d1::timestamp, interval '1 day') g LOOP
      IF part ~ '^[0-9]{1,2}:[0-9]{2}-[0-9]{1,2}:[0-9]{2}$' THEN
        ps := split_part(part, '-', 1)::time; pe := split_part(part, '-', 2)::time; label := ' (' || to_char(ps, 'HH24:MI') || '–' || to_char(pe, 'HH24:MI') || ')';
      ELSIF part = 'manha' THEN ps := u.work_start; pe := least(u.work_end, time '12:00');
      ELSIF part = 'tarde' THEN ps := greatest(u.work_start, time '12:00'); pe := u.work_end;
      ELSIF part = 'noite' THEN ps := u.work_end; pe := time '22:00';
      ELSE ps := u.work_start; pe := u.work_end; END IF;
      IF pe <= ps THEN CONTINUE; END IF;
      ts_s := (d + ps) AT TIME ZONE tz; ts_e := (d + pe) AT TIME ZONE tz;
      cur := greatest(ts_s, cur_now);
      IF cur >= ts_e THEN CONTINUE; END IF;
      blocks := '';
      FOR b IN SELECT f_ag_ts(x->>'start') st, f_ag_ts(x->>'end') en FROM jsonb_array_elements(ev) x
               WHERE coalesce(x->>'all_day', '') <> 'true' AND coalesce(x->>'self_status', '') <> 'declined'
                 AND f_ag_ts(x->>'start') IS NOT NULL AND f_ag_ts(x->>'end') IS NOT NULL
                 AND f_ag_ts(x->>'end') > cur AND f_ag_ts(x->>'start') < ts_e
               ORDER BY 1 LOOP
        IF b.st - cur >= make_interval(mins => mins) THEN
          blocks := blocks || CASE WHEN blocks = '' THEN '' ELSE ', ' END || to_char(cur AT TIME ZONE tz, 'HH24:MI') || '–' || to_char(b.st AT TIME ZONE tz, 'HH24:MI');
        END IF;
        cur := greatest(cur, b.en);
      END LOOP;
      IF ts_e - cur >= make_interval(mins => mins) THEN
        blocks := blocks || CASE WHEN blocks = '' THEN '' ELSE ', ' END || to_char(cur AT TIME ZONE tz, 'HH24:MI') || '–' || to_char(ts_e AT TIME ZONE tz, 'HH24:MI');
      END IF;
      IF blocks <> '' THEN
        lines := lines || nl || '- ' || f_ag_dayname(d) || ' ' || to_char(d, 'DD/MM') || ': ' || blocks;
        any_free := true;
      END IF;
    END LOOP;
    IF NOT any_free THEN
      RETURN jsonb_build_object('text', 'Não achei horário livre de pelo menos ' || mins || ' min' || label || CASE WHEN d0 = d1 THEN ' em ' || to_char(d0, 'DD/MM') ELSE ' entre ' || to_char(d0, 'DD/MM') || ' e ' || to_char(d1, 'DD/MM') END
        || ' (expediente ' || to_char(u.work_start, 'HH24:MI') || '–' || to_char(u.work_end, 'HH24:MI') || ').', 'kb', 'none');
    END IF;
    RETURN jsonb_build_object('text', 'Horários livres' || label || ' (blocos de pelo menos ' || mins || ' min, expediente ' || to_char(u.work_start, 'HH24:MI') || '–' || to_char(u.work_end, 'HH24:MI') || '):' || lines
      || CASE WHEN clamped THEN nl || 'Mostrei só os primeiros 7 dias.' ELSE '' END, 'kb', 'none');
  END IF;

  -- ============================================================ lembrete vira compromisso
  IF act = 'promote' THEN
    IF q = '' THEN
      RETURN jsonb_build_object('text', 'Qual lembrete eu coloco no Google Agenda? Me diga o nome.', 'kb', 'none');
    END IF;
    SELECT min(f_ag_match(q, title)) FILTER (WHERE f_ag_match(q, title) > 0), count(*) FILTER (WHERE f_ag_match(q, title) > 0)
      INTO rbest, rn FROM reminders WHERE user_id = p_user AND kind = 'reminder' AND status = 'pending' AND due_at > now();
    IF rn = 0 OR rbest IS NULL THEN
      RETURN jsonb_build_object('text', 'Não achei nenhum lembrete pendente com "' || q || '".', 'kb', 'none');
    END IF;
    SELECT * INTO r FROM reminders WHERE user_id = p_user AND kind = 'reminder' AND status = 'pending' AND due_at > now()
      AND f_ag_match(q, title) = rbest ORDER BY due_at LIMIT 1;
    v_dur := coalesce(nullif(p->>'duration_minutes', '')::int, 60);
    INSERT INTO agenda_pending(user_id, kind, calendar_key, title, new_start, new_end, payload)
    VALUES (p_user, 'create', ck, r.title, r.due_at, r.due_at + make_interval(mins => v_dur),
            jsonb_build_object('summary', r.title, 'start', f_ag_iso(r.due_at), 'end', f_ag_iso(r.due_at + make_interval(mins => v_dur)),
                               'location', '', 'attendees', '', 'meet', false, 'repeat_freq', '', 'repeat_until', '', 'repeat_count', '',
                               'lead_str', '', 'source', 'text', 'force', false, 'promote_reminder_id', r.id))
    RETURNING id INTO pid;
    RETURN jsonb_build_object('text', 'Criar "' || r.title || '" no seu Google Agenda em ' || f_ag_fmt(r.due_at, tz) || ' (' || v_dur || ' min)? O lembrete daqui continua ativo.'
                              || CASE WHEN rn > 1 THEN ' (Achei ' || rn || ' lembretes parecidos; peguei o mais próximo.)' ELSE '' END,
                              'kb', 'ag_confirm', 'rid', pid);
  END IF;
  RETURN jsonb_build_object('text', 'Não entendi o pedido de agenda.', 'kb', 'none');
EXCEPTION WHEN others THEN
  RETURN jsonb_build_object('text', 'Não consegui mexer na agenda agora. Tente de novo em instantes.', 'kb', 'none', 'err', SQLERRM);
END $$;
