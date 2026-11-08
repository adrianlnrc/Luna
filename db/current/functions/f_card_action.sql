-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_card_action(p_user bigint, p jsonb)
-- Origem da definicao atual: 013_extras.sql (linha 491)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:491
CREATE OR REPLACE FUNCTION f_card_action(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE act text := coalesce(p->>'action', ''); hint text; nm text; cid bigint; c fin_cards%ROWTYPE; cl integer; du integer; lim numeric; al integer; t text := ''; n integer; r record;
BEGIN
  -- o campo title vem sempre preenchido pelo modelo: so serve de reserva para cadastrar/editar
  hint := coalesce(nullif(btrim(p->>'card'), ''), CASE WHEN act IN ('card_create', 'card_edit') THEN nullif(btrim(p->>'title'), '') END, '');
  nm := btrim(regexp_replace(hint, '^((o|a) )?cart[aã]o( ?(do|da|de))? ', '', 'i'));
  BEGIN cl := nullif(p->>'card_closing_day', '')::int; EXCEPTION WHEN others THEN cl := NULL; END;
  BEGIN du := nullif(p->>'card_due_day', '')::int; EXCEPTION WHEN others THEN du := NULL; END;
  BEGIN lim := nullif(p->>'card_limit', '')::numeric; EXCEPTION WHEN others THEN lim := NULL; END;
  BEGIN al := nullif(p->>'alert_days', '')::int; EXCEPTION WHEN others THEN al := NULL; END;
  IF cl IS NOT NULL AND cl NOT BETWEEN 1 AND 31 THEN cl := NULL; END IF;
  IF du IS NOT NULL AND du NOT BETWEEN 1 AND 31 THEN du := NULL; END IF;
  IF al IS NOT NULL AND al NOT BETWEEN 0 AND 20 THEN al := NULL; END IF;
  IF lim IS NOT NULL AND lim < 0 THEN lim := NULL; END IF;

  IF act IN ('card_create', 'card_edit') THEN
    cid := f_card_find(p_user, nm);
    IF cid IS NULL AND nm = '' THEN
      SELECT count(*) INTO n FROM fin_cards WHERE user_id = p_user AND active;
      IF n = 1 THEN SELECT id INTO cid FROM fin_cards WHERE user_id = p_user AND active; END IF;
    END IF;
    IF cid IS NULL THEN
      IF nm = '' THEN
        RETURN jsonb_build_object('text', 'Qual é o nome do cartão? Ex.: "cartão Itaú fecha dia 10 vence dia 17 limite 5000".', 'kb', 'none');
      END IF;
      IF cl IS NULL OR du IS NULL THEN
        RETURN jsonb_build_object('text', 'Para cadastrar o cartão ' || nm || ', me diga o dia que a fatura fecha e o dia que vence. Ex.: "cartão ' || nm || ' fecha dia 10 vence dia 17 limite 5000".', 'kb', 'none');
      END IF;
      INSERT INTO fin_cards (user_id, name, norm_name, closing_day, due_day, card_limit, alert_days)
      VALUES (p_user, left(nm, 40), f_norm(nm), cl, du, lim, coalesce(al, 3))
      ON CONFLICT (user_id, norm_name) DO UPDATE SET closing_day = EXCLUDED.closing_day, due_day = EXCLUDED.due_day,
        card_limit = coalesce(EXCLUDED.card_limit, fin_cards.card_limit), alert_days = EXCLUDED.alert_days, active = true
      RETURNING id INTO cid;
      PERFORM f_card_alert_sync(cid);
      SELECT * INTO c FROM fin_cards WHERE id = cid;
      RETURN jsonb_build_object('text', 'Cadastrei o cartão ' || c.name || ': fecha dia ' || c.closing_day || ', vence dia ' || c.due_day ||
        CASE WHEN c.card_limit IS NOT NULL THEN ', limite ' || f_brl(c.card_limit) ELSE '' END || '. Te aviso ' || c.alert_days || ' dia' || CASE WHEN c.alert_days <> 1 THEN 's' ELSE '' END ||
        ' antes do vencimento, às 9h. Para lançar: "almoço 40 no cartão ' || c.name || '".', 'kb', 'none');
    END IF;
    -- editar
    IF cl IS NULL AND du IS NULL AND lim IS NULL AND al IS NULL THEN
      SELECT * INTO c FROM fin_cards WHERE id = cid;
      RETURN jsonb_build_object('text', 'O cartão ' || c.name || ' hoje fecha dia ' || c.closing_day || ', vence dia ' || c.due_day ||
        CASE WHEN c.card_limit IS NOT NULL THEN ', limite ' || f_brl(c.card_limit) ELSE ', sem limite' END || '. O que mudo? Ex.: "fecha dia 12", "limite 6000", "me avisa 5 dias antes".', 'kb', 'none');
    END IF;
    UPDATE fin_cards SET closing_day = coalesce(cl, closing_day), due_day = coalesce(du, due_day), card_limit = coalesce(lim, card_limit), alert_days = coalesce(al, alert_days)
     WHERE id = cid RETURNING * INTO c;
    PERFORM f_card_alert_sync(cid);
    RETURN jsonb_build_object('text', 'Atualizei o cartão ' || c.name || ': fecha dia ' || c.closing_day || ', vence dia ' || c.due_day ||
      CASE WHEN c.card_limit IS NOT NULL THEN ', limite ' || f_brl(c.card_limit) ELSE '' END || ', aviso ' || c.alert_days || ' dia' || CASE WHEN c.alert_days <> 1 THEN 's' ELSE '' END || ' antes.', 'kb', 'none');
  END IF;

  IF act = 'card_remove' THEN
    cid := f_card_find(p_user, nm);
    IF cid IS NULL AND nm = '' THEN
      SELECT count(*) INTO n FROM fin_cards WHERE user_id = p_user AND active;
      IF n = 1 THEN SELECT id INTO cid FROM fin_cards WHERE user_id = p_user AND active; END IF;
    END IF;
    IF cid IS NULL THEN RETURN jsonb_build_object('text', 'Não achei esse cartão. Diga "meus cartões" para ver a lista.', 'kb', 'none'); END IF;
    SELECT * INTO c FROM fin_cards WHERE id = cid;
    RETURN jsonb_build_object('text', 'Apagar o cartão ' || c.name || '? Os lançamentos continuam, só perdem a ligação com o cartão, e o aviso de vencimento acaba.', 'kb', 'ex_card_del', 'rid', cid);
  END IF;

  IF act = 'card_list' THEN
    FOR r IN SELECT * FROM fin_cards WHERE user_id = p_user AND active ORDER BY name LOOP
      t := t || E'\n- ' || r.name || ': fecha dia ' || r.closing_day || ', vence dia ' || r.due_day || CASE WHEN r.card_limit IS NOT NULL THEN ', limite ' || f_brl(r.card_limit) ELSE '' END;
    END LOOP;
    IF t = '' THEN RETURN jsonb_build_object('text', 'Você ainda não tem cartões. Diga, por exemplo: "cartão Itaú fecha dia 10 vence dia 17 limite 5000".', 'kb', 'none'); END IF;
    RETURN jsonb_build_object('text', 'Seus cartões:' || t, 'kb', 'none');
  END IF;

  IF act = 'card_status' THEN
    cid := CASE WHEN nm = '' THEN NULL ELSE f_card_find(p_user, nm) END;
    IF cid IS NOT NULL THEN RETURN jsonb_build_object('text', f_card_status_text(cid), 'kb', 'none'); END IF;
    IF nm <> '' THEN
      RETURN jsonb_build_object('text', 'Não achei o cartão "' || nm || '". Diga "meus cartões" para ver a lista ou cadastre: "cartão ' || nm || ' fecha dia 10 vence dia 17 limite 5000".', 'kb', 'none');
    END IF;
    n := 0;
    FOR r IN SELECT id FROM fin_cards WHERE user_id = p_user AND active ORDER BY name LIMIT 4 LOOP
      n := n + 1; t := t || CASE WHEN n > 1 THEN E'\n\n' ELSE '' END || f_card_status_text(r.id);
    END LOOP;
    IF n = 0 THEN RETURN jsonb_build_object('text', 'Você ainda não tem cartões. Diga, por exemplo: "cartão Itaú fecha dia 10 vence dia 17 limite 5000".', 'kb', 'none'); END IF;
    RETURN jsonb_build_object('text', t, 'kb', 'none');
  END IF;

  RETURN jsonb_build_object('text', 'Não entendi o que fazer com o cartão.', 'kb', 'none');
EXCEPTION WHEN others THEN
  RAISE WARNING 'f_card_action: %', SQLERRM;
  RETURN jsonb_build_object('text', 'Não consegui mexer nos cartões agora. Tente de novo em instantes.', 'kb', 'none');
END $$;
