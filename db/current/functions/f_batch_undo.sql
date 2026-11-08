-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_batch_undo(p_user bigint, p_batch bigint)
-- Origem da definicao atual: 033_acoes_recentes.sql (linha 237)
-- Definicoes (migracao:linha), da mais antiga a atual: 033_acoes_recentes.sql:237
CREATE OR REPLACE FUNCTION agente.f_batch_undo(p_user bigint, p_batch bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  ra recent_actions%ROWTYPE; v_done text := ''; v_manual text := ''; v_cals jsonb := '[]'::jsonb; n int := 0; nl text := E'\n'; v_text text;
BEGIN
  IF p_batch IS NULL THEN RETURN jsonb_build_object('text', 'Não achei o que desfazer.', 'kb', 'none', 'rid', 0); END IF;
  FOR ra IN SELECT * FROM recent_actions WHERE user_id = p_user AND batch_id = p_batch AND NOT undone ORDER BY id DESC LOOP
    BEGIN
      IF ra.kind = 'reminder' THEN
        UPDATE reminders SET status = 'cancelled' WHERE id = ra.ref_id AND user_id = p_user;
        UPDATE notifications SET state = 'cancelled' WHERE reminder_id = ra.ref_id AND state = 'pending';
      ELSIF ra.kind = 'event' THEN
        UPDATE reminders SET status = 'cancelled' WHERE user_id = p_user AND calendar_event_id = ra.ref_text AND status IN ('pending', 'awaiting_time');
        UPDATE notifications SET state = 'cancelled' WHERE state = 'pending' AND reminder_id IN (SELECT id FROM reminders WHERE user_id = p_user AND calendar_event_id = ra.ref_text);
        UPDATE agenda_series SET active = false WHERE user_id = p_user AND calendar_event_id = ra.ref_text;
        v_cals := v_cals || jsonb_build_array(jsonb_build_object('op', 'delete', 'calendar_key', coalesce(ra.calendar_key, ''), 'event_id', ra.ref_text, 'title', ra.label));
      ELSIF ra.kind = 'expense' THEN
        PERFORM f_callback(p_user, 'fundo:' || ra.ref_id);
      ELSIF ra.kind = 'note' THEN
        DELETE FROM notes WHERE id = ra.ref_id AND user_id = p_user;
      ELSIF ra.kind = 'list_item' THEN
        DELETE FROM list_items WHERE id = ra.ref_id AND user_id = p_user;
      ELSIF ra.kind = 'task' THEN
        v_manual := v_manual || nl || '- tarefa: ' || ra.label;
        CONTINUE;
      END IF;
      UPDATE recent_actions SET undone = true WHERE id = ra.id;
      IF ra.kind <> 'list_item' THEN
        v_done := v_done || nl || '- ' || CASE ra.kind WHEN 'reminder' THEN 'lembrete' WHEN 'event' THEN 'compromisso' WHEN 'expense' THEN 'gasto' WHEN 'note' THEN 'nota' ELSE ra.kind END || ': ' || ra.label;
      ELSE
        n := n + 1;
      END IF;
    EXCEPTION WHEN others THEN
      v_manual := v_manual || nl || '- ' || ra.label || ' (deu erro; confira)';
    END;
  END LOOP;
  IF v_done = '' AND n = 0 AND v_manual = '' THEN
    RETURN jsonb_build_object('text', 'Isso já foi desfeito (ou não tem mais nada desse pedido para desfazer).', 'kb', 'none', 'rid', 0);
  END IF;
  v_text := 'Desfeito:' || v_done || CASE WHEN n > 0 THEN nl || '- ' || n || ' item(ns) de lista' ELSE '' END;
  IF v_done = '' AND n = 0 THEN v_text := 'Não consegui desfazer tudo.'; END IF;
  IF v_manual <> '' THEN
    v_text := v_text || nl || nl || 'Estes eu não consigo desfazer daqui (apague no app do Google se quiser):' || v_manual;
  END IF;
  RETURN jsonb_build_object('text', v_text, 'kb', 'none', 'rid', 0) || CASE WHEN jsonb_array_length(v_cals) > 0 THEN jsonb_build_object('cals', v_cals) ELSE '{}'::jsonb END;
END $$;
