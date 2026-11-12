-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_crit_add(p_user bigint, p_texto text, p_origem text)
-- Origem da definicao atual: 037_assessor_base.sql (linha 347)
-- Definicoes (migracao:linha), da mais antiga a atual: 037_assessor_base.sql:347
CREATE OR REPLACE FUNCTION agente.f_crit_add(p_user bigint, p_texto text, p_origem text DEFAULT 'pedido') RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  v_txt text := left(btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')), 200);
  v_norm text; v_id bigint; n int; v_cap constant int := 15;
BEGIN
  IF NOT f_mem_sw(p_user, 'mem_enabled') THEN
    RETURN jsonb_build_object('ok', false, 'disabled', true, 'text', 'A memória está desligada. Diga "liga a memória" para eu guardar critérios.');
  END IF;
  v_norm := f_norm(v_txt);
  IF length(v_norm) < 3 THEN RETURN jsonb_build_object('ok', false, 'error', 'vazio', 'text', 'Qual é o critério?'); END IF;
  SELECT id INTO v_id FROM user_memory WHERE user_id = p_user AND ativo AND tipo = 'criterio' AND norm = v_norm LIMIT 1;
  IF v_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'duplicate', true, 'id', v_id, 'text', 'Já sigo esse critério: ' || v_txt);
  END IF;
  SELECT count(*) INTO n FROM user_memory WHERE user_id = p_user AND ativo AND tipo = 'criterio';
  IF n >= v_cap THEN
    RETURN jsonb_build_object('ok', false, 'error', 'teto', 'total', n,
      'text', 'Você já tem ' || n || ' critérios, que é o máximo. Veja com /memoria e apague um ("esquece o #id") antes de criar outro.');
  END IF;
  INSERT INTO user_memory (user_id, texto, norm, tipo, origem)
  VALUES (p_user, v_txt, v_norm, 'criterio', left(coalesce(p_origem, 'pedido'), 30)) RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'duplicate', false, 'id', v_id, 'text', 'Anotei o critério: ' || v_txt);
END $$;
