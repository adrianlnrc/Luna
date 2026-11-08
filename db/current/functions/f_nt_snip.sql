-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_nt_snip(p text, p_len int)
-- Origem da definicao atual: 016_listas_notas.sql (linha 327)
-- Definicoes (migracao:linha), da mais antiga a atual: 016_listas_notas.sql:327
CREATE OR REPLACE FUNCTION f_nt_snip(p text, p_len int) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT CASE WHEN length(regexp_replace(COALESCE(p, ''), '[[:space:]]+', ' ', 'g')) > p_len
              THEN left(regexp_replace(COALESCE(p, ''), '[[:space:]]+', ' ', 'g'), p_len - 3) || '...'
              ELSE regexp_replace(COALESCE(p, ''), '[[:space:]]+', ' ', 'g') END
$$;
