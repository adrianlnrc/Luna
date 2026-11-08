-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_batch_open(p_user bigint)
-- Origem da definicao atual: 033_acoes_recentes.sql (linha 36)
-- Definicoes (migracao:linha), da mais antiga a atual: 033_acoes_recentes.sql:36
CREATE OR REPLACE FUNCTION agente.f_batch_open(p_user bigint) RETURNS bigint
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE v bigint;
BEGIN
  DELETE FROM recent_actions WHERE created_at < now() - interval '3 days';
  DELETE FROM recent_batches WHERE opened_at < now() - interval '3 days';
  INSERT INTO recent_batches(user_id) VALUES (p_user) RETURNING id INTO v;
  RETURN v;
END $$;
