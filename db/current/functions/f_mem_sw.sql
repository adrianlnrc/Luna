-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_mem_sw(p_user bigint, p_name text)
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 88)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:88
CREATE OR REPLACE FUNCTION agente.f_mem_sw(p_user bigint, p_name text) RETURNS boolean
LANGUAGE sql STABLE SET search_path TO 'agente', 'public' AS $$
  SELECT coalesce((SELECT CASE p_name WHEN 'mem_enabled' THEN s.mem_enabled WHEN 'offer_save_enabled' THEN s.offer_save_enabled
                                      WHEN 'suggest_enabled' THEN s.suggest_enabled END
                     FROM agente.user_switches s WHERE s.user_id = p_user), true)
$$;
