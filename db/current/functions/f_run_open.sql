-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_run_open(p_user bigint, p_origem text, p_canal text)
-- Origem da definicao atual: 040_assessor_runs.sql (linha 51)
-- Definicoes (migracao:linha), da mais antiga a atual: 040_assessor_runs.sql:51
CREATE OR REPLACE FUNCTION f_run_open(p_user bigint, p_origem text, p_canal text DEFAULT 'telegram') RETURNS bigint
LANGUAGE sql SET search_path = agente, public AS $$
  INSERT INTO assessor_runs (user_id, origem, canal) VALUES (p_user, p_origem, coalesce(nullif(p_canal, ''), 'telegram')) RETURNING id
$$;
