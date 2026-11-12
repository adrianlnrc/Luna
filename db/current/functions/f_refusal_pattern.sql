-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_refusal_pattern(p_user bigint)
-- Origem da definicao atual: 040_assessor_runs.sql (linha 152)
-- Definicoes (migracao:linha), da mais antiga a atual: 040_assessor_runs.sql:152
CREATE OR REPLACE FUNCTION f_refusal_pattern(p_user bigint) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = agente, public AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('ferramenta', ferramenta, 'acao', acao, 'recusas', n, 'exemplos', ex)), '[]'::jsonb) FROM (
    SELECT ferramenta, acao, count(*) AS n, jsonb_agg(left(resumo, 100) ORDER BY id DESC) AS ex
      FROM pending_actions
     WHERE user_id = p_user AND status = 'cancelada' AND origem IN ('agente', 'vigia', 'revisao') AND criado_em > now() - interval '30 days'
     GROUP BY ferramenta, acao HAVING count(*) >= 3) x
$$;
