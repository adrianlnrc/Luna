-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ai_brl(p numeric)
-- Origem da definicao atual: 028_custo_ia_anuais.sql (linha 56)
-- Definicoes (migracao:linha), da mais antiga a atual: 028_custo_ia_anuais.sql:56
CREATE OR REPLACE FUNCTION f_ai_brl(p numeric) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT 'R$ ' || replace(CASE WHEN abs(coalesce(p, 0)) >= 1 THEN to_char(coalesce(p, 0), 'FM999999990.00') ELSE to_char(coalesce(p, 0), 'FM990.0000') END, '.', ',')
$$;
