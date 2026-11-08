-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agimp_create(p_user bigint, p_x jsonb)
-- Origem da definicao atual: 032_resumo_enxuto.sql (linha 106)
-- Definicoes (migracao:linha), da mais antiga a atual: 031_agenda_import.sql:78, 032_resumo_enxuto.sql:106
CREATE OR REPLACE FUNCTION f_agimp_create(p_user bigint, p_x jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE v_cal text; e jsonb; v_items jsonb := '[]'::jsonb; n int := 0; v_day date; k text; v_id bigint; v_week date; v_notes jsonb; v_title text; v_drop jsonb := '[]'::jsonb;
BEGIN
  SELECT calendar_key INTO v_cal FROM users WHERE id = p_user;
  IF coalesce(v_cal, '') = '' THEN
    RETURN jsonb_build_object('text', 'Ainda não tenho o seu Google conectado, então não consigo criar eventos nem tarefas. Fale com o Adrian para ligar a sua conta.', 'kb', 'none', 'rid', 0);
  END IF;
  FOR e IN SELECT x FROM jsonb_array_elements(coalesce(p_x->'items', '[]'::jsonb)) AS x LOOP
    BEGIN v_day := (e->>'day')::date; EXCEPTION WHEN others THEN CONTINUE; END;
    IF v_day IS NULL THEN CONTINUE; END IF;
    v_title := left(coalesce(nullif(trim(e->>'title'), ''), 'Compromisso'), 120);
    -- nao e acao nem compromisso: feriado, avisos soltos
    IF lower(v_title) ~ '^(feriado|recesso|ponto facultativo|obs\.?|observa[cç][aã]o|anota[cç][aã]o|nota|lembrete geral)\M' THEN
      v_drop := v_drop || to_jsonb(v_title || ' (' || to_char(v_day, 'DD/MM') || ')');
      CONTINUE;
    END IF;
    k := CASE WHEN e->>'kind' = 'task' THEN 'task' ELSE 'event' END;
    IF k = 'event' AND NOT (coalesce(e->>'start', '') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' AND coalesce(e->>'end', '') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' AND (e->>'end') > (e->>'start')) THEN
      k := 'task';
    END IF;
    n := n + 1;
    v_items := v_items || jsonb_build_array(jsonb_build_object('n', n, 'kind', k, 'day', v_day,
      'start', CASE WHEN k = 'event' THEN e->>'start' END, 'end', CASE WHEN k = 'event' THEN e->>'end' END,
      'title', v_title,
      'urgent', coalesce((e->>'urgent')::boolean, false), 'uncertain', coalesce((e->>'uncertain')::boolean, false)));
  END LOOP;
  IF n = 0 THEN
    RETURN jsonb_build_object('text', 'Não consegui ler compromissos nessa foto. Tente de novo com a página inteira, bem iluminada e sem reflexo.', 'kb', 'none', 'rid', 0);
  END IF;
  v_items := f_agimp_mark_fixed(v_items);
  BEGIN v_week := (p_x->>'week_start')::date; EXCEPTION WHEN others THEN v_week := NULL; END;
  v_notes := (CASE WHEN jsonb_typeof(p_x->'notes') = 'array' THEN p_x->'notes' ELSE '[]'::jsonb END) || v_drop;
  DELETE FROM agenda_import WHERE user_id = p_user AND created_at < now() - interval '30 days';
  UPDATE agenda_import SET state = 'cancelled' WHERE user_id = p_user AND state = 'open';
  INSERT INTO agenda_import (user_id, calendar_key, week_start, items, notes) VALUES (p_user, v_cal, v_week, v_items, v_notes) RETURNING id INTO v_id;
  RETURN jsonb_build_object('text', f_agimp_render(v_id), 'kb', 'agimp', 'rid', v_id);
END $$;
