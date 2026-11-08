-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ai_log(p_user bigint, p_kind text, p_model text, p_in integer, p_out integer, p_est boolean)
-- Origem da definicao atual: 028_custo_ia_anuais.sql (linha 41)
-- Definicoes (migracao:linha), da mais antiga a atual: 028_custo_ia_anuais.sql:41
CREATE OR REPLACE FUNCTION f_ai_log(p_user bigint, p_kind text, p_model text, p_in integer, p_out integer, p_est boolean DEFAULT false)
RETURNS bigint LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE tz text; v_id bigint;
BEGIN
  IF p_user IS NULL OR (p_in IS NULL AND p_out IS NULL) THEN RETURN NULL; END IF;
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  IF NOT FOUND THEN RETURN NULL; END IF;
  INSERT INTO ai_usage (user_id, day, kind, model, tokens_in, tokens_out, estimated)
  VALUES (p_user, (now() AT TIME ZONE coalesce(tz, 'America/Sao_Paulo'))::date, coalesce(nullif(btrim(p_kind), ''), 'texto'),
          coalesce(nullif(btrim(p_model), ''), 'desconhecido'), greatest(coalesce(p_in, 0), 0), greatest(coalesce(p_out, 0), 0), coalesce(p_est, false))
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;
