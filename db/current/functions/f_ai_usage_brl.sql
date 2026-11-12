-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ai_usage_brl(u ai_usage)
-- Origem da definicao atual: 040_assessor_runs.sql (linha 18)
-- Definicoes (migracao:linha), da mais antiga a atual: 040_assessor_runs.sql:18
CREATE OR REPLACE FUNCTION f_ai_usage_brl(u ai_usage) RETURNS numeric
LANGUAGE sql STABLE SET search_path = agente, public AS $$
  SELECT (coalesce(u.tokens_in * p.usd_per_1m_in + u.tokens_out * p.usd_per_1m_out, 0) / 1000000.0 + coalesce(u.extra_usd, 0))
         * coalesce(p.usd_brl, (SELECT max(usd_brl) FROM ai_pricing), 5.5)
    FROM (SELECT 1) one LEFT JOIN ai_pricing p ON p.model = u.model
$$;
