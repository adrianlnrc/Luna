-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_place_is_name(p_text text)
-- Origem da definicao atual: 023_locais_pergunta.sql (linha 20)
-- Definicoes (migracao:linha), da mais antiga a atual: 023_locais_pergunta.sql:20
CREATE OR REPLACE FUNCTION f_place_is_name(p_text text) RETURNS boolean
LANGUAGE sql STABLE SET search_path TO 'agente','public' AS $$
  SELECT btrim(coalesce(p_text, '')) <> ''
     AND length(btrim(p_text)) <= 40
     AND btrim(p_text) !~ '[0-9]'
     AND f_norm(p_text) !~ '\y(online|zoom|meet|teams|remoto|telefone)\y';
$$;
