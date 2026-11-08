-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agimp_tasks_due(p_user bigint)
-- Origem da definicao atual: 032_resumo_enxuto.sql (linha 225)
-- Definicoes (migracao:linha), da mais antiga a atual: 032_resumo_enxuto.sql:225
CREATE OR REPLACE FUNCTION f_agimp_tasks_due(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE v_tz text; v_today date;
BEGIN
  SELECT coalesce(timezone, 'America/Sao_Paulo') INTO v_tz FROM users WHERE id = p_user;
  v_today := (now() AT TIME ZONE coalesce(v_tz, 'America/Sao_Paulo'))::date;
  RETURN jsonb_build_object('items', coalesce((SELECT jsonb_agg(jsonb_build_object('id', t.id, 'title', CASE WHEN t.urgent THEN '🔴 ' ELSE '' END || t.title, 'due', t.due) ORDER BY t.due, t.id)
    FROM agenda_tarefas_agendadas t WHERE t.user_id = p_user AND t.state = 'scheduled' AND t.due <= v_today), '[]'::jsonb));
END $$;
