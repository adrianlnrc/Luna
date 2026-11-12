-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_user_purge(p_user bigint)
-- Origem da definicao atual: 040_assessor_runs.sql (linha 227)
-- Definicoes (migracao:linha), da mais antiga a atual: 040_assessor_runs.sql:227
CREATE OR REPLACE FUNCTION f_user_purge(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE r record; pend text[]; nxt text[]; pass int := 0; n bigint; total bigint := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user) THEN RETURN jsonb_build_object('ok', false, 'error', 'usuario'); END IF;
  DELETE FROM contact_group_members m USING contact_groups g WHERE g.id = m.group_id AND g.user_id = p_user;
  DELETE FROM fin_goal_deposits d USING fin_goals g WHERE g.id = d.goal_id AND g.user_id = p_user;
  SELECT array_agg(tabela) INTO pend FROM f_user_tables();
  -- as chaves estrangeiras entre tabelas do usuario nao tem todas ON DELETE CASCADE: repete ate esvaziar
  WHILE coalesce(array_length(pend, 1), 0) > 0 AND pass < 12 LOOP
    pass := pass + 1; nxt := '{}';
    FOR r IN SELECT unnest(pend) AS tabela LOOP
      BEGIN
        EXECUTE format('DELETE FROM agente.%I WHERE user_id = $1', r.tabela) USING p_user;
        GET DIAGNOSTICS n = ROW_COUNT; total := total + n;
      EXCEPTION WHEN foreign_key_violation THEN nxt := nxt || r.tabela;
      END;
    END LOOP;
    pend := nxt;
  END LOOP;
  IF coalesce(array_length(pend, 1), 0) > 0 THEN
    RAISE EXCEPTION 'f_user_purge: nao consegui apagar %', pend;
  END IF;
  DELETE FROM users WHERE id = p_user;
  RETURN jsonb_build_object('ok', true, 'linhas', total);
END $$;
