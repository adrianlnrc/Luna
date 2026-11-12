-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_runs_expire(p_user bigint)
-- Origem da definicao atual: 040_assessor_runs.sql (linha 101)
-- Definicoes (migracao:linha), da mais antiga a atual: 040_assessor_runs.sql:101
CREATE OR REPLACE FUNCTION f_runs_expire(p_user bigint) RETURNS integer
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE n int;
BEGIN
  UPDATE pending_actions SET status = 'expirada', resolvido_em = now()
   WHERE user_id = p_user AND status = 'pendente' AND expira_em <= now();
  WITH upd AS (
    UPDATE assessor_runs r SET resultado = 'ignorado'
     WHERE r.user_id = p_user AND r.resultado = 'respondido' AND r.propostas > 0 AND r.criado_em < now() - interval '24 hours'
       AND NOT EXISTS (SELECT 1 FROM pending_actions pa WHERE pa.run_id = r.id AND pa.status IN ('pendente', 'executando', 'executada'))
    RETURNING 1)
  SELECT count(*) INTO n FROM upd;
  RETURN n;
END $$;
