-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ai_log_run(p_user bigint, p_run bigint, p_kind text, p_model text, p_in integer, p_out integer, p_extra_usd numeric, p_est boolean)
-- Origem da definicao atual: 040_assessor_runs.sql (linha 5)
-- Definicoes (migracao:linha), da mais antiga a atual: 040_assessor_runs.sql:5
CREATE OR REPLACE FUNCTION f_ai_log_run(p_user bigint, p_run bigint, p_kind text, p_model text, p_in integer, p_out integer,
                                        p_extra_usd numeric DEFAULT 0, p_est boolean DEFAULT false) RETURNS bigint
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE v_id bigint;
BEGIN
  INSERT INTO ai_usage (user_id, day, kind, model, tokens_in, tokens_out, estimated, extra_usd, run_id)
  VALUES (p_user, f_fin_today(p_user), coalesce(nullif(p_kind, ''), 'texto'), coalesce(p_model, ''),
          greatest(coalesce(p_in, 0), 0), greatest(coalesce(p_out, 0), 0), coalesce(p_est, false), coalesce(p_extra_usd, 0), p_run)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;
