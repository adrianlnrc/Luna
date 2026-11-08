-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_nt_search(p_user bigint, p_q text, p_limit int)
-- Origem da definicao atual: 016_listas_notas.sql (linha 297)
-- Definicoes (migracao:linha), da mais antiga a atual: 016_listas_notas.sql:297
CREATE OR REPLACE FUNCTION f_nt_search(p_user bigint, p_q text, p_limit int)
RETURNS TABLE (id bigint, body text, created_at timestamptz, total bigint)
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE
  stop text[] := ARRAY['de','da','do','das','dos','um','uma','uns','umas','que','qual','quais','sobre','eu','tinha','tenho','anotado','anotei','anota',
    'nota','notas','minha','minhas','meu','meus','para','pra','com','em','no','na','nos','nas','ele','ela','isso','esse','essa','aquilo','foi','era','ver','mostra','mostrar',
    'procura','busca','acha','achar','lembra','sobre','tem','algo','alguma','algum','por','mais','como','ultima','ultimas','ultimo','ultimos','apaga','apagar','exclui','remove','tira'];
  toks text[]; k bigint; minscore int;
BEGIN
  toks := COALESCE(ARRAY(
    SELECT DISTINCT CASE WHEN length(t) >= 6 THEN left(t, length(t) - 2) WHEN length(t) >= 4 THEN rtrim(t, 's') ELSE t END
      FROM unnest(string_to_array(f_norm(p_q), ' ')) AS t
     WHERE length(t) >= 3 AND NOT (t = ANY (stop))), '{}');
  IF cardinality(toks) = 0 THEN
    RETURN QUERY SELECT n.id, n.body, n.created_at, count(*) OVER ()
      FROM notes n WHERE n.user_id = p_user ORDER BY n.created_at DESC, n.id DESC LIMIT p_limit;
    RETURN;
  END IF;
  SELECT count(*) INTO k FROM notes n
   WHERE n.user_id = p_user AND (SELECT count(*) FROM unnest(toks) t WHERE n.body_norm LIKE '%' || t || '%') = cardinality(toks);
  minscore := CASE WHEN k > 0 THEN cardinality(toks) ELSE 1 END;
  RETURN QUERY
    SELECT s.id, s.body, s.created_at, count(*) OVER ()
      FROM (SELECT n.id, n.body, n.created_at,
                   (SELECT count(*) FROM unnest(toks) t WHERE n.body_norm LIKE '%' || t || '%') AS score
              FROM notes n WHERE n.user_id = p_user) s
     WHERE s.score >= minscore
     ORDER BY s.score DESC, s.created_at DESC, s.id DESC LIMIT p_limit;
END $$;
