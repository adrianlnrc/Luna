-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_cb(p_user bigint, p_action text, p_id bigint)
-- Origem da definicao atual: 011_planejamento.sql (linha 241)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:397, 011_planejamento.sql:241
CREATE OR REPLACE FUNCTION f_fin_cb(p_user bigint, p_action text, p_id bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE e fin_entries%ROWTYPE; v_note text := ''; g fin_goals%ROWTYPE;
BEGIN
  IF p_id < 0 THEN
    IF p_action = 'fkeep' THEN RETURN jsonb_build_object('text', 'Ok, mantive a meta.', 'kb', 'none'); END IF;
    SELECT * INTO g FROM fin_goals WHERE id = -p_id AND user_id = p_user;
    IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Essa meta já foi apagada.', 'kb', 'none'); END IF;
    DELETE FROM fin_goals WHERE id = g.id;
    RETURN jsonb_build_object('text', 'Apaguei a meta ' || g.name || '.', 'kb', 'none');
  END IF;
  SELECT * INTO e FROM fin_entries WHERE id = p_id AND user_id = p_user;
  IF p_action = 'fkeep' THEN RETURN jsonb_build_object('text', 'Ok, mantive.', 'kb', 'none'); END IF;
  IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Esse lançamento já foi desfeito ou apagado.', 'kb', 'none'); END IF;
  IF p_action = 'fok' THEN
    IF e.status <> 'draft' THEN RETURN jsonb_build_object('text', 'Esse lançamento já estava confirmado.', 'kb', 'none'); END IF;
    IF e.due_on IS NOT NULL THEN
      UPDATE fin_entries SET status = 'pending' WHERE id = e.id;
      PERFORM f_fin_remind(e.id);
      RETURN jsonb_build_object('text', 'Anotei a pagar: ' || e.description || ' ' || f_brl(e.amount) || ', vence ' || to_char(e.due_on, 'DD/MM') || '. Te aviso no dia.', 'kb', 'fin_undo', 'rid', e.id);
    END IF;
    UPDATE fin_entries SET status = 'paid', paid_on = occurred_on WHERE id = e.id;
    IF e.kind = 'expense' THEN v_note := f_fin_budget_note(p_user, e.category_id, e.amount, e.occurred_on); END IF;
    RETURN jsonb_build_object('text', 'Confirmado: ' || e.description || ' ' || f_brl(e.amount) || '.' || v_note, 'kb', 'fin_undo', 'rid', e.id);
  ELSIF p_action = 'fno' THEN
    IF e.status = 'draft' THEN DELETE FROM fin_entries WHERE id = e.id; END IF;
    RETURN jsonb_build_object('text', 'Ok, descartei. Se quiser, me diga o valor certo.', 'kb', 'none');
  ELSIF p_action IN ('fundo', 'fdel') THEN
    IF e.reminder_id IS NOT NULL THEN
      UPDATE reminders SET status = 'done' WHERE id = e.reminder_id;
      UPDATE notifications SET state = 'cancelled' WHERE reminder_id = e.reminder_id AND state = 'pending';
    END IF;
    IF e.recurring_id IS NOT NULL AND p_action = 'fundo' THEN
      UPDATE fin_recurring SET active = false WHERE id = e.recurring_id AND created_at > now() - interval '30 minutes';
    END IF;
    IF e.series_id IS NOT NULL THEN DELETE FROM fin_entries WHERE series_id = e.series_id AND user_id = p_user;
    ELSE DELETE FROM fin_entries WHERE id = e.id; END IF;
    RETURN jsonb_build_object('text', CASE WHEN p_action = 'fundo' THEN 'Desfeito: ' ELSE 'Apaguei: ' END || e.description || ' ' || f_brl(e.amount) || '.', 'kb', 'none');
  END IF;
  RETURN jsonb_build_object('text', 'Não entendi esse botão.', 'kb', 'none');
END $$;
