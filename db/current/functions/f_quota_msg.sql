-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_quota_msg(p_user bigint)
-- Origem da definicao atual: 040_assessor_runs.sql (linha 40)
-- Definicoes (migracao:linha), da mais antiga a atual: 040_assessor_runs.sql:40
CREATE OR REPLACE FUNCTION f_quota_msg(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE v_msgs int; v_lim int;
BEGIN
  INSERT INTO usage_daily (user_id, dia, msgs) VALUES (p_user, f_fin_today(p_user), 1)
  ON CONFLICT (user_id, dia) DO UPDATE SET msgs = usage_daily.msgs + 1 RETURNING msgs INTO v_msgs;
  SELECT p.msgs_dia INTO v_lim FROM plans p JOIN users u ON u.plan_id = p.id WHERE u.id = p_user;
  RETURN jsonb_build_object('ok', v_msgs <= v_lim, 'msgs', v_msgs, 'limite', v_lim);
END $$;
