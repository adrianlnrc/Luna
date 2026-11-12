-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_pending_finish(p_user bigint, p_id bigint, p_ok boolean, p_resultado jsonb)
-- Origem da definicao atual: 037_assessor_base.sql (linha 168)
-- Definicoes (migracao:linha), da mais antiga a atual: 037_assessor_base.sql:168
CREATE OR REPLACE FUNCTION f_pending_finish(p_user bigint, p_id bigint, p_ok boolean, p_resultado jsonb) RETURNS void
LANGUAGE sql SET search_path = agente, public AS $$
  UPDATE pending_actions SET status = CASE WHEN p_ok THEN 'executada' ELSE 'falhou' END, resultado = p_resultado, resolvido_em = now()
   WHERE id = p_id AND user_id = p_user AND status = 'executando'
$$;
