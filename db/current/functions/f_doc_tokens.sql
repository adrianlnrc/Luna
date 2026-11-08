-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_doc_tokens(p text)
-- Origem da definicao atual: 015_documentos.sql (linha 54)
-- Definicoes (migracao:linha), da mais antiga a atual: 015_documentos.sql:54
CREATE OR REPLACE FUNCTION agente.f_doc_tokens(p text)
RETURNS text[] LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $f$
  SELECT coalesce(array_agg(DISTINCT z.t), ARRAY[]::text[]) FROM (
    SELECT CASE WHEN length(x) > 3 AND right(x, 1) = 's' THEN left(x, length(x) - 1) ELSE x END AS t
    FROM unnest(string_to_array(f_norm(p), ' ')) x
    WHERE length(x) >= 2 AND x NOT IN (
      'de','do','da','dos','das','no','na','nos','nas','em','um','uma','uns','umas','ao','aos','as','os','pra','para','por','com','sem',
      'que','qual','quais','meu','minha','meus','minhas','esse','essa','esses','essas','este','esta','isso','aquele','aquela',
      'me','te','se','vc','voce','manda','mandar','envia','enviar','mostra','mostrar','acha','achar','achei','busca','buscar','procura','procurar',
      'tudo','todo','toda','todos','todas','arquivo','arquivos','documento','documentos','doc','docs','pasta','pastas',
      'foto','fotos','imagem','imagens','print','prints','screenshot','pdf','sobre','link','aqui','ai','ver','tem','ter','onde','cade','quero')
  ) z WHERE z.t <> ''
$f$;
