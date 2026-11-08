-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_multi_db(p_user bigint, p_acts jsonb)
-- Origem da definicao atual: 033_acoes_recentes.sql (linha 131)
-- Definicoes (migracao:linha), da mais antiga a atual: 033_acoes_recentes.sql:131
CREATE OR REPLACE FUNCTION agente.f_multi_db(p_user bigint, p_acts jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  a jsonb; k text; tz text; v_lines jsonb := '[]'::jsonb; v_fails jsonb := '[]'::jsonb; res jsonb; t text; due timestamptz; v_title text; v_lead int; lab text;
BEGIN
  SELECT coalesce(nullif(timezone, ''), 'America/Sao_Paulo') INTO tz FROM users WHERE id = p_user;
  FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_acts, '[]'::jsonb)) LOOP
    k := a->>'kind'; v_title := btrim(coalesce(a->>'title', '')); t := NULL;
    BEGIN
      IF k = 'reminder' THEN
        due := (a->>'due_iso')::timestamptz;
        v_lead := nullif(a->>'lead', '')::int;
        res := f_reminder_create_ex(p_user, v_title, due, false, v_lead, 'text', '{"freq":"","until":"","count":""}'::jsonb);
        lab := CASE WHEN coalesce(v_lead, 0) >= 1440 AND v_lead % 1440 = 0 THEN ' (aviso ' || (v_lead / 1440) || ' dia(s) antes)'
                    WHEN coalesce(v_lead, 0) >= 60 AND v_lead % 60 = 0 THEN ' (aviso ' || (v_lead / 60) || 'h antes)'
                    WHEN coalesce(v_lead, 0) > 0 THEN ' (aviso ' || v_lead || ' min antes)' ELSE '' END;
        t := CASE WHEN coalesce((res->>'duplicate')::boolean, false) THEN 'Lembrete que já existia: ' ELSE 'Lembrete: ' END
             || v_title || ', ' || to_char(due AT TIME ZONE tz, 'DD/MM "às" HH24:MI') || lab;
      ELSIF k = 'expense' THEN
        res := f_fin(p_user, jsonb_build_object('action', 'add', 'kind', 'expense', 'amount', (a->>'amount')::numeric, 'title', v_title,
                 'category', '', 'category_stated', false, 'method', '', 'installments', 1, 'paid', true, 'date', '', 'recurring_day', NULL,
                 'person', '', 'period', 'current', 'keywords', '', 'budget_amount', NULL, 'closing_day', NULL, 'card', '',
                 'card_closing_day', NULL, 'card_due_day', NULL, 'card_limit', NULL, 'month', '', 'alert_days', NULL, 'report_format', '',
                 'items', '[]'::jsonb, 'source', 'text', 'reply', ''));
        t := nullif(btrim(split_part(coalesce(res->>'text', ''), E'\n', 1)), '');
        IF t IS NULL THEN RAISE EXCEPTION 'sem texto'; END IF;
      ELSIF k = 'note' THEN
        res := f_notes(p_user, jsonb_build_object('note_action', 'save', 'note_text', v_title, 'note_query', '', 'text', v_title));
        t := nullif(btrim(split_part(coalesce(res->>'text', ''), E'\n', 1)), '');
        IF t IS NULL THEN RAISE EXCEPTION 'sem texto'; END IF;
      ELSIF k = 'list' THEN
        res := f_lists(p_user, jsonb_build_object('list_action', 'add', 'list_name', coalesce(a->>'list_name', ''),
                 'list_items', coalesce(a->'items', '[]'::jsonb), 'text', v_title));
        t := nullif(btrim(split_part(coalesce(res->>'text', ''), E'\n', 1)), '');
        IF t IS NULL THEN RAISE EXCEPTION 'sem texto'; END IF;
      ELSIF k = 'supply' THEN
        res := f_supply_taken(p_user, v_title);
        IF coalesce((res->>'found')::boolean, false) THEN
          t := 'Anotado: tomou ' || coalesce(res->>'item', v_title);
        ELSE
          v_fails := v_fails || to_jsonb('Não achei o item "' || v_title || '" para marcar como tomado.');
          CONTINUE;
        END IF;
      ELSE
        CONTINUE;
      END IF;
      v_lines := v_lines || to_jsonb(t);
    EXCEPTION WHEN others THEN
      v_fails := v_fails || to_jsonb('Não consegui registrar "' || left(v_title, 60) || '".');
    END;
  END LOOP;
  RETURN jsonb_build_object('lines', v_lines, 'fails', v_fails);
END $$;
