-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_mem_switch_name(p_name text)
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 96)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:96
CREATE OR REPLACE FUNCTION agente.f_mem_switch_name(p_name text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente', 'public' AS $$
  SELECT CASE
    WHEN f_norm(p_name) IN ('mem enabled', 'memoria', 'memorias', 'mem', 'lembrar') OR p_name = 'mem_enabled' THEN 'mem_enabled'
    WHEN f_norm(p_name) IN ('offer save enabled', 'oferta', 'oferta de salvar', 'perguntar se salvo', 'salvar', 'offer') OR p_name = 'offer_save_enabled' THEN 'offer_save_enabled'
    WHEN f_norm(p_name) IN ('suggest enabled', 'sugestao', 'sugestoes', 'sugestao diaria', 'suggest') OR p_name = 'suggest_enabled' THEN 'suggest_enabled'
  END
$$;
