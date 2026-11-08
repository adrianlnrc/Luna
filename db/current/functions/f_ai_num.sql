-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ai_num(p numeric)
-- Origem da definicao atual: 028_custo_ia_anuais.sql (linha 61)
-- Definicoes (migracao:linha), da mais antiga a atual: 028_custo_ia_anuais.sql:61
CREATE OR REPLACE FUNCTION f_ai_num(p numeric) RETURNS text
LANGUAGE sql IMMUTABLE AS $$ SELECT replace(to_char(coalesce(p, 0), 'FM999,999,999,990'), ',', '.') $$;
