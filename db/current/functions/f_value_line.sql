-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_value_line(p_user bigint)
-- Origem da definicao atual: 040_assessor_runs.sql (linha 117)
-- Definicoes (migracao:linha), da mais antiga a atual: 040_assessor_runs.sql:117
CREATE OR REPLACE FUNCTION f_value_line(p_user bigint) RETURNS text
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE q jsonb := f_quota_state(p_user); v_ini timestamptz; v_acoes int;
        tz text := (SELECT timezone FROM users WHERE id = p_user);
BEGIN
  v_ini := ((q->>'mes')::date::timestamp AT TIME ZONE coalesce(tz, 'America/Sao_Paulo'));
  SELECT coalesce((SELECT sum(gravacoes) FROM assessor_runs WHERE user_id = p_user AND criado_em >= v_ini), 0)
       + (SELECT count(*) FROM pending_actions WHERE user_id = p_user AND status = 'executada' AND resolvido_em >= v_ini)
    INTO v_acoes;
  RETURN (q->>'analises') || ' de ' || (q->>'limite_analises') || ' análises no mês · ' || v_acoes
         || CASE WHEN v_acoes = 1 THEN ' ação concluída' ELSE ' ações concluídas' END;
END $$;
