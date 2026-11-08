-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_callback_pre_f10(p_user bigint, p_data text)
-- Origem da definicao atual: 031_agenda_import.sql (linha 237)
-- Definicoes (migracao:linha), da mais antiga a atual: 026_recibo_alertas.sql:237, 031_agenda_import.sql:237
-- Renomeada de f_callback para f_callback_pre_f10 em 033_acoes_recentes.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_callback_pre_f10).
CREATE OR REPLACE FUNCTION f_callback(p_user bigint, p_data text) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE a text := split_part(p_data, ':', 1); v_id bigint := CASE WHEN split_part(p_data, ':', 2) ~ '^[0-9]+$' THEN split_part(p_data, ':', 2)::bigint END; res jsonb; al text := '';
BEGIN
  IF a IN ('aiok', 'aino') THEN
    RETURN f_agimp_cb(p_user, p_data);
  END IF;
  IF a = 'fedit' THEN
    RETURN f_fin_edit_cb(p_user, coalesce(v_id, 0));
  END IF;
  IF a = 'fundo' AND v_id IS NOT NULL AND EXISTS (SELECT 1 FROM fin_entries WHERE id = v_id AND user_id = p_user) AND f_fin_expired(v_id) THEN
    RETURN jsonb_build_object('text', 'Esse lançamento já passou de 24h; diga o que corrigir, por exemplo: corrige o gasto do mercado de ontem para 50', 'kb', 'none');
  END IF;
  res := f_callback_pre_m2(p_user, p_data);
  IF a = 'fok' AND v_id IS NOT NULL AND res->>'kb' = 'fin_undo' THEN
    UPDATE fin_entries SET created_at = now() WHERE id = v_id AND user_id = p_user AND status IN ('paid', 'pending');
    BEGIN al := f_fin_alerts(p_user, v_id); EXCEPTION WHEN others THEN al := ''; END;
    res := jsonb_set(res, '{text}', to_jsonb((res->>'text') || al));
    res := jsonb_set(res, '{kb}', '"fin_recibo"'::jsonb);
  END IF;
  RETURN res;
END $$;
