-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ls_find(p_user bigint, p_name text)
-- Origem da definicao atual: 016_listas_notas.sql (linha 65)
-- Definicoes (migracao:linha), da mais antiga a atual: 016_listas_notas.sql:65
CREATE OR REPLACE FUNCTION f_ls_find(p_user bigint, p_name text) RETURNS bigint
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE n text := f_norm(f_ls_clean(p_name)); v bigint; k int;
BEGIN
  IF n = '' THEN RETURN NULL; END IF;
  SELECT id INTO v FROM lists WHERE user_id = p_user AND name_norm = n ORDER BY id LIMIT 1;
  IF v IS NOT NULL THEN RETURN v; END IF;
  SELECT id INTO v FROM lists WHERE user_id = p_user
    AND regexp_replace(name_norm, 's$', '') = regexp_replace(n, 's$', '') ORDER BY id LIMIT 1;
  IF v IS NOT NULL THEN RETURN v; END IF;
  SELECT count(*), min(id) INTO k, v FROM lists
   WHERE user_id = p_user AND length(n) >= 3
     AND (name_norm LIKE '%' || n || '%' OR (length(name_norm) >= 3 AND n LIKE '%' || name_norm || '%'));
  IF k = 1 THEN RETURN v; END IF;
  RETURN NULL;
END $$;
