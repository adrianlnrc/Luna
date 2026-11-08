-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_recent_correct(p_user bigint, p jsonb)
-- Origem da definicao atual: 033_acoes_recentes.sql (linha 286)
-- Definicoes (migracao:linha), da mais antiga a atual: 033_acoes_recentes.sql:286
CREATE OR REPLACE FUNCTION agente.f_recent_correct(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  ra recent_actions%ROWTYPE; r reminders%ROWTYPE; tz text; v_title text; v_date date; v_time time; v_due timestamptz; offs int[]; o int; v_note text;
BEGIN
  SELECT coalesce(nullif(timezone, ''), 'America/Sao_Paulo') INTO tz FROM users WHERE id = p_user;
  SELECT * INTO ra FROM recent_actions
   WHERE id = CASE WHEN coalesce(p->>'recent_id', '') ~ '^[0-9]+$' THEN (p->>'recent_id')::bigint END AND user_id = p_user AND NOT undone;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('text', 'Não achei essa ação entre as últimas. Me diz o nome do que você quer corrigir.', 'kb', 'none', 'rid', 0);
  END IF;

  IF ra.kind = 'reminder' THEN
    SELECT * INTO r FROM reminders WHERE id = ra.ref_id AND user_id = p_user;
    IF NOT FOUND OR r.status NOT IN ('pending', 'awaiting_time') THEN
      RETURN jsonb_build_object('text', 'Esse lembrete já foi concluído ou cancelado. Quer que eu crie outro?', 'kb', 'none', 'rid', 0);
    END IF;
    v_title := coalesce(nullif(btrim(p->>'title'), ''), r.title);
    v_due := r.due_at;
    IF coalesce(p->>'date', '') <> '' OR coalesce(p->>'time', '') <> '' THEN
      v_date := coalesce(nullif(p->>'date', '')::date, (r.due_at AT TIME ZONE tz)::date);
      v_time := coalesce(nullif(p->>'time', '')::time, (r.due_at AT TIME ZONE tz)::time);
      IF v_date IS NULL OR v_time IS NULL THEN
        RETURN jsonb_build_object('text', 'Me diga a data e a hora certas do lembrete.', 'kb', 'none', 'rid', 0);
      END IF;
      v_due := (v_date + v_time) AT TIME ZONE tz;
      IF v_due <= now() THEN
        RETURN jsonb_build_object('text', 'Esse horário já passou. Para quando eu mudo?', 'kb', 'none', 'rid', 0);
      END IF;
    END IF;
    UPDATE reminders SET title = v_title, due_at = v_due, status = 'pending' WHERE id = r.id;
    IF v_due IS DISTINCT FROM r.due_at THEN
      SELECT array_agg(DISTINCT offset_minutes) INTO offs FROM notifications WHERE reminder_id = r.id AND type = 'pre_alert' AND offset_minutes IS NOT NULL;
      UPDATE notifications SET state = 'cancelled' WHERE reminder_id = r.id AND state = 'pending';
      INSERT INTO notifications(user_id, reminder_id, type, fire_at) VALUES (p_user, r.id, 'reminder', v_due);
      FOREACH o IN ARRAY coalesce(offs, ARRAY[]::int[]) LOOP
        IF o > 0 AND v_due - make_interval(mins => o) > now() THEN
          INSERT INTO notifications(user_id, reminder_id, type, fire_at, offset_minutes) VALUES (p_user, r.id, 'pre_alert', v_due - make_interval(mins => o), o);
        END IF;
      END LOOP;
    END IF;
    UPDATE recent_actions SET label = left(v_title || ', ' || to_char(v_due AT TIME ZONE tz, 'DD/MM HH24:MI'), 120) WHERE id = ra.id;
    RETURN jsonb_build_object('text', 'Corrigido: ' || v_title || ', ' || to_char(v_due AT TIME ZONE tz, 'DD/MM "às" HH24:MI') || '.', 'kb', 'none', 'rid', 0);

  ELSIF ra.kind = 'note' THEN
    v_note := btrim(coalesce(p->>'note_text', ''));
    IF f_norm(v_note) = '' THEN
      RETURN jsonb_build_object('text', 'Como a nota deve ficar?', 'kb', 'none', 'rid', 0);
    END IF;
    v_note := left(v_note, 4000);
    UPDATE notes SET body = v_note, body_norm = f_norm(v_note) WHERE id = ra.ref_id AND user_id = p_user;
    UPDATE recent_actions SET label = left(v_note, 70) WHERE id = ra.id;
    RETURN jsonb_build_object('text', 'Nota corrigida: "' || left(v_note, 100) || '".', 'kb', 'none', 'rid', 0);

  ELSIF ra.kind = 'event' THEN
    RETURN jsonb_build_object('text', 'Para mudar um compromisso eu confirmo com você antes. Diga, por exemplo: "muda ' || left(ra.label, 40) || ' para as 10h".', 'kb', 'none', 'rid', 0);
  ELSIF ra.kind = 'expense' THEN
    RETURN jsonb_build_object('text', 'Para corrigir um gasto diga, por exemplo: "corrige o gasto do mercado para 50".', 'kb', 'none', 'rid', 0);
  END IF;
  RETURN jsonb_build_object('text', 'Tarefa do Google eu ainda não altero. Quer que eu crie outra com o texto certo? A antiga você apaga no app.', 'kb', 'none', 'rid', 0);
END $$;
