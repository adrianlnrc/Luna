-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ls_clean(p text)
-- Origem da definicao atual: 016_listas_notas.sql (linha 53)
-- Definicoes (migracao:linha), da mais antiga a atual: 016_listas_notas.sql:53
CREATE OR REPLACE FUNCTION f_ls_clean(p text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT btrim(regexp_replace(regexp_replace(btrim(COALESCE(p, '')),
    '^((a|o|minha|nossa) )*lista ((de|da|do|dos|das) )?', '', 'i'), '[ ]+', ' ', 'g'))
$$;
