-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agimp_dow(p_d date)
-- Origem da definicao atual: 031_agenda_import.sql (linha 23)
-- Definicoes (migracao:linha), da mais antiga a atual: 031_agenda_import.sql:23
CREATE OR REPLACE FUNCTION f_agimp_dow(p_d date) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT (ARRAY['Domingo','Segunda','Terça','Quarta','Quinta','Sexta','Sábado'])[extract(dow FROM p_d)::int + 1]
$$;
