-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_crit_txt(p_user bigint)
-- Origem da definicao atual: 037_assessor_base.sql (linha 372)
-- Definicoes (migracao:linha), da mais antiga a atual: 037_assessor_base.sql:372
CREATE OR REPLACE FUNCTION agente.f_crit_txt(p_user bigint) RETURNS text
LANGUAGE sql STABLE SET search_path TO 'agente', 'public' AS $$
  SELECT CASE WHEN NOT f_mem_sw(p_user, 'mem_enabled') THEN '' ELSE
    coalesce((SELECT string_agg('- ' || texto, E'\n' ORDER BY id) FROM user_memory
               WHERE user_id = p_user AND ativo AND tipo = 'criterio'), '') END
$$;
