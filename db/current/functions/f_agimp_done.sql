-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agimp_done(p_user bigint, p_id bigint, p_res jsonb)
-- Origem da definicao atual: 032_resumo_enxuto.sql (linha 201)
-- Definicoes (migracao:linha), da mais antiga a atual: 031_agenda_import.sql:201, 032_resumo_enxuto.sql:201
CREATE OR REPLACE FUNCTION f_agimp_done(p_user bigint, p_id bigint, p_res jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE eo int := coalesce((p_res->>'events_ok')::int, 0); ef int := coalesce((p_res->>'events_fail')::int, 0);
        tko int := coalesce((p_res->>'tasks_ok')::int, 0); tkf int := coalesce((p_res->>'tasks_fail')::int, 0); v text; errs text; sch int;
BEGIN
  SELECT count(*) INTO sch FROM agenda_tarefas_agendadas WHERE draft_id = p_id AND user_id = p_user AND state = 'scheduled';
  IF eo + tko + sch = 0 OR (eo + tko = 0 AND ef + tkf > 0) THEN
    DELETE FROM agenda_tarefas_agendadas WHERE draft_id = p_id AND user_id = p_user AND state = 'scheduled';
    UPDATE agenda_import SET state = 'open', result = p_res WHERE id = p_id AND user_id = p_user AND state = 'running';
    SELECT string_agg('- ' || left(x, 120), E'\n') INTO errs FROM (SELECT jsonb_array_elements_text(coalesce(p_res->'errors', '[]'::jsonb)) AS x LIMIT 3) q;
    RETURN jsonb_build_object('text', 'Não consegui criar nada no seu Google agora.' || CASE WHEN coalesce(errs, '') <> '' THEN E'\n' || errs ELSE '' END || E'\nToque em Criar tudo para tentar de novo.', 'kb', 'agimp', 'rid', p_id);
  END IF;
  UPDATE agenda_import SET state = 'done', result = p_res, done_at = now() WHERE id = p_id AND user_id = p_user;
  v := 'Pronto! Criei ' || eo || ' compromisso(s) no Google Agenda e ' || tko || ' tarefa(s) no Google Tarefas hoje.';
  IF sch > 0 THEN v := v || E'\nGuardei ' || sch || ' tarefa(s) de outros dias: cada uma aparece no Google Tarefas na manhã do dia dela.'; END IF;
  IF ef + tkf > 0 THEN
    SELECT string_agg('- ' || left(x, 120), E'\n') INTO errs FROM (SELECT jsonb_array_elements_text(coalesce(p_res->'errors', '[]'::jsonb)) AS x LIMIT 3) q;
    v := v || E'\nNão consegui criar ' || (ef + tkf) || ' item(ns).' || CASE WHEN coalesce(errs, '') <> '' THEN E'\n' || errs ELSE '' END;
  END IF;
  v := v || E'\nSe algo ficou errado, me diga que eu ajusto.';
  RETURN jsonb_build_object('text', v, 'kb', 'none', 'rid', 0);
END $$;
