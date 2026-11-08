-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ls_item_find(p_list bigint, p_name text, p_strict boolean)
-- Origem da definicao atual: 016_listas_notas.sql (linha 84)
-- Definicoes (migracao:linha), da mais antiga a atual: 016_listas_notas.sql:84
CREATE OR REPLACE FUNCTION f_ls_item_find(p_list bigint, p_name text, p_strict boolean) RETURNS bigint
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE n text := f_norm(p_name); v bigint; k int;
BEGIN
  IF n = '' THEN RETURN NULL; END IF;
  SELECT id INTO v FROM list_items WHERE list_id = p_list AND name_norm = n ORDER BY done, id LIMIT 1;
  IF v IS NOT NULL THEN RETURN v; END IF;
  SELECT id INTO v FROM list_items WHERE list_id = p_list
    AND regexp_replace(name_norm, 's$', '') = regexp_replace(n, 's$', '') ORDER BY done, id LIMIT 1;
  IF v IS NOT NULL THEN RETURN v; END IF;
  IF p_strict OR length(n) < 3 THEN RETURN NULL; END IF;
  SELECT count(*), min(id) INTO k, v FROM list_items
   WHERE list_id = p_list AND (name_norm LIKE '%' || n || '%' OR (length(name_norm) >= 3 AND n LIKE '%' || name_norm || '%'));
  IF k = 1 THEN RETURN v; END IF;
  IF k > 1 THEN RETURN 0; END IF;
  RETURN NULL;
END $$;
