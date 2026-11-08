-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_cat(p_user bigint, p_kind text, p_hint text, p_norm text, p_stated boolean)
-- Origem da definicao atual: 008_financas.sql (linha 153)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:153
CREATE OR REPLACE FUNCTION f_fin_cat(p_user bigint, p_kind text, p_hint text, p_norm text, p_stated boolean) RETURNS bigint
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE v bigint;
BEGIN
  PERFORM f_fin_seed(p_user);
  IF p_stated THEN
    v := f_fin_cat_find(p_user, p_kind, p_hint, '');
    IF v IS NOT NULL THEN RETURN v; END IF;
  END IF;
  IF coalesce(p_norm, '') <> '' THEN
    SELECT category_id INTO v FROM fin_entries
    WHERE user_id = p_user AND kind = p_kind AND norm_desc = p_norm AND category_id IS NOT NULL AND status <> 'draft'
    ORDER BY id DESC LIMIT 1;
    IF v IS NOT NULL THEN RETURN v; END IF;
  END IF;
  v := f_fin_cat_find(p_user, p_kind, p_hint, p_norm);
  IF v IS NOT NULL THEN RETURN v; END IF;
  SELECT id INTO v FROM fin_categories WHERE user_id = p_user AND kind = p_kind
    AND lower(name) = CASE WHEN p_kind = 'income' THEN 'recebimentos' ELSE 'outros' END;
  RETURN v;
END $$;
