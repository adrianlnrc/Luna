-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ls_msg(p text)
-- Origem da definicao atual: 016_listas_notas.sql (linha 118)
-- Definicoes (migracao:linha), da mais antiga a atual: 016_listas_notas.sql:118
CREATE OR REPLACE FUNCTION f_ls_msg(p text) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT jsonb_build_object('text', p, 'kb', 'none', 'rid', 0)
$$;
