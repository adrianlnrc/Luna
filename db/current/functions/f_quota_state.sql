-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_quota_state(p_user bigint)
-- Origem da definicao atual: 040_assessor_runs.sql (linha 26)
-- Definicoes (migracao:linha), da mais antiga a atual: 040_assessor_runs.sql:26
CREATE OR REPLACE FUNCTION f_quota_state(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE pl plans%ROWTYPE; q usage_quota%ROWTYPE; v_mes date := date_trunc('month', f_fin_today(p_user))::date; v_msgs int;
BEGIN
  SELECT p.* INTO pl FROM plans p JOIN users u ON u.plan_id = p.id WHERE u.id = p_user;
  SELECT * INTO q FROM usage_quota WHERE user_id = p_user AND mes = v_mes;
  SELECT msgs INTO v_msgs FROM usage_daily WHERE user_id = p_user AND dia = f_fin_today(p_user);
  RETURN jsonb_build_object('mes', v_mes, 'analises', coalesce(q.analises, 0), 'analises_web', coalesce(q.analises_web, 0),
    'limite_analises', pl.analises_mes, 'limite_web', pl.analises_web_mes, 'msgs_hoje', coalesce(v_msgs, 0), 'limite_msgs', pl.msgs_dia,
    'tem_analise', coalesce(q.analises, 0) < pl.analises_mes,
    'tem_web', coalesce(q.analises, 0) < pl.analises_mes AND coalesce(q.analises_web, 0) < pl.analises_web_mes);
END $$;
