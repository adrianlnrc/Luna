-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_pending_claim(p_user bigint, p_id bigint)
-- Origem da definicao atual: 037_assessor_base.sql (linha 147)
-- Definicoes (migracao:linha), da mais antiga a atual: 037_assessor_base.sql:147
CREATE OR REPLACE FUNCTION f_pending_claim(p_user bigint, p_id bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE pa pending_actions%ROWTYPE;
BEGIN
  UPDATE pending_actions SET status = 'expirada', resolvido_em = now()
   WHERE id = p_id AND user_id = p_user AND status = 'pendente' AND expira_em <= now();
  UPDATE pending_actions SET status = 'executando'
   WHERE id = p_id AND user_id = p_user AND status = 'pendente' AND expira_em > now()
  RETURNING * INTO pa;
  IF FOUND THEN
    RETURN jsonb_build_object('ok', true, 'id', pa.id, 'ferramenta', pa.ferramenta, 'acao', pa.acao, 'args', pa.args,
                              'nivel', pa.nivel, 'origem', pa.origem, 'run_id', pa.run_id);
  END IF;
  SELECT * INTO pa FROM pending_actions WHERE id = p_id AND user_id = p_user;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'motivo', 'inexistente', 'text', 'Não achei essa proposta.'); END IF;
  RETURN jsonb_build_object('ok', false, 'motivo', pa.status, 'text',
    CASE pa.status WHEN 'expirada' THEN 'Essa proposta expirou. Se ainda quiser, me peça de novo.'
                   WHEN 'cancelada' THEN 'Essa proposta já tinha sido cancelada.'
                   ELSE 'Essa proposta já foi resolvida.' END);
END $$;
