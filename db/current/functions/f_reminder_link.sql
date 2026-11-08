-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_reminder_link(p_user bigint, p jsonb)
-- Origem da definicao atual: 012_agenda.sql (linha 597)
-- Definicoes (migracao:linha), da mais antiga a atual: 012_agenda.sql:597
CREATE OR REPLACE FUNCTION f_reminder_link(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  u users%ROWTYPE; tz text; q text := btrim(coalesce(p->>'link_event', '')); v_title text := btrim(coalesce(p->>'title', '')); v_person text := btrim(coalesce(p->>'person', ''));
  s agenda_series%ROWTYPE; s_next timestamptz; s_best int; r_ev reminders%ROWTYPE; r_best int; occ timestamptz; occ_title text; v_sid bigint;
  v_lead int; v_rem jsonb; v_rid bigint; cn text; cnt int; t text;
BEGIN
  SELECT * INTO u FROM users WHERE id = p_user;
  IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Não achei o seu cadastro.', 'kb', 'none'); END IF;
  tz := u.timezone;
  IF v_title = '' THEN v_title := 'Lembrete de ' || q; END IF;
  -- 1) serie recorrente (a de proxima ocorrencia mais cedo entre as que melhor combinam)
  SELECT min(f_ag_match(q, x.title)) INTO s_best FROM agenda_series x WHERE x.user_id = p_user AND x.active AND f_series_next(x.id) IS NOT NULL AND f_ag_match(q, x.title) > 0;
  IF s_best IS NOT NULL THEN
    SELECT * INTO s FROM agenda_series x
      WHERE x.user_id = p_user AND x.active AND f_ag_match(q, x.title) = s_best AND f_series_next(x.id) IS NOT NULL
      ORDER BY f_series_next(x.id) LIMIT 1;
    s_next := f_series_next(s.id);
  END IF;
  -- 2) evento unico (espelho em reminders kind=event)
  SELECT min(f_ag_match(q, x.title)) INTO r_best FROM reminders x WHERE x.user_id = p_user AND x.kind = 'event' AND x.status = 'pending' AND x.due_at > now() AND f_ag_match(q, x.title) > 0;
  IF r_best IS NOT NULL THEN
    SELECT * INTO r_ev FROM reminders x WHERE x.user_id = p_user AND x.kind = 'event' AND x.status = 'pending' AND x.due_at > now() AND f_ag_match(q, x.title) = r_best ORDER BY x.due_at LIMIT 1;
  END IF;
  IF s_next IS NOT NULL AND (r_ev.id IS NULL OR s_next <= r_ev.due_at) THEN
    occ := s_next; occ_title := s.title; v_sid := s.id;
  ELSIF r_ev.id IS NOT NULL THEN
    occ := r_ev.due_at; occ_title := r_ev.title;
  END IF;
  IF occ IS NULL THEN
    RETURN jsonb_build_object('text', 'Não achei o compromisso "' || q || '" na sua agenda. Me diga a data e a hora que eu crio o lembrete "' || v_title || '".', 'kb', 'none', 'rid', 0,
      'state', jsonb_build_object('kind', 'clarify', 'original', 'Lembrete "' || v_title || '"' || CASE WHEN v_person <> '' THEN ' (para ' || v_person || ')' ELSE '' END || ' ligado ao compromisso "' || q || '", que não encontrei; falta a data e a hora')::text);
  END IF;
  -- pessoa: casa com os contatos pelo nome
  IF v_person <> '' THEN
    SELECT c.name INTO cn FROM contacts c WHERE c.user_id = p_user AND f_norm(c.name) = f_norm(v_person) LIMIT 1;
    IF cn IS NULL THEN
      SELECT count(*) INTO cnt FROM contacts c WHERE c.user_id = p_user AND f_norm(c.name) LIKE f_norm(v_person) || '%';
      IF cnt = 1 THEN SELECT c.name INTO cn FROM contacts c WHERE c.user_id = p_user AND f_norm(c.name) LIKE f_norm(v_person) || '%'; END IF;
    END IF;
    IF cn IS NOT NULL THEN v_person := initcap(cn); END IF;
  END IF;
  v_lead := CASE WHEN coalesce(nullif(p->>'lead_minutes', '')::int, 0) > 0 THEN (p->>'lead_minutes')::int
                WHEN coalesce(u.default_lead_minutes, 0) > 0 THEN u.default_lead_minutes ELSE 60 END;
  v_rem := f_create_reminder(p_user, v_title, occ, false, v_lead, 'reminder', NULL, coalesce(nullif(p->>'source', ''), 'text'));
  v_rid := (v_rem->>'reminder_id')::bigint;
  UPDATE reminders SET series_id = v_sid, person = nullif(v_person, ''), notes = 'Compromisso: ' || occ_title WHERE id = v_rid;
  t := 'Lembrete ligado a ' || occ_title || ' (' || f_ag_fmt(occ, tz) || ')' || CASE WHEN v_person <> '' THEN ' e a ' || v_person ELSE '' END || ': "' || v_title || '".'
       || ' Aviso ' || v_lead || ' min antes.'
       || CASE WHEN v_sid IS NOT NULL THEN ' Vale só para essa próxima ocorrência; depois dela, me peça de novo.' ELSE '' END;
  RETURN jsonb_build_object('text', t, 'kb', 'none', 'rid', v_rid, 'person_matched', cn IS NOT NULL);
EXCEPTION WHEN others THEN
  RETURN jsonb_build_object('text', 'Não consegui ligar o lembrete ao compromisso agora. Tente de novo.', 'kb', 'none', 'rid', 0, 'err', SQLERRM);
END $$;
