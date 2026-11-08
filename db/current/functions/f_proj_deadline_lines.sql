-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_proj_deadline_lines(p_user bigint)
-- Origem da definicao atual: 032_resumo_enxuto.sql (linha 247)
-- Definicoes (migracao:linha), da mais antiga a atual: 032_resumo_enxuto.sql:247
CREATE OR REPLACE FUNCTION f_proj_deadline_lines(p_user bigint) RETURNS text
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE today date := f_fin_today(p_user); t text := ''; r record;
BEGIN
  FOR r IN SELECT pr.name, pr.due_date FROM projects pr
            WHERE pr.user_id = p_user AND pr.due_date IN (today, today + 1)
              AND EXISTS (SELECT 1 FROM project_tasks x WHERE x.project_id = pr.id AND NOT x.done)
            ORDER BY pr.due_date, pr.name LOOP
    t := t || E'\n- Prazo do projeto ' || r.name || ': ' || CASE WHEN r.due_date = today THEN 'hoje' ELSE 'amanhã' END;
  END LOOP;
  RETURN ltrim(t, E'\n');
END $$;
