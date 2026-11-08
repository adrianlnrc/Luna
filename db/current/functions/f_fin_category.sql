-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_category(p_user bigint, p jsonb)
-- Origem da definicao atual: 008_financas.sql (linha 593)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:593
CREATE OR REPLACE FUNCTION f_fin_category(p_user bigint, p jsonb) RETURNS jsonb LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE
  act text := p->>'action'; v_kind text := CASE WHEN p->>'kind' = 'income' THEN 'income' ELSE 'expense' END;
  v_name text := btrim(coalesce(nullif(p->>'category', ''), p->>'title', '')); kws text[]; v_id bigint; t text := ''; r record; k integer := 0;
BEGIN
  PERFORM f_fin_seed(p_user);
  IF act = 'category_list' THEN
    FOR r IN SELECT name, kind, budget, keywords FROM fin_categories WHERE user_id = p_user ORDER BY kind DESC, name LOOP
      k := k + 1;
      t := t || E'\n- ' || r.name || CASE WHEN r.kind = 'income' THEN ' (receita)' ELSE '' END ||
           CASE WHEN r.budget IS NOT NULL THEN ', orçamento ' || f_brl(r.budget) ELSE '' END ||
           CASE WHEN array_length(r.keywords, 1) > 0 THEN ' [' || array_to_string(r.keywords[1:4], ', ') || ']' ELSE '' END;
    END LOOP;
    RETURN jsonb_build_object('text', 'Suas categorias:' || t || E'\nPara criar: "cria a categoria Pet com ração e veterinário".', 'kb', 'none');
  END IF;
  IF v_name = '' THEN RETURN jsonb_build_object('text', 'Qual o nome da categoria? Ex.: "cria a categoria Pet com ração e veterinário".', 'kb', 'none'); END IF;
  SELECT coalesce(array_agg(DISTINCT f_norm(x)) FILTER (WHERE f_norm(x) <> ''), '{}') INTO kws FROM unnest(string_to_array(coalesce(p->>'keywords', ''), ',')) x;
  v_id := f_fin_cat_find(p_user, v_kind, v_name, '');
  IF v_id IS NOT NULL AND EXISTS (SELECT 1 FROM fin_categories WHERE id = v_id AND f_norm(name) = f_norm(v_name)) THEN
    UPDATE fin_categories SET keywords = ARRAY(SELECT DISTINCT unnest(keywords || kws)) WHERE id = v_id;
    RETURN jsonb_build_object('text', 'A categoria ' || v_name || ' já existe' || CASE WHEN array_length(kws, 1) > 0 THEN '; acrescentei as palavras-chave: ' || array_to_string(kws, ', ') ELSE '' END || '.', 'kb', 'none');
  END IF;
  INSERT INTO fin_categories (user_id, name, kind, keywords) VALUES (p_user, left(v_name, 60), v_kind, kws) ON CONFLICT DO NOTHING;
  RETURN jsonb_build_object('text', 'Categoria criada: ' || v_name || CASE WHEN array_length(kws, 1) > 0 THEN ' (palavras-chave: ' || array_to_string(kws, ', ') || ')' ELSE '' END ||
    '. Quando um gasto citar essas palavras, eu uso essa categoria.', 'kb', 'none');
END $$;
