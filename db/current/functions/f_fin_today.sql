-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_today(p_user bigint)
-- Origem da definicao atual: 008_financas.sql (linha 84)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:84
CREATE OR REPLACE FUNCTION f_fin_today(p_user bigint) RETURNS date LANGUAGE sql STABLE SET search_path = agente, public AS $$
  SELECT (now() AT TIME ZONE timezone)::date FROM users WHERE id = p_user
$$;
