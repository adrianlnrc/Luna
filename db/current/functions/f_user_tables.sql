-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_user_tables()
-- Origem da definicao atual: 040_assessor_runs.sql (linha 198)
-- Definicoes (migracao:linha), da mais antiga a atual: 040_assessor_runs.sql:198
CREATE OR REPLACE FUNCTION f_user_tables() RETURNS TABLE (tabela text)
LANGUAGE sql STABLE SET search_path = agente, public AS $$
  SELECT c.table_name::text FROM information_schema.columns c
    JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE'
   WHERE c.table_schema = 'agente' AND c.column_name = 'user_id' ORDER BY 1
$$;
