-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agimp_tasks_mark(p_user bigint, p_ids jsonb)
-- Origem da definicao atual: 032_resumo_enxuto.sql (linha 236)
-- Definicoes (migracao:linha), da mais antiga a atual: 032_resumo_enxuto.sql:236
CREATE OR REPLACE FUNCTION f_agimp_tasks_mark(p_user bigint, p_ids jsonb) RETURNS integer
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE c int;
BEGIN
  UPDATE agenda_tarefas_agendadas SET state = 'created'
   WHERE user_id = p_user AND state = 'scheduled' AND id IN (SELECT (jsonb_array_elements_text(coalesce(p_ids, '[]'::jsonb)))::bigint);
  GET DIAGNOSTICS c = ROW_COUNT;
  RETURN c;
END $$;
