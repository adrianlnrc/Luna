-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_proj_fmt(p_d date, p_today date)
-- Origem da definicao atual: 017_projetos.sql (linha 44)
-- Definicoes (migracao:linha), da mais antiga a atual: 017_projetos.sql:44
CREATE OR REPLACE FUNCTION f_proj_fmt(p_d date, p_today date) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT CASE WHEN p_d IS NULL THEN '' WHEN extract(year FROM p_d) = extract(year FROM p_today) THEN to_char(p_d, 'DD/MM') ELSE to_char(p_d, 'DD/MM/YYYY') END
$$;
