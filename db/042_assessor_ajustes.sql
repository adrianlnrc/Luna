-- Assessor: ajustes de apoio ao servico. Idempotente. NAO aplicado em producao.
SET search_path = agente, public;

-- Limite de pesquisas na web por usuario (PRD RF-11): 3 por minuto.
-- O servico nao usa f_research_gate (db/029) porque ela grava uma linha em ai_usage sem modelo, o que falha
-- num banco criado do zero (db/028 cria ai_usage.model como NOT NULL). Esta conta a partir das linhas que o
-- proprio servico grava (kind = 'pesquisa').
CREATE OR REPLACE FUNCTION f_search_gate(p_user bigint, p_max integer DEFAULT 3) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM ai_usage WHERE user_id = p_user AND kind = 'pesquisa' AND created_at > now() - interval '1 minute';
  IF n >= p_max THEN
    RETURN jsonb_build_object('ok', false, 'recentes', n,
      'text', 'Você fez ' || n || ' pesquisas no último minuto. Espere um pouco e peça de novo.');
  END IF;
  RETURN jsonb_build_object('ok', true, 'recentes', n);
END $$;
