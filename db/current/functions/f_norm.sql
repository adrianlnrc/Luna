-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_norm(p text)
-- Origem da definicao atual: 008_financas.sql (linha 67)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:67
CREATE OR REPLACE FUNCTION f_norm(p text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path = agente, public AS $$
  SELECT btrim(regexp_replace(lower(regexp_replace(translate(coalesce(p, ''),
    'ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇç',
    'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCc'), '[^[:alnum:] ]', '', 'g')), '[ ]+', ' ', 'g'))
$$;
