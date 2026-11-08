-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_proj_resolve(p_user bigint, p_name text)
-- Origem da definicao atual: 017_projetos.sql (linha 60)
-- Definicoes (migracao:linha), da mais antiga a atual: 017_projetos.sql:60
CREATE OR REPLACE FUNCTION f_proj_resolve(p_user bigint, p_name text) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE q text := coalesce(f_norm(p_name), ''); toks text[]; ids bigint[]; n integer; lst text; v_name text;
BEGIN
  SELECT array_agg(t) INTO toks FROM (
    SELECT regexp_replace(x, '[^a-z0-9]', '', 'g') AS t FROM unnest(string_to_array(q, ' ')) x) s
   WHERE t <> '' AND t NOT IN ('o','a','os','as','de','do','da','dos','das','projeto','projetos','no','na','em','pro','pra','para','meu','minha','um','uma');
  IF toks IS NULL THEN
    SELECT array_agg(id ORDER BY created_at) INTO ids FROM projects WHERE user_id = p_user;
    n := coalesce(cardinality(ids), 0);
    IF n = 0 THEN RETURN jsonb_build_object('err', 'Você ainda não tem projetos. Ex.: "novo projeto: mudança do escritório, prazo 30/09".'); END IF;
    IF n = 1 THEN SELECT name INTO v_name FROM projects WHERE id = ids[1]; RETURN jsonb_build_object('id', ids[1], 'name', v_name); END IF;
    SELECT string_agg(name, ', ' ORDER BY created_at) INTO lst FROM projects WHERE user_id = p_user;
    RETURN jsonb_build_object('err', 'Qual projeto? Os seus: ' || lst || '.');
  END IF;
  SELECT id, name INTO n, v_name FROM projects WHERE user_id = p_user AND norm_name = q;
  IF FOUND THEN RETURN jsonb_build_object('id', n, 'name', v_name); END IF;
  SELECT array_agg(id ORDER BY created_at) INTO ids FROM projects
   WHERE user_id = p_user AND (SELECT bool_and(norm_name LIKE '%' || x || '%') FROM unnest(toks) x);
  n := coalesce(cardinality(ids), 0);
  IF n = 1 THEN SELECT name INTO v_name FROM projects WHERE id = ids[1]; RETURN jsonb_build_object('id', ids[1], 'name', v_name); END IF;
  IF n > 1 THEN
    SELECT string_agg(name, ', ' ORDER BY created_at) INTO lst FROM projects WHERE id = ANY(ids);
    RETURN jsonb_build_object('err', 'Achei mais de um projeto parecido: ' || lst || '. Qual deles?');
  END IF;
  SELECT string_agg(name, ', ' ORDER BY created_at) INTO lst FROM projects WHERE user_id = p_user;
  RETURN jsonb_build_object('err', 'Não achei o projeto "' || btrim(p_name) || '".' || CASE WHEN lst IS NULL THEN ' Você ainda não tem projetos.' ELSE ' Os seus: ' || lst || '.' END);
END $$;
