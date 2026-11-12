-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_run_result(p_user bigint, p_run bigint, p_resultado text)
-- Origem da definicao atual: 040_assessor_runs.sql (linha 84)
-- Definicoes (migracao:linha), da mais antiga a atual: 040_assessor_runs.sql:84
CREATE OR REPLACE FUNCTION f_run_result(p_user bigint, p_run bigint, p_resultado text) RETURNS text
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE v_cur text; v_new text;
BEGIN
  SELECT resultado INTO v_cur FROM assessor_runs WHERE id = p_run AND user_id = p_user;
  IF NOT FOUND OR p_resultado NOT IN ('respondido', 'acao_confirmada', 'aceito', 'ignorado', 'rejeitado', 'erro') THEN RETURN v_cur; END IF;
  v_new := CASE
    WHEN p_resultado = 'acao_confirmada' THEN 'acao_confirmada'
    WHEN v_cur = 'acao_confirmada' THEN v_cur
    WHEN p_resultado = 'aceito' THEN 'aceito'
    WHEN v_cur = 'aceito' THEN v_cur
    ELSE p_resultado END;
  UPDATE assessor_runs SET resultado = v_new WHERE id = p_run AND user_id = p_user;
  RETURN v_new;
END $$;
