-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_mem_tipo(p text)
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 138)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:138
CREATE OR REPLACE FUNCTION agente.f_mem_tipo(p text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente', 'public' AS $$
  SELECT CASE f_norm(p)
    WHEN 'habito' THEN 'habito' WHEN 'habitos' THEN 'habito'
    WHEN 'preferencia' THEN 'preferencia' WHEN 'preferencias' THEN 'preferencia'
    WHEN 'relacao' THEN 'relacao' WHEN 'relacoes' THEN 'relacao' WHEN 'parentesco' THEN 'relacao'
    ELSE 'fato' END
$$;
