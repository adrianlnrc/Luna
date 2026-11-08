-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_mem_switches(p_user bigint)
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 105)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:105
CREATE OR REPLACE FUNCTION agente.f_mem_switches(p_user bigint) RETURNS jsonb
LANGUAGE sql STABLE SET search_path TO 'agente', 'public' AS $$
  SELECT jsonb_build_object('mem_enabled', f_mem_sw(p_user, 'mem_enabled'),
                            'offer_save_enabled', f_mem_sw(p_user, 'offer_save_enabled'),
                            'suggest_enabled', f_mem_sw(p_user, 'suggest_enabled'))
$$;
