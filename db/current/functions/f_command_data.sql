-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_command_data(p_user bigint)
-- Origem da definicao atual: 028_custo_ia_anuais.sql (linha 140) [dentro de bloco DO/EXECUTE, criacao condicional]
-- Definicoes (migracao:linha), da mais antiga a atual: 028_custo_ia_anuais.sql:140
CREATE FUNCTION agente.f_command_data(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $b$
BEGIN
  RETURN agente.f_command_data_pre_m4(p_user) || jsonb_build_object('custo', agente.f_ai_cost_text(p_user));
END $b$;
