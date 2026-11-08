-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_cat_find(p_user bigint, p_kind text, p_hint text, p_norm text)
-- Origem da definicao atual: 008_financas.sql (linha 133)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:133
CREATE OR REPLACE FUNCTION f_fin_cat_find(p_user bigint, p_kind text, p_hint text, p_norm text) RETURNS bigint
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE v bigint; h text := f_norm(p_hint);
BEGIN
  IF h <> '' THEN
    SELECT id INTO v FROM fin_categories WHERE user_id = p_user AND kind = p_kind AND f_norm(name) = h LIMIT 1;
    IF v IS NOT NULL THEN RETURN v; END IF;
    SELECT c.id INTO v FROM fin_categories c WHERE c.user_id = p_user AND c.kind = p_kind
      AND EXISTS (SELECT 1 FROM unnest(c.keywords) k WHERE k <> '' AND (h = f_norm(k) OR h LIKE '%' || f_norm(k) || '%')) LIMIT 1;
    IF v IS NOT NULL THEN RETURN v; END IF;
  END IF;
  IF coalesce(p_norm, '') <> '' THEN
    SELECT c.id INTO v FROM fin_categories c WHERE c.user_id = p_user AND c.kind = p_kind
      AND EXISTS (SELECT 1 FROM unnest(c.keywords) k WHERE k <> '' AND p_norm LIKE '%' || f_norm(k) || '%')
    ORDER BY c.is_default LIMIT 1;
  END IF;
  RETURN v;
END $$;
