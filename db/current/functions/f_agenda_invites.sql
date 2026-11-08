-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agenda_invites(p_user bigint, p_cal text, p_events jsonb)
-- Origem da definicao atual: 012_agenda.sql (linha 654)
-- Definicoes (migracao:linha), da mais antiga a atual: 012_agenda.sql:654
CREATE OR REPLACE FUNCTION f_agenda_invites(p_user bigint, p_cal text, p_events jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  u users%ROWTYPE; e jsonb; res jsonb := '[]'::jsonb; key text; st timestamptz; en timestamptz; pid bigint; org text; orgn text; cnt int := 0; ins int; t text;
BEGIN
  SELECT * INTO u FROM users WHERE id = p_user;
  IF NOT FOUND OR jsonb_typeof(p_events) <> 'array' THEN RETURN '[]'::jsonb; END IF;
  FOR e IN SELECT x FROM jsonb_array_elements(p_events) x
           WHERE coalesce(x->>'self_status', '') = 'needsAction' AND coalesce(x->>'organizer_self', 'false') <> 'true' AND coalesce(x->>'id', '') <> ''
           ORDER BY f_ag_ts(x->>'start') LOOP
    EXIT WHEN cnt >= 5;
    st := f_ag_ts(e->>'start'); en := coalesce(f_ag_ts(e->>'end'), st);
    IF st IS NULL OR en <= now() THEN CONTINUE; END IF;
    key := coalesce(nullif(e->>'recurring_id', ''), e->>'id');
    INSERT INTO agenda_invites_seen(user_id, event_id) VALUES (p_user, key) ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS ins = ROW_COUNT;
    IF ins = 0 THEN CONTINUE; END IF;
    org := coalesce(nullif(e->>'organizer', ''), 'alguém');
    SELECT initcap(name) INTO orgn FROM contacts WHERE user_id = p_user AND lower(email) = lower(org) LIMIT 1;
    INSERT INTO agenda_pending(user_id, kind, calendar_key, event_id, title, old_start, old_end, payload)
    VALUES (p_user, 'respond', p_cal, key, coalesce(e->>'title', '(sem título)'), st, en,
            jsonb_build_object('organizer', org, 'recurring', coalesce(e->>'recurring_id', '') <> ''))
    RETURNING id INTO pid;
    t := 'Convite de ' || coalesce(orgn || ' (' || org || ')', org) || ': ' || coalesce(e->>'title', '(sem título)') || ', ' || f_ag_fmt(st, u.timezone)
         || CASE WHEN coalesce(e->>'recurring_id', '') <> '' THEN ' (evento recorrente)' ELSE '' END || '. Aceitar ou recusar?';
    res := res || jsonb_build_array(jsonb_build_object('chat_id', u.telegram_id, 'text', t, 'rid', pid));
    cnt := cnt + 1;
  END LOOP;
  RETURN res;
EXCEPTION WHEN others THEN
  RETURN '[]'::jsonb;
END $$;
