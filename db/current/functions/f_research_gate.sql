-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_research_gate(p_user bigint)
-- Origem da definicao atual: 029_pesquisa.sql (linha 53)
-- Definicoes (migracao:linha), da mais antiga a atual: 029_pesquisa.sql:53
CREATE OR REPLACE FUNCTION agente.f_research_gate(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE n int; oldest timestamptz; tz text; uid bigint;
BEGIN
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  IF tz IS NULL THEN RETURN jsonb_build_object('ok', false, 'wait_s', 0, 'error', 'usuario nao encontrado'); END IF;
  PERFORM pg_advisory_xact_lock(hashtext('research:' || p_user::text));
  SELECT count(*), min(created_at) INTO n, oldest FROM ai_usage
   WHERE user_id = p_user AND kind = 'pesquisa' AND created_at > now() - interval '1 minute';
  IF n >= 3 THEN
    RETURN jsonb_build_object('ok', false, 'wait_s', greatest(1, ceil(extract(epoch FROM (oldest + interval '1 minute' - now())))::int));
  END IF;
  INSERT INTO ai_usage (user_id, day, kind, tokens_in, tokens_out, estimated, extra_usd)
  VALUES (p_user, (now() AT TIME ZONE tz)::date, 'pesquisa', 0, 0, true, 0) RETURNING id INTO uid;
  RETURN jsonb_build_object('ok', true, 'usage_id', uid);
END $$;
