-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_mem_forget(p_user bigint, p_ref text)
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 334)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:334
CREATE OR REPLACE FUNCTION agente.f_mem_forget(p_user bigint, p_ref text) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  ref text := btrim(coalesce(p_ref, '')); q text; v_id bigint; ids bigint[]; cand jsonb; n int; toks text[]; d user_memory%ROWTYPE;
BEGIN
  IF ref ~ '^#?[0-9]+$' THEN
    UPDATE user_memory SET ativo = false WHERE id = ltrim(ref, '#')::bigint AND user_id = p_user AND ativo RETURNING id INTO v_id;
    IF v_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'found', false, 'text', 'Não achei esse item na sua memória.'); END IF;
    SELECT * INTO d FROM user_memory WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'found', true, 'removed', jsonb_build_array(d.texto), 'text', 'Esqueci: ' || d.texto);
  END IF;

  q := f_norm(ref);
  IF q IN ('', 'isso', 'esse', 'essa', 'ultimo', 'o ultimo', 'esse ultimo', 'isso ai') THEN
    UPDATE user_memory SET ativo = false
     WHERE id = (SELECT id FROM user_memory WHERE user_id = p_user AND ativo ORDER BY id DESC LIMIT 1) AND user_id = p_user
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'found', false, 'text', 'Não tenho nada na memória para esquecer.'); END IF;
    SELECT * INTO d FROM user_memory WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'found', true, 'removed', jsonb_build_array(d.texto), 'text', 'Esqueci: ' || d.texto);
  END IF;

  toks := f_mem_tokens(ref);
  SELECT array_agg(m.id ORDER BY m.id) INTO ids FROM user_memory m
   WHERE m.user_id = p_user AND m.ativo
     AND (m.norm LIKE '%' || q || '%'
          OR (cardinality(toks) > 0 AND NOT EXISTS (SELECT 1 FROM unnest(toks) t WHERE strpos(' ' || m.norm || ' ', ' ' || t) = 0)));
  n := coalesce(cardinality(ids), 0);
  IF n = 0 THEN RETURN jsonb_build_object('ok', false, 'found', false, 'text', 'Não achei isso na sua memória. Veja com /memoria.'); END IF;
  IF n > 1 THEN
    SELECT jsonb_agg(jsonb_build_object('id', m.id, 'texto', m.texto) ORDER BY m.id) INTO cand FROM user_memory m WHERE m.id = ANY (ids[1:8]);
    RETURN jsonb_build_object('ok', false, 'found', true, 'count', n, 'ambiguous', cand,
             'text', 'Achei ' || n || ': ' || (SELECT string_agg('#' || m.id || ' ' || m.texto, '; ' ORDER BY m.id) FROM user_memory m WHERE m.id = ANY (ids[1:5]))
                     || CASE WHEN n > 5 THEN ' (e mais ' || (n - 5) || ')' ELSE '' END || '. Qual eu esqueço?');
  END IF;
  UPDATE user_memory SET ativo = false WHERE id = ids[1] RETURNING * INTO d;
  RETURN jsonb_build_object('ok', true, 'found', true, 'removed', jsonb_build_array(d.texto), 'text', 'Esqueci: ' || d.texto);
END $$;
