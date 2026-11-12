-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_run_close(p_user bigint, p_run bigint, p jsonb)
-- Origem da definicao atual: 040_assessor_runs.sql (linha 58)
-- Definicoes (migracao:linha), da mais antiga a atual: 040_assessor_runs.sql:58
CREATE OR REPLACE FUNCTION f_run_close(p_user bigint, p_run bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE r assessor_runs%ROWTYPE; v_custo numeric; v_mes date := date_trunc('month', f_fin_today(p_user))::date;
        v_analise boolean := coalesce((p->>'analise')::boolean, false); v_web boolean := coalesce((p->>'com_web')::boolean, false);
BEGIN
  SELECT coalesce(sum(f_ai_usage_brl(a)), 0) INTO v_custo FROM ai_usage a WHERE a.run_id = p_run AND a.user_id = p_user;
  UPDATE assessor_runs SET
    modelo = coalesce(p->>'modelo', modelo), passos = coalesce((p->>'passos')::int, passos),
    ferramentas = coalesce((SELECT array_agg(x) FROM jsonb_array_elements_text(p->'ferramentas') x), ferramentas),
    gravacoes = coalesce((p->>'gravacoes')::int, gravacoes), propostas = coalesce((p->>'propostas')::int, propostas),
    com_web = v_web, analise = v_analise, degradado = coalesce((p->>'degradado')::boolean, false),
    limite = p->>'limite', duracao_ms = (p->>'duracao_ms')::int,
    resultado = CASE WHEN p->>'resultado' IN ('respondido', 'acao_confirmada', 'aceito', 'ignorado', 'rejeitado', 'erro')
                     THEN p->>'resultado' ELSE resultado END,
    custo_brl = v_custo
  WHERE id = p_run AND user_id = p_user RETURNING * INTO r;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false); END IF;
  IF v_analise AND r.origem = 'pergunta' AND NOT r.degradado THEN
    INSERT INTO usage_quota (user_id, mes, analises, analises_web) VALUES (p_user, v_mes, 1, CASE WHEN v_web THEN 1 ELSE 0 END)
    ON CONFLICT (user_id, mes) DO UPDATE SET analises = usage_quota.analises + 1,
                                             analises_web = usage_quota.analises_web + CASE WHEN v_web THEN 1 ELSE 0 END;
  END IF;
  RETURN jsonb_build_object('ok', true, 'id', r.id, 'custo_brl', v_custo, 'resultado', r.resultado);
END $$;
