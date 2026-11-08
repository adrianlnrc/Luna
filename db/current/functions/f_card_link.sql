-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_card_link(p_user bigint, p jsonb, p_res jsonb)
-- Origem da definicao atual: 013_extras.sql (linha 584)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:584
CREATE OR REPLACE FUNCTION f_card_link(p_user bigint, p jsonb, p_res jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE hint text := nullif(btrim(coalesce(p->>'card', '')), ''); v_rid bigint; cid bigint; c fin_cards%ROWTYPE; e fin_entries%ROWTYPE; n integer; open_amt numeric; s date; en date;
BEGIN
  IF p_res IS NULL OR coalesce(p->>'kind', 'expense') = 'income' OR p_res->>'rid' IS NULL THEN RETURN p_res; END IF;
  v_rid := (p_res->>'rid')::bigint;
  IF v_rid IS NULL OR v_rid <= 0 THEN RETURN p_res; END IF;
  SELECT * INTO e FROM fin_entries WHERE id = v_rid AND user_id = p_user;
  IF NOT FOUND OR e.kind <> 'expense' OR e.status NOT IN ('paid','draft') THEN RETURN p_res; END IF;
  IF hint IS NULL THEN
    IF coalesce(p->>'method', '') <> 'credito' THEN RETURN p_res; END IF;
    SELECT count(*) INTO n FROM fin_cards WHERE user_id = p_user AND active;
    IF n <> 1 THEN RETURN p_res; END IF;
    SELECT id INTO cid FROM fin_cards WHERE user_id = p_user AND active;
  ELSE
    cid := f_card_find(p_user, hint);
    IF cid IS NULL THEN
      RETURN jsonb_set(p_res, '{text}', to_jsonb((p_res->>'text') || E'\nNão achei o cartão "' || hint || '"; lancei sem ligar a um cartão. Cadastre com: "cartão ' || hint || ' fecha dia 10 vence dia 17 limite 5000".'));
    END IF;
  END IF;
  SELECT * INTO c FROM fin_cards WHERE id = cid;
  UPDATE fin_entries SET card_id = cid, method = 'credito'
   WHERE user_id = p_user AND (id = v_rid OR (e.series_id IS NOT NULL AND series_id = e.series_id));
  s := f_card_close_le(c.closing_day, f_fin_today(p_user)); en := f_card_close_gt(c.closing_day, f_fin_today(p_user));
  open_amt := f_card_sum(cid, s, en);
  RETURN jsonb_set(p_res, '{text}', to_jsonb((p_res->>'text') || E'\nNo cartão ' || c.name || '. Fatura aberta: ' || f_brl(open_amt) || ' (fecha ' || to_char(en, 'DD/MM') || ').'));
EXCEPTION WHEN others THEN
  RAISE WARNING 'f_card_link: %', SQLERRM;
  RETURN p_res;
END $$;
