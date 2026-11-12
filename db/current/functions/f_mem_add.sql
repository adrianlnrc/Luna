-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_mem_add(p_user bigint, p_texto text, p_tipo text, p_origem text)
-- Origem da definicao atual: 037_assessor_base.sql (linha 221)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:149, 037_assessor_base.sql:221
CREATE OR REPLACE FUNCTION agente.f_mem_add(p_user bigint, p_texto text, p_tipo text DEFAULT 'fato', p_origem text DEFAULT 'ia') RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  v_txt text := left(btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')), 200);
  v_norm text; v_cur text; v_tipo text := f_mem_tipo(p_tipo); d user_memory%ROWTYPE; v_id bigint; v_ev int := 0; v_cap constant int := 40;
BEGIN
  IF NOT f_mem_sw(p_user, 'mem_enabled') THEN
    RETURN jsonb_build_object('ok', false, 'disabled', true, 'text', '');
  END IF;
  v_norm := f_norm(v_txt);
  IF length(v_norm) < 3 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vazio', 'text', '');
  END IF;
  DELETE FROM user_memory WHERE user_id = p_user AND NOT ativo AND coalesce(ultimo_uso, criado_em) < now() - interval '30 days';

  SELECT * INTO d FROM user_memory m
   WHERE m.user_id = p_user AND m.ativo AND m.tipo <> 'criterio'
     AND (m.norm = v_norm
          OR (length(v_norm) >= 10 AND length(m.norm) >= 10 AND (position(v_norm IN m.norm) > 0 OR position(m.norm IN v_norm) > 0))
          OR (SELECT count(*) FROM (SELECT unnest(string_to_array(m.norm, ' ')) INTERSECT SELECT unnest(string_to_array(v_norm, ' '))) i)::numeric
             / greatest((SELECT count(*) FROM (SELECT unnest(string_to_array(m.norm, ' ')) UNION SELECT unnest(string_to_array(v_norm, ' '))) u), 1) >= 0.8)
   ORDER BY m.id LIMIT 1;
  IF FOUND THEN
    UPDATE user_memory SET ultimo_uso = now(),
           texto = CASE WHEN length(v_txt) > length(texto) AND position(norm IN v_norm) > 0 THEN v_txt ELSE texto END,
           norm  = CASE WHEN length(v_txt) > length(texto) AND position(norm IN v_norm) > 0 THEN v_norm ELSE norm END
     WHERE id = d.id RETURNING id, texto INTO v_id, v_cur;
    RETURN jsonb_build_object('ok', true, 'duplicate', true, 'id', v_id, 'text', 'Já estava anotado: ' || v_cur);
  END IF;

  -- um fato que foi esquecido e volta a ser dito: reativa a linha antiga em vez de criar outra
  SELECT id INTO v_id FROM user_memory WHERE user_id = p_user AND NOT ativo AND norm = v_norm ORDER BY id DESC LIMIT 1;
  IF v_id IS NOT NULL THEN
    UPDATE user_memory SET ativo = true, texto = v_txt, tipo = v_tipo, origem = left(coalesce(p_origem, 'ia'), 30), ultimo_uso = now() WHERE id = v_id;
  ELSE
    INSERT INTO user_memory(user_id, texto, norm, tipo, origem) VALUES (p_user, v_txt, v_norm, v_tipo, left(coalesce(p_origem, 'ia'), 30)) RETURNING id INTO v_id;
  END IF;

  WITH over AS (
    SELECT id FROM user_memory WHERE user_id = p_user AND ativo AND tipo <> 'criterio' AND id <> v_id
     ORDER BY usos DESC, coalesce(ultimo_uso, criado_em) DESC, criado_em DESC OFFSET v_cap - 1)
  UPDATE user_memory SET ativo = false WHERE id IN (SELECT id FROM over);
  GET DIAGNOSTICS v_ev = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'duplicate', false, 'id', v_id, 'evicted', v_ev, 'tipo', v_tipo, 'text', 'Anotei: ' || v_txt);
END $$;
