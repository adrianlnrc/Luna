-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_correct_pre_m2(p_user bigint, p jsonb)
-- Origem da definicao atual: 008_financas.sql (linha 352)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:352
-- Renomeada de f_fin_correct para f_fin_correct_pre_m2 em 026_recibo_alertas.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_fin_correct_pre_m2).
CREATE OR REPLACE FUNCTION f_fin_correct(p_user bigint, p jsonb) RETURNS jsonb LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE e fin_entries%ROWTYPE; v_amt numeric := round(nullif(p->>'amount', '')::numeric, 2); v_cat bigint; v_name text; v_title text := btrim(coalesce(p->>'title', ''));
        v_hint text := btrim(coalesce(p->>'category', '')); v_changes text[] := '{}'; v_found boolean := false;
BEGIN
  -- alvo: o lancamento citado pelo nome (se houver) ou o ultimo
  IF v_title <> '' THEN
    SELECT * INTO e FROM fin_entries WHERE user_id = p_user AND status <> 'draft' AND norm_desc LIKE '%' || f_norm(v_title) || '%' ORDER BY id DESC LIMIT 1;
    v_found := FOUND;
  END IF;
  IF NOT v_found THEN
    SELECT * INTO e FROM fin_entries WHERE user_id = p_user AND status <> 'draft' ORDER BY id DESC LIMIT 1;
  END IF;
  IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Não tenho nenhum lançamento para corrigir.', 'kb', 'none'); END IF;
  IF v_amt IS NOT NULL AND v_amt > 0 THEN
    UPDATE fin_entries SET amount = v_amt WHERE id = e.id; v_changes := v_changes || ('valor ' || f_brl(v_amt));
  END IF;
  IF v_hint <> '' THEN
    v_cat := f_fin_cat_find(p_user, e.kind, v_hint, '');
    IF v_cat IS NULL THEN
      INSERT INTO fin_categories (user_id, name, kind) VALUES (p_user, left(v_hint, 60), e.kind) ON CONFLICT DO NOTHING;
      v_cat := f_fin_cat_find(p_user, e.kind, v_hint, '');
    END IF;
    IF v_cat IS NOT NULL THEN
      UPDATE fin_entries SET category_id = v_cat WHERE id = e.id OR (e.series_id IS NOT NULL AND series_id = e.series_id);
      SELECT name INTO v_name FROM fin_categories WHERE id = v_cat; v_changes := v_changes || ('categoria ' || v_name);
    END IF;
  END IF;
  IF v_title <> '' AND NOT v_found AND f_norm(v_title) <> e.norm_desc AND v_hint = '' AND v_amt IS NULL THEN
    UPDATE fin_entries SET description = left(v_title, 120), norm_desc = f_norm(v_title) WHERE id = e.id; v_changes := v_changes || ('descrição ' || v_title);
  END IF;
  IF array_length(v_changes, 1) IS NULL THEN
    RETURN jsonb_build_object('text', 'O que devo corrigir em ' || e.description || ' ' || f_brl(e.amount) || '? Valor, categoria ou descrição?', 'kb', 'none');
  END IF;
  RETURN jsonb_build_object('text', 'Corrigido: ' || e.description || ' agora com ' || array_to_string(v_changes, ', ') || '.', 'kb', 'none');
END $$;
