-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_insights_pick(p_user bigint, p_events jsonb, p_via text)
-- Origem da definicao atual: 039_insights.sql (linha 186)
-- Definicoes (migracao:linha), da mais antiga a atual: 039_insights.sql:186
CREATE OR REPLACE FUNCTION f_insights_pick(p_user bigint, p_events jsonb, p_via text) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE
  u users%ROWTYPE; p insight_prefs%ROWTYPE; cand jsonb; lim int := 0; x jsonb; out jsonb := '[]'; v_id bigint;
  agora time; hoje_ini timestamptz; ja int;
BEGIN
  SELECT * INTO u FROM users WHERE id = p_user;
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;
  p := f_insight_prefs(p_user);
  IF p_via = 'resumo' THEN
    lim := CASE WHEN p.ignorados_seguidos >= 5 THEN 0 WHEN p.modo = 'quieto' THEN 0 WHEN p.modo = 'atento' THEN 4 ELSE 2 END;
  ELSIF p_via = 'imediato' THEN
    agora := (now() AT TIME ZONE u.timezone)::time;
    IF agora < u.work_start OR agora > u.work_end THEN RETURN '[]'::jsonb; END IF;
    hoje_ini := (f_fin_today(p_user)::timestamp AT TIME ZONE u.timezone);
    SELECT count(*) INTO ja FROM insights_log WHERE user_id = p_user AND via = 'imediato' AND enviado_em >= hoje_ini;
    lim := CASE WHEN p.ignorados_seguidos >= 5 THEN 0 WHEN p.modo = 'quieto' THEN 0 WHEN p.modo = 'atento' THEN 2 ELSE 1 END - ja;
  ELSIF p_via = 'revisao' THEN
    lim := 6;
  ELSE
    RETURN '[]'::jsonb;
  END IF;
  IF lim <= 0 THEN RETURN '[]'::jsonb; END IF;
  cand := f_insights(p_user, p_events);
  FOR x IN SELECT * FROM jsonb_array_elements(cand) LOOP
    EXIT WHEN lim <= 0;
    CONTINUE WHEN p_via = 'imediato' AND x->>'prioridade' <> 'alta';
    INSERT INTO insights_log (user_id, chave, regra, prioridade, texto, acao, via)
    VALUES (p_user, x->>'chave', x->>'regra', x->>'prioridade', x->>'texto', NULLIF(x->'acao', 'null'::jsonb), p_via)
    RETURNING id INTO v_id;
    out := out || (x || jsonb_build_object('id', v_id));
    lim := lim - 1;
  END LOOP;
  RETURN out;
END $$;
