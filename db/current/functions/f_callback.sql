-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_callback(p_user bigint, p_data text)
-- Origem da definicao atual: 033_acoes_recentes.sql (linha 356)
-- Definicoes (migracao:linha), da mais antiga a atual: 033_acoes_recentes.sql:356
CREATE OR REPLACE FUNCTION agente.f_callback(p_user bigint, p_data text) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
BEGIN
  IF split_part(p_data, ':', 1) = 'mu' AND split_part(p_data, ':', 2) ~ '^[0-9]+$' THEN
    RETURN f_batch_undo(p_user, split_part(p_data, ':', 2)::bigint);
  END IF;
  RETURN f_callback_pre_f10(p_user, p_data);
END $$;
