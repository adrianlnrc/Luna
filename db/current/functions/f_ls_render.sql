-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ls_render(p_list bigint)
-- Origem da definicao atual: 016_listas_notas.sql (linha 103)
-- Definicoes (migracao:linha), da mais antiga a atual: 016_listas_notas.sql:103
CREATE OR REPLACE FUNCTION f_ls_render(p_list bigint) RETURNS text
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE l lists%ROWTYPE; tot int; pend int; body text; nl text := chr(10);
BEGIN
  SELECT * INTO l FROM lists WHERE id = p_list;
  IF NOT FOUND THEN RETURN ''; END IF;
  SELECT count(*), count(*) FILTER (WHERE NOT done) INTO tot, pend FROM list_items WHERE list_id = p_list;
  IF tot = 0 THEN RETURN 'Lista ' || l.name || ': vazia.'; END IF;
  SELECT string_agg(CASE WHEN done THEN '☑ ' ELSE '☐ ' END || name, nl ORDER BY done, id)
    INTO body FROM (SELECT * FROM list_items WHERE list_id = p_list ORDER BY done, id LIMIT 80) s;
  RETURN 'Lista ' || l.name || ' (' || pend || CASE WHEN pend = 1 THEN ' pendente' ELSE ' pendentes' END || ' de ' || tot || '):' || nl || body
    || CASE WHEN tot > 80 THEN nl || '... e mais ' || (tot - 80) || '.' ELSE '' END;
END $$;
