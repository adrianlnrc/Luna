-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_callback_base(p_user bigint, p_data text)
-- Origem da definicao atual: 008_financas.sql (linha 656)
-- Definicoes (migracao:linha), da mais antiga a atual: 003_functions.sql:69, 005_doses.sql:108, 008_financas.sql:656
-- Renomeada de f_callback para f_callback_base em 011b_base_agenda.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_callback_base).
CREATE OR REPLACE FUNCTION f_callback(p_user bigint, p_data text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE a text := split_part(p_data, ':', 1); v_id bigint := NULLIF(split_part(p_data, ':', 2), '')::bigint;
        r reminders%ROWTYPE; s supplies%ROWTYPE; tz text; v_new timestamptz; v_sid bigint; v_st supplies_status%ROWTYPE; v_fin fin_entries%ROWTYPE;
BEGIN
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  IF a = 'sum' THEN
    UPDATE users SET summary_time = substr(p_data, 5)::time, onboarding_step = 'done', onboarded_at = COALESCE(onboarded_at, now())
    WHERE id = p_user;
    RETURN jsonb_build_object('text', 'Pronto! Seu resumo diario sai as ' || substr(p_data, 5) ||
      '. Pode me mandar seu primeiro lembrete, por texto ou audio.', 'kb', 'none');
  ELSIF a = 'lead' THEN
    RETURN f_set_lead(p_user, v_id, split_part(p_data, ':', 3)::integer);
  ELSIF a IN ('fundo', 'fok', 'fno', 'fdel', 'fkeep') THEN
    RETURN f_fin_cb(p_user, a, v_id);
  ELSIF a IN ('took', 'skipd') THEN
    UPDATE supply_doses SET status = CASE WHEN a = 'took' THEN 'taken' ELSE 'skipped' END,
                            taken_at = CASE WHEN a = 'took' THEN now() END
    WHERE id = v_id AND user_id = p_user AND status = 'pending' RETURNING supply_id INTO v_sid;
    IF v_sid IS NULL THEN RETURN jsonb_build_object('text', 'Essa dose ja foi registrada.', 'kb', 'none'); END IF;
    UPDATE notifications SET state = 'cancelled' WHERE dose_id = v_id AND state = 'pending';
    SELECT * INTO v_st FROM supplies_status WHERE id = v_sid;
    IF a = 'took' THEN
      RETURN jsonb_build_object('text', 'Anotado: tomou ' || v_st.item || '. Restam ' || round(v_st.units_left)::int ||
        ' (acaba em ' || to_char(v_st.runs_out_on, 'DD/MM') || ').', 'kb', 'none');
    END IF;
    RETURN jsonb_build_object('text', 'Ok, pulei a dose de hoje de ' || v_st.item || '.', 'kb', 'none');
  ELSIF a IN ('bought', 'later') THEN
    SELECT * INTO s FROM supplies WHERE id = v_id AND user_id = p_user;
    IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Nao encontrei esse item.', 'kb', 'none'); END IF;
    IF a = 'bought' THEN
      UPDATE supplies SET units_total = COALESCE(pack_size, units_total), started_on = CURRENT_DATE, paused_days = 0, alert_notified_on = NULL WHERE id = v_id;
      RETURN jsonb_build_object('text', 'Anotado! Recomecei a contagem de ' || s.item || ': ' || COALESCE(s.pack_size, s.units_total) || ' unidades.', 'kb', 'none');
    ELSE
      RETURN jsonb_build_object('text', 'Combinado, vou lembrar no proximo resumo.', 'kb', 'none');
    END IF;
  END IF;

  SELECT * INTO r FROM reminders WHERE id = v_id AND user_id = p_user;
  IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Nao encontrei esse lembrete.', 'kb', 'none'); END IF;
  IF a = 'done' THEN
    UPDATE reminders SET status = 'done' WHERE id = v_id;
    UPDATE notifications SET state = 'cancelled' WHERE reminder_id = v_id AND state = 'pending';
    UPDATE fin_entries SET status = 'paid', paid_on = f_fin_today(p_user), occurred_on = f_fin_today(p_user)
    WHERE reminder_id = v_id AND user_id = p_user AND status = 'pending' RETURNING * INTO v_fin;
    IF v_fin.id IS NOT NULL THEN
      RETURN jsonb_build_object('text', CASE WHEN v_fin.kind = 'income' THEN 'Recebido: ' ELSE 'Pago: ' END || v_fin.description || ' ' || f_brl(v_fin.amount) || '.', 'kb', 'none');
    END IF;
    RETURN jsonb_build_object('text', 'Feito: ' || r.title, 'kb', 'none');
  ELSIF a = 'snz1h' THEN
    UPDATE notifications SET state = 'cancelled' WHERE reminder_id = v_id AND state = 'pending';
    INSERT INTO notifications(user_id, reminder_id, type, fire_at) VALUES (p_user, v_id, 'reminder', now() + interval '1 hour');
    RETURN jsonb_build_object('text', 'Adiado em 1 hora: ' || r.title, 'kb', 'none');
  ELSIF a = 'snzt' THEN
    RETURN jsonb_build_object('text', 'Adiar "' || r.title || '" para amanha. No mesmo horario ou em outro?', 'kb', 'snooze', 'rid', v_id);
  ELSIF a = 'snzs' THEN
    v_new := ((CURRENT_DATE + 1) + ((COALESCE(r.due_at, now()) AT TIME ZONE tz)::time)) AT TIME ZONE tz;
    RETURN f_provide_time(p_user, v_id, v_new);
  ELSIF a = 'snzo' THEN
    RETURN jsonb_build_object('text', 'Para que dia e horario? (ex.: amanha 15h)', 'kb', 'none',
      'state', jsonb_build_object('kind', 'snooze', 'reminder_id', v_id)::text);
  END IF;
  RETURN jsonb_build_object('text', 'Nao entendi esse botao.', 'kb', 'none');
END $function$;
