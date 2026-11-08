-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_multi_tasks(p_user bigint, p_items jsonb)
-- Origem da definicao atual: 033_acoes_recentes.sql (linha 218)
-- Definicoes (migracao:linha), da mais antiga a atual: 033_acoes_recentes.sql:218
CREATE OR REPLACE FUNCTION agente.f_multi_tasks(p_user bigint, p_items jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE it jsonb; v_lines jsonb := '[]'::jsonb; v_fails jsonb := '[]'::jsonb; v_title text; v_id text;
BEGIN
  FOR it IN SELECT * FROM jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) LOOP
    v_title := coalesce(it->>'title', ''); v_id := coalesce(it->'result'->>'id', '');
    IF v_id <> '' THEN
      PERFORM f_ra_log(p_user, 'task', NULL, v_id, it->>'calendar_key', v_title || CASE WHEN coalesce(it->>'due', '') <> '' THEN ', para ' || to_char((it->>'due')::date, 'DD/MM') ELSE '' END);
      v_lines := v_lines || to_jsonb('Tarefa: ' || v_title || CASE WHEN coalesce(it->>'due', '') <> '' THEN ', para ' || to_char((it->>'due')::date, 'DD/MM') ELSE '' END);
    ELSE
      v_fails := v_fails || to_jsonb('Não consegui criar a tarefa "' || left(v_title, 60) || '"'
                   || CASE WHEN coalesce(it->'result'->>'not_connected', '') = 'true' THEN ' (sua conta do Google Tarefas não está conectada)' ELSE '' END || '.');
    END IF;
  END LOOP;
  RETURN jsonb_build_object('lines', v_lines, 'fails', v_fails);
END $$;
