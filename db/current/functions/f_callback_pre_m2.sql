-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_callback_pre_m2(p_user bigint, p_data text)
-- Origem da definicao atual: 024_ciclo_correcoes.sql (linha 148)
-- Definicoes (migracao:linha), da mais antiga a atual: 024_ciclo_correcoes.sql:148
-- Renomeada de f_callback para f_callback_pre_m2 em 026_recibo_alertas.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_callback_pre_m2).
CREATE OR REPLACE FUNCTION agente.f_callback(p_user bigint, p_data text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
BEGIN
  IF split_part(p_data, ':', 1) IN ('spdel', 'spkeep') THEN
    RETURN f_supply_cb(p_user, p_data);
  END IF;
  RETURN f_callback_pre_f6(p_user, p_data);
END $function$;
