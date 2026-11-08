-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_card_date(p_y integer, p_m integer, p_d integer)
-- Origem da definicao atual: 013_extras.sql (linha 37)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:37
CREATE OR REPLACE FUNCTION f_card_date(p_y integer, p_m integer, p_d integer) RETURNS date
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT (make_date(p_y, p_m, 1) + (least(p_d, extract(day FROM (make_date(p_y, p_m, 1) + interval '1 month - 1 day'))::int) - 1))::date
$$;
