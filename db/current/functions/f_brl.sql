-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_brl(p numeric)
-- Origem da definicao atual: 008_financas.sql (linha 73)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:73
CREATE OR REPLACE FUNCTION f_brl(p numeric) RETURNS text LANGUAGE sql IMMUTABLE SET search_path = agente, public AS $$
  SELECT 'R$ ' || translate(to_char(coalesce(p, 0), 'FM999,999,999,990.00'), ',.', '.,')
$$;
