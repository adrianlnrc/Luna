-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_pending_cancel(p_user bigint, p_id bigint)
-- Origem da definicao atual: 037_assessor_base.sql (linha 174)
-- Definicoes (migracao:linha), da mais antiga a atual: 037_assessor_base.sql:174
CREATE OR REPLACE FUNCTION f_pending_cancel(p_user bigint, p_id bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE v_run bigint;
BEGIN
  UPDATE pending_actions SET status = 'cancelada', resolvido_em = now()
   WHERE id = p_id AND user_id = p_user AND status = 'pendente' RETURNING run_id INTO v_run;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'text', 'Essa proposta já foi resolvida.'); END IF;
  RETURN jsonb_build_object('ok', true, 'run_id', v_run, 'text', 'Ok, não fiz nada.');
END $$;
