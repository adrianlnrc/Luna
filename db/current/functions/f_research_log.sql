-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_research_log(p_user bigint, p_usage_id bigint, p_model text, p_in int, p_out int, p_searches int, p_estimated boolean)
-- Origem da definicao atual: 029_pesquisa.sql (linha 71)
-- Definicoes (migracao:linha), da mais antiga a atual: 029_pesquisa.sql:71
CREATE OR REPLACE FUNCTION agente.f_research_log(p_user bigint, p_usage_id bigint, p_model text, p_in int, p_out int, p_searches int, p_estimated boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE tz text; d date; fee numeric; pr record; this_usd numeric := 0; priced boolean := false; brl numeric := 5.3420;
        day_usd numeric; mon_usd numeric; unpriced int; this_brl numeric; searches int := greatest(coalesce(p_searches, 0), 0);
BEGIN
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  d := (now() AT TIME ZONE coalesce(tz, 'America/Sao_Paulo'))::date;
  SELECT coalesce(usd_per_call, 0) INTO fee FROM ai_pricing WHERE model = 'tool:web_search';
  fee := coalesce(fee, 0.01);
  SELECT * INTO pr FROM ai_pricing WHERE model = p_model;
  IF FOUND THEN
    priced := true; brl := pr.usd_brl;
    this_usd := (coalesce(p_in, 0) * pr.usd_per_1m_in + coalesce(p_out, 0) * pr.usd_per_1m_out) / 1000000.0;
  END IF;
  this_usd := this_usd + searches * fee;
  IF p_usage_id IS NOT NULL AND EXISTS (SELECT 1 FROM ai_usage WHERE id = p_usage_id AND user_id = p_user) THEN
    UPDATE ai_usage SET model = p_model, tokens_in = coalesce(p_in, 0), tokens_out = coalesce(p_out, 0),
           estimated = coalesce(p_estimated, false), extra_usd = searches * fee WHERE id = p_usage_id;
  ELSE
    INSERT INTO ai_usage (user_id, day, kind, model, tokens_in, tokens_out, estimated, extra_usd)
    VALUES (p_user, d, 'pesquisa', p_model, coalesce(p_in, 0), coalesce(p_out, 0), coalesce(p_estimated, false), searches * fee);
  END IF;
  SELECT coalesce(sum((u.tokens_in * coalesce(p.usd_per_1m_in, 0) + u.tokens_out * coalesce(p.usd_per_1m_out, 0)) / 1000000.0 + u.extra_usd), 0)
    INTO day_usd FROM ai_usage u LEFT JOIN ai_pricing p ON p.model = u.model WHERE u.user_id = p_user AND u.day = d;
  SELECT coalesce(sum((u.tokens_in * coalesce(p.usd_per_1m_in, 0) + u.tokens_out * coalesce(p.usd_per_1m_out, 0)) / 1000000.0 + u.extra_usd), 0)
    INTO mon_usd FROM ai_usage u LEFT JOIN ai_pricing p ON p.model = u.model
   WHERE u.user_id = p_user AND u.day >= date_trunc('month', d)::date AND u.day <= d;
  SELECT count(*) INTO unpriced FROM ai_usage u WHERE u.user_id = p_user AND u.day >= date_trunc('month', d)::date
     AND u.tokens_in + u.tokens_out > 0 AND NOT EXISTS (SELECT 1 FROM ai_pricing p WHERE p.model = u.model);
  RETURN jsonb_build_object('priced', priced, 'model', p_model, 'tokens_in', coalesce(p_in, 0), 'tokens_out', coalesce(p_out, 0),
    'searches', searches, 'search_fee_usd', fee, 'usd_brl', brl,
    'cost_usd', round(this_usd, 6), 'cost_brl', round(this_usd * brl, 4),
    'day_brl', round(day_usd * brl, 4), 'month_brl', round(mon_usd * brl, 4), 'unpriced_rows', unpriced);
END $$;
