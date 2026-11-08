-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agimp_edit(p_user bigint, p_x jsonb)
-- Origem da definicao atual: 032_resumo_enxuto.sql (linha 180)
-- Definicoes (migracao:linha), da mais antiga a atual: 032_resumo_enxuto.sql:180
CREATE OR REPLACE FUNCTION f_agimp_edit(p_user bigint, p_x jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE r agenda_import; n_fx int;
BEGIN
  IF coalesce(p_x->>'act', '') = 'remove' AND lower(trim(coalesce(p_x->>'title', ''))) = 'fixos' AND coalesce(p_x->>'n', '') = '' THEN
    SELECT * INTO r FROM agenda_import WHERE user_id = p_user AND state = 'open' ORDER BY id DESC LIMIT 1;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('text', 'Não tenho nenhuma importação de agenda em aberto. Mande a foto da agenda que eu leio de novo.', 'kb', 'none', 'rid', 0);
    END IF;
    SELECT count(*) INTO n_fx FROM jsonb_array_elements(r.items) x(e) WHERE coalesce((x.e->>'fixed')::boolean, false) AND coalesce((x.e->>'skip')::boolean, false) = false;
    IF n_fx = 0 THEN
      RETURN jsonb_build_object('text', 'Não há blocos fixos nesse rascunho.' || E'\n\n' || f_agimp_render(r.id), 'kb', 'agimp', 'rid', r.id);
    END IF;
    UPDATE agenda_import SET items = (SELECT jsonb_agg(CASE WHEN coalesce((x.e->>'fixed')::boolean, false) THEN jsonb_set(x.e, '{skip}', 'true'::jsonb) ELSE x.e END ORDER BY ord)
                                        FROM jsonb_array_elements(items) WITH ORDINALITY AS x(e, ord)) WHERE id = r.id;
    RETURN jsonb_build_object('text', 'Tirei os blocos fixos.' || E'\n\n' || f_agimp_render(r.id), 'kb', 'agimp', 'rid', r.id);
  END IF;
  RETURN f_agimp_edit_pre_m9(p_user, p_x);
END $$;
