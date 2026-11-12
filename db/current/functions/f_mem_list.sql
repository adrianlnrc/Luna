-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_mem_list(p_user bigint, p_filtro text)
-- Origem da definicao atual: 037_assessor_base.sql (linha 291)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:277, 037_assessor_base.sql:291
CREATE OR REPLACE FUNCTION agente.f_mem_list(p_user bigint, p_filtro text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE
  fl text := f_norm(p_filtro); vp boolean := false; vl boolean := false; vm boolean := false; v_tipo text; v_q text;
  t text := ''; r record; n int; items jsonb := '[]'::jsonb; np int := 0; nl int := 0; nm int := 0; sec text;
BEGIN
  IF fl IN ('', 'tudo', 'todos', 'todas', 'tudo tudo') THEN vp := true; vl := true; vm := true;
  ELSIF fl IN ('pessoa', 'pessoas', 'contato', 'contatos', 'grupo', 'grupos') THEN vp := true;
  ELSIF fl IN ('lugar', 'lugares', 'local', 'locais') THEN vl := true;
  ELSIF fl IN ('memoria', 'memorias', 'anotacoes', 'anotacao') THEN vm := true;
  ELSIF fl IN ('habito', 'habitos', 'preferencia', 'preferencias', 'fato', 'fatos', 'relacao', 'relacoes', 'parentesco') THEN vm := true; v_tipo := f_mem_tipo(fl);
  ELSE vp := true; vl := true; vm := true; v_q := fl;
  END IF;

  IF vp THEN
    sec := '';
    FOR r IN SELECT c.name, c.email, c.relation FROM contacts c
              WHERE c.user_id = p_user AND (v_q IS NULL OR f_norm(c.name || ' ' || c.email || ' ' || c.relation || ' ' || array_to_string(c.aliases, ' ')) LIKE '%' || v_q || '%')
              ORDER BY c.favorite DESC, c.name LOOP
      np := np + 1;
      sec := sec || E'\n- ' || f_ct_disp(r.name) || CASE WHEN r.relation <> '' THEN ' (' || r.relation || ')' ELSE '' END || CASE WHEN r.email <> '' THEN ' - ' || r.email ELSE '' END;
    END LOOP;
    IF v_q IS NULL OR np > 0 THEN t := t || 'Pessoas (' || np || '):' || CASE WHEN np = 0 THEN E'\n- nenhuma' ELSE sec END || E'\n\n'; END IF;
  END IF;
  IF vl THEN
    sec := '';
    FOR r IN SELECT p.name, p.address FROM places p
              WHERE p.user_id = p_user AND (v_q IS NULL OR f_norm(p.name || ' ' || p.address || ' ' || array_to_string(p.aliases, ' ')) LIKE '%' || v_q || '%')
              ORDER BY p.name LOOP
      nl := nl + 1;
      sec := sec || E'\n- ' || f_ct_disp(r.name) || ': ' || CASE WHEN r.address <> '' THEN r.address ELSE 'sem endereço ainda' END;
    END LOOP;
    IF v_q IS NULL OR nl > 0 THEN t := t || 'Lugares (' || nl || '):' || CASE WHEN nl = 0 THEN E'\n- nenhum' ELSE sec END || E'\n\n'; END IF;
  END IF;
  IF vm THEN
    sec := '';
    FOR r IN SELECT m.id, m.tipo, m.texto FROM user_memory m
              WHERE m.user_id = p_user AND m.ativo AND (v_tipo IS NULL OR m.tipo = v_tipo) AND (v_q IS NULL OR m.norm LIKE '%' || v_q || '%')
              ORDER BY m.tipo, m.id LOOP
      nm := nm + 1;
      items := items || jsonb_build_array(jsonb_build_object('id', r.id, 'tipo', r.tipo, 'texto', r.texto));
      sec := sec || E'\n- #' || r.id || ' ' || r.texto || ' (' || CASE r.tipo WHEN 'habito' THEN 'hábito' WHEN 'preferencia' THEN 'preferência' WHEN 'relacao' THEN 'relação' WHEN 'criterio' THEN 'critério' ELSE 'fato' END || ')';
    END LOOP;
    IF v_q IS NULL OR nm > 0 THEN
      t := t || 'Memória' || CASE WHEN v_tipo IS NOT NULL THEN ' (' || v_tipo || ')' ELSE '' END || ' (' || nm || '):'
             || CASE WHEN nm = 0 THEN E'\n- nada ainda' ELSE sec END || E'\n\n';
    END IF;
  END IF;
  t := btrim(t, E'\n ');
  IF t = '' THEN t := 'Não achei nada com "' || btrim(p_filtro) || '".'; END IF;
  IF vm AND nm > 0 THEN t := t || E'\n\nPara apagar um fato: "esquece o #' || (items->0->>'id') || '" ou "esquece que ...".'; END IF;
  RETURN jsonb_build_object('text', t, 'total', np + nl + nm, 'pessoas', np, 'lugares', nl, 'memoria', nm, 'items', items,
                            'switches', f_mem_switches(p_user));
END $$;
