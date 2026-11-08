-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_proj_insert_tasks(p_user bigint, p_pid bigint, p_tasks jsonb)
-- Origem da definicao atual: 017_projetos.sql (linha 119)
-- Definicoes (migracao:linha), da mais antiga a atual: 017_projetos.sql:119
CREATE OR REPLACE FUNCTION f_proj_insert_tasks(p_user bigint, p_pid bigint, p_tasks jsonb) RETURNS integer
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE x jsonb; n integer := 0; k integer; d date;
BEGIN
  FOR x IN SELECT * FROM jsonb_array_elements(p_tasks) LOOP
    BEGIN d := nullif(x->>'due', '')::date; EXCEPTION WHEN others THEN d := NULL; END;
    INSERT INTO project_tasks (project_id, user_id, title, norm_title, due_date)
    VALUES (p_pid, p_user, left(btrim(x->>'title'), 200), f_norm(left(btrim(x->>'title'), 200)), d)
    ON CONFLICT (project_id, norm_title) DO NOTHING;
    GET DIAGNOSTICS k = ROW_COUNT;
    n := n + k;
  END LOOP;
  RETURN n;
END $$;
