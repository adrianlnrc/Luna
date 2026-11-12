-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_insight_mode(p_user bigint, p_modo text)
-- Origem da definicao atual: 039_insights.sql (linha 267)
-- Definicoes (migracao:linha), da mais antiga a atual: 039_insights.sql:267
CREATE OR REPLACE FUNCTION f_insight_mode(p_user bigint, p_modo text) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE m text := f_norm(p_modo);
BEGIN
  PERFORM f_insight_prefs(p_user);
  IF m IN ('todos', 'tudo', 'religar', 'reativar') THEN
    UPDATE insight_prefs SET regras_silenciadas = '{}', regras_desligadas = '{}', ignorados_seguidos = 0, atualizado_em = now() WHERE user_id = p_user;
    RETURN jsonb_build_object('ok', true, 'text', 'Voltei a avisar de tudo.');
  END IF;
  IF m NOT IN ('quieto', 'normal', 'atento') THEN
    RETURN jsonb_build_object('ok', false, 'text', 'Os modos são: quieto, normal ou atento.');
  END IF;
  UPDATE insight_prefs SET modo = m, ignorados_seguidos = 0, atualizado_em = now() WHERE user_id = p_user;
  RETURN jsonb_build_object('ok', true, 'modo', m, 'text', CASE m
    WHEN 'quieto' THEN 'Modo quieto: só a revisão da semana.'
    WHEN 'atento' THEN 'Modo atento: até 4 avisos no resumo da manhã e 2 imediatos por dia.'
    ELSE 'Modo normal: até 2 avisos no resumo da manhã e 1 imediato por dia.' END);
END $$;
