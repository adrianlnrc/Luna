-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ls_disp(p text)
-- Origem da definicao atual: 016_listas_notas.sql (linha 59)
-- Definicoes (migracao:linha), da mais antiga a atual: 016_listas_notas.sql:59
CREATE OR REPLACE FUNCTION f_ls_disp(p text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT upper(left(btrim(COALESCE(p, '')), 1)) || substr(btrim(COALESCE(p, '')), 2)
$$;
