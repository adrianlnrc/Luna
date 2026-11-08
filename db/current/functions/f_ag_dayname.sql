-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ag_dayname(p date)
-- Origem da definicao atual: 012_agenda.sql (linha 54)
-- Definicoes (migracao:linha), da mais antiga a atual: 012_agenda.sql:54
CREATE OR REPLACE FUNCTION f_ag_dayname(p date) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente', 'public' AS $$
  SELECT (ARRAY['dom','seg','ter','qua','qui','sex','sáb'])[extract(dow FROM p)::int + 1]
$$;
