-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_invite_prepare(p_user bigint, p jsonb)
-- Origem da definicao atual: 023_locais_pergunta.sql (linha 29)
-- Definicoes (migracao:linha), da mais antiga a atual: 014_contatos_convites.sql:295, 021_locais_comandos.sql:155, 023_locais_pergunta.sql:29
CREATE OR REPLACE FUNCTION f_invite_prepare(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE
  u users%ROWTYPE;
  names text[] := COALESCE(ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'invitees') = 'array' THEN p->'invitees' ELSE '[]'::jsonb END)), '{}');
  v_meet boolean := COALESCE((p->>'meet')::boolean, false);
  v_start timestamptz; v_end timestamptz; v_title text;
  res jsonb; unk text[]; emails text; shown text; ex text; pid bigint; pl jsonb; lbl text; tzn text;
  v_loc text; v_place bigint; gtxt text; v_pname text; v_pnorm text; v_ppid bigint;
  wd text[] := ARRAY['dom','seg','ter','qua','qui','sex','sáb'];
BEGIN
  SELECT * INTO u FROM users WHERE id = p_user;
  IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Não achei seu cadastro.', 'kb', 'none', 'rid', 0); END IF;
  IF COALESCE(u.calendar_key, '') = '' THEN
    RETURN jsonb_build_object('text', 'Seu Google Agenda não está conectado, então não consigo enviar convites nem criar link do Meet.', 'kb', 'none', 'rid', 0);
  END IF;
  tzn := COALESCE(NULLIF(u.timezone, ''), 'America/Sao_Paulo');
  BEGIN
    v_start := NULLIF(p->>'start', '')::timestamptz;
    v_end := COALESCE(NULLIF(p->>'end', '')::timestamptz, v_start + interval '1 hour');
  EXCEPTION WHEN OTHERS THEN v_start := NULL;
  END;
  IF v_start IS NULL THEN
    RETURN jsonb_build_object('text', 'Não entendi o dia e a hora. Pode repetir?', 'kb', 'none', 'rid', 0);
  END IF;
  v_title := COALESCE(NULLIF(trim(p->>'summary'), ''), 'Reunião');

  -- local: se o nome bate com um local salvo, usa o endereço salvo
  v_loc := COALESCE(btrim(p->>'location'), '');
  v_place := f_place_find(p_user, v_loc);
  IF v_place IS NOT NULL THEN SELECT address INTO v_loc FROM places WHERE id = v_place; END IF;

  res := f_resolve_invitees(p_user, names);
  unk := COALESCE(ARRAY(SELECT jsonb_array_elements_text(res->'unknown')), '{}');
  IF array_length(unk, 1) > 0 THEN
    RETURN jsonb_build_object('text', 'Não achei ' || (SELECT string_agg('"' || x || '"', ' e ') FROM unnest(unk) x)
      || ' nos seus contatos nem grupos. Para criar um grupo, diga: "cria o grupo ' || unk[1] || ' com Fulano e Beltrana". Ou me passe o e-mail: "o e-mail ' || f_ct_de(unk[1]) || ' é fulano@dominio.com".', 'kb', 'none', 'rid', 0);
  END IF;
  IF array_length(names, 1) > 0 AND jsonb_array_length(res->'invitees') = 0 THEN
    RETURN jsonb_build_object('text', 'Não encontrei ninguém para convidar (o grupo está vazio?). Veja com /contatos.', 'kb', 'none', 'rid', 0);
  END IF;

  -- local que parece nome e nao esta salvo: pergunta o endereco antes de criar a pendencia do compromisso
  IF v_place IS NULL AND COALESCE((p->>'place_checked')::boolean, false) IS NOT TRUE AND f_place_is_name(v_loc) THEN
    v_pname := lower(btrim(regexp_replace(v_loc, '^(a|o|na|no|da|do|de|em) ', '', 'i')));
    v_pnorm := f_norm(left(v_pname, 60));
    IF v_pnorm <> '' THEN
      UPDATE place_pending SET state = 'cancelled'
       WHERE user_id = p_user AND state = 'open' AND (norm_name = v_pnorm OR created_at < now() - interval '30 minutes');
      INSERT INTO place_pending(user_id, name, norm_name, payload) VALUES (p_user, v_pname, v_pnorm, p) RETURNING id INTO v_ppid;
      RETURN jsonb_build_object('text', 'Não tenho o endereço de "' || v_pname || '". Qual é? Eu salvo para as próximas vezes.', 'kb', 'place_ask', 'rid', v_ppid);
    END IF;
  END IF;

  -- sem repetir e-mail
  SELECT string_agg(e, ',' ORDER BY o), string_agg(nm, ', ' ORDER BY o)
    INTO emails, shown
  FROM (SELECT DISTINCT ON (x->>'email') x->>'email' AS e,
               CASE WHEN x->>'name' = x->>'email' THEN x->>'email' ELSE f_ct_disp(x->>'name') END AS nm, o
        FROM jsonb_array_elements(res->'invitees') WITH ORDINALITY t(x, o) ORDER BY x->>'email', o) d;
  -- quais nomes citados eram grupos
  SELECT string_agg('grupo ' || f_ct_disp(cg.name), ' e ') INTO gtxt FROM unnest(names) x JOIN contact_groups cg ON cg.id = f_ct_group_find(p_user, x);

  pl := jsonb_build_object('summary', v_title, 'start', f_ct_iso(v_start, tzn),
        'end', f_ct_iso(v_end, tzn),
        'location', v_loc, 'attendees', COALESCE(emails, ''), 'meet', v_meet,
        'repeat_freq', COALESCE(p->>'repeat_freq', ''), 'repeat_until', COALESCE(p->>'repeat_until', ''),
        'repeat_count', COALESCE(NULLIF(p->>'repeat_count', '')::int, 0),
        'lead_str', COALESCE(p->>'lead_str', ''), 'source', COALESCE(NULLIF(p->>'source', ''), 'text'), 'force', false);
  IF (pl->>'repeat_count')::int = 0 THEN pl := jsonb_set(pl, '{repeat_count}', '""'::jsonb); END IF;

  -- idempotencia: mesma pendencia aberta recente
  SELECT id INTO pid FROM agenda_pending
   WHERE user_id = p_user AND kind = 'create' AND state = 'open' AND created_at > now() - interval '30 minutes'
     AND new_start = v_start AND title = v_title AND payload->>'attendees' = COALESCE(emails, '')
     AND (payload->>'meet')::boolean = v_meet
   ORDER BY id DESC LIMIT 1;
  IF pid IS NULL THEN
    INSERT INTO agenda_pending(user_id, kind, calendar_key, title, new_start, new_end, payload)
    VALUES (p_user, 'create', u.calendar_key, v_title, v_start, v_end, pl) RETURNING id INTO pid;
  END IF;

  lbl := wd[extract(dow FROM v_start AT TIME ZONE tzn)::int + 1] || ' ' || to_char(v_start AT TIME ZONE tzn, 'DD/MM') || ' às ' || to_char(v_start AT TIME ZONE tzn, 'HH24:MI');
  ex := 'Marcar ' || v_title || ' ' || lbl;
  IF v_loc <> '' THEN ex := ex || ' em ' || v_loc; END IF;
  IF shown IS NOT NULL THEN
    ex := ex || ' e enviar convite para ' || shown || CASE WHEN gtxt IS NOT NULL THEN ' (' || gtxt || ')' ELSE '' END;
  END IF;
  IF v_meet THEN ex := ex || ' (com link do Meet)'; END IF;
  RETURN jsonb_build_object('text', ex || '?', 'kb', 'ag_confirm', 'rid', pid);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('text', 'Não consegui preparar o convite agora. Tente de novo em instantes.', 'kb', 'none', 'rid', 0);
END $$;
