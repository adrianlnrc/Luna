-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agimp_edit_pre_m9(p_user bigint, p_x jsonb)
-- Origem da definicao atual: 031_agenda_import.sql (linha 132)
-- Definicoes (migracao:linha), da mais antiga a atual: 031_agenda_import.sql:132
-- Renomeada de f_agimp_edit para f_agimp_edit_pre_m9 em 032_resumo_enxuto.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_agimp_edit_pre_m9).
CREATE OR REPLACE FUNCTION f_agimp_edit(p_user bigint, p_x jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE r agenda_import; v_act text := coalesce(p_x->>'act', ''); v_n int; v_item jsonb; v_new jsonb; v_vis int; v_title text; v_date date; v_start text; v_end text;
        v_dur int; v_kind text;
BEGIN
  SELECT * INTO r FROM agenda_import WHERE user_id = p_user AND state = 'open' ORDER BY id DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('text', 'Não tenho nenhuma importação de agenda em aberto. Mande a foto da agenda que eu leio de novo.', 'kb', 'none', 'rid', 0);
  END IF;
  IF v_act = 'cancel' THEN
    UPDATE agenda_import SET state = 'cancelled' WHERE id = r.id;
    RETURN jsonb_build_object('text', 'Importação cancelada. Nada foi criado.', 'kb', 'none', 'rid', 0);
  END IF;
  IF v_act = 'confirm' THEN RETURN f_agimp_confirm(p_user, r.id); END IF;
  IF p_x->>'n' ~ '^[0-9]+$' THEN v_n := (p_x->>'n')::int; END IF;
  SELECT count(*) INTO v_vis FROM jsonb_array_elements(r.items) AS x(e) WHERE coalesce((x.e->>'skip')::boolean, false) = false;
  IF v_n IS NULL AND v_vis = 1 THEN
    SELECT (x.e->>'n')::int INTO v_n FROM jsonb_array_elements(r.items) AS x(e) WHERE coalesce((x.e->>'skip')::boolean, false) = false;
  END IF;
  IF v_n IS NULL THEN
    RETURN jsonb_build_object('text', 'Qual item você quer corrigir? Diga o número, por exemplo "o 3 é na segunda".' || E'\n\n' || f_agimp_render(r.id), 'kb', 'agimp', 'rid', r.id);
  END IF;
  SELECT x.e INTO v_item FROM jsonb_array_elements(r.items) AS x(e) WHERE (x.e->>'n')::int = v_n AND coalesce((x.e->>'skip')::boolean, false) = false;
  IF v_item IS NULL THEN
    RETURN jsonb_build_object('text', 'Não achei o item ' || v_n || ' na lista.' || E'\n\n' || f_agimp_render(r.id), 'kb', 'agimp', 'rid', r.id);
  END IF;
  v_new := v_item;
  IF v_act = 'remove' THEN
    v_new := jsonb_set(v_new, '{skip}', 'true'::jsonb);
  ELSE
    v_title := nullif(trim(coalesce(p_x->>'title', '')), '');
    IF v_title IS NOT NULL THEN v_new := jsonb_set(v_new, '{title}', to_jsonb(left(v_title, 120))); END IF;
    BEGIN v_date := nullif(p_x->>'date', '')::date; EXCEPTION WHEN others THEN v_date := NULL; END;
    IF v_date IS NOT NULL THEN v_new := jsonb_set(v_new, '{day}', to_jsonb(v_date)); END IF;
    v_kind := CASE WHEN p_x->>'kind' IN ('event', 'task') THEN p_x->>'kind' ELSE v_item->>'kind' END;
    v_start := CASE WHEN coalesce(p_x->>'time', '') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN p_x->>'time' END;
    v_end := CASE WHEN coalesce(p_x->>'end', '') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN p_x->>'end' END;
    IF v_kind = 'task' THEN
      v_new := jsonb_set(jsonb_set(jsonb_set(v_new, '{kind}', '"task"'::jsonb), '{start}', 'null'::jsonb), '{end}', 'null'::jsonb);
    ELSE
      IF v_item->>'kind' = 'event' THEN
        v_dur := greatest(15, (extract(epoch FROM ((v_item->>'end')::time - (v_item->>'start')::time)) / 60)::int);
        IF v_start IS NOT NULL AND v_end IS NULL THEN
          v_end := to_char(least((v_start::time + make_interval(mins => v_dur)), time '23:59'), 'HH24:MI');
        END IF;
        v_start := coalesce(v_start, v_item->>'start'); v_end := coalesce(v_end, v_item->>'end');
      ELSE
        -- tarefa virando compromisso: precisa de hora de inicio
        IF v_start IS NULL THEN
          RETURN jsonb_build_object('text', 'Para virar compromisso eu preciso da hora. Diga, por exemplo, "o ' || v_n || ' é às 14h".' || E'\n\n' || f_agimp_render(r.id), 'kb', 'agimp', 'rid', r.id);
        END IF;
        v_end := coalesce(v_end, to_char(least((v_start::time + interval '1 hour'), time '23:59'), 'HH24:MI'));
        v_new := jsonb_set(v_new, '{kind}', '"event"'::jsonb);
      END IF;
      IF v_end <= v_start THEN
        RETURN jsonb_build_object('text', 'O fim precisa ser depois do início. Diga de novo o horário do item ' || v_n || '.' || E'\n\n' || f_agimp_render(r.id), 'kb', 'agimp', 'rid', r.id);
      END IF;
      v_new := jsonb_set(jsonb_set(v_new, '{start}', to_jsonb(v_start)), '{end}', to_jsonb(v_end));
    END IF;
    v_new := jsonb_set(v_new, '{uncertain}', 'false'::jsonb);
  END IF;
  UPDATE agenda_import SET items = (
    SELECT jsonb_agg(CASE WHEN (x.e->>'n')::int = v_n THEN v_new ELSE x.e END ORDER BY ord)
      FROM jsonb_array_elements(items) WITH ORDINALITY AS x(e, ord)) WHERE id = r.id;
  RETURN jsonb_build_object('text', CASE WHEN v_act = 'remove' THEN 'Tirei o item ' || v_n || '.' ELSE 'Corrigi o item ' || v_n || '.' END || E'\n\n' || f_agimp_render(r.id), 'kb', 'agimp', 'rid', r.id);
END $$;
