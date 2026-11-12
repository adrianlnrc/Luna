-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_insight_answer(p_user bigint, p_id bigint, p_resp text)
-- Origem da definicao atual: 039_insights.sql (linha 223)
-- Definicoes (migracao:linha), da mais antiga a atual: 039_insights.sql:223
CREATE OR REPLACE FUNCTION f_insight_answer(p_user bigint, p_id bigint, p_resp text) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE l insights_log%ROWTYPE;
BEGIN
  IF p_resp NOT IN ('aceito', 'agora_nao', 'silenciado') THEN RETURN jsonb_build_object('ok', false, 'text', 'Não entendi.'); END IF;
  UPDATE insights_log SET resposta = p_resp, respondido_em = now()
   WHERE id = p_id AND user_id = p_user AND (resposta IS NULL OR resposta = 'ignorado') RETURNING * INTO l;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'text', 'Esse aviso já foi respondido.'); END IF;
  PERFORM f_insight_prefs(p_user);
  UPDATE insight_prefs SET ignorados_seguidos = 0, atualizado_em = now(),
         regras_silenciadas = CASE WHEN p_resp = 'silenciado' AND NOT l.regra = ANY (regras_silenciadas)
                                   THEN regras_silenciadas || l.regra ELSE regras_silenciadas END
   WHERE user_id = p_user;
  RETURN jsonb_build_object('ok', true, 'regra', l.regra, 'resposta', p_resp, 'acao', l.acao,
    'text', CASE p_resp WHEN 'silenciado' THEN 'Combinado, não aviso mais sobre isso. Para voltar, diga "volta a me avisar de tudo".'
                        WHEN 'agora_nao' THEN 'Tudo bem.' ELSE '' END);
END $$;
