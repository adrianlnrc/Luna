-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_callback_pre_f6(p_user bigint, p_data text)
-- Origem da definicao atual: 023_locais_pergunta.sql (linha 210)
-- Definicoes (migracao:linha), da mais antiga a atual: 023_locais_pergunta.sql:210
-- Renomeada de f_callback para f_callback_pre_f6 em 024_ciclo_correcoes.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_callback_pre_f6).
CREATE OR REPLACE FUNCTION f_callback(p_user bigint, p_data text) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
BEGIN
  IF split_part(p_data, ':', 1) IN ('plskip', 'plnever') THEN
    RETURN f_place_cb(p_user, p_data);
  END IF;
  RETURN f_callback_pre_places(p_user, p_data);
END $$;
