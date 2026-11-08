-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_summary_data_base(p_user bigint)
-- Origem da definicao atual: 013_extras.sql (linha 706)
-- Definicoes (migracao:linha), da mais antiga a atual: 009_resumos.sql:38, 013_extras.sql:706
-- Renomeada de f_summary_data para f_summary_data_base em 018_resumo_fase4.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_summary_data_base).
CREATE OR REPLACE FUNCTION f_summary_data(p_user bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'agente', 'public'
AS $$
DECLARE
  tz text; today date; ps date; pe date; v jsonb;
  d0 timestamptz; d1 timestamptz; d2 timestamptz;
BEGIN
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  today := (now() AT TIME ZONE tz)::date;
  d0 := today::timestamp AT TIME ZONE tz; d1 := (today + 1)::timestamp AT TIME ZONE tz; d2 := (today + 2)::timestamp AT TIME ZONE tz;
  SELECT p_start, p_end INTO ps, pe FROM f_fin_period(p_user, 0);
  SELECT jsonb_build_object(
    'today_reminders', COALESCE((SELECT jsonb_agg(jsonb_build_object('time', to_char(r.due_at AT TIME ZONE tz, 'HH24:MI'), 'title', r.title) ORDER BY r.due_at)
        FROM reminders r WHERE r.user_id = p_user AND r.kind = 'reminder' AND r.status = 'pending' AND r.due_at >= d0 AND r.due_at < d1
          AND NOT EXISTS (SELECT 1 FROM fin_entries f WHERE f.reminder_id = r.id)), '[]'::jsonb),
    'overdue_today', COALESCE((SELECT jsonb_agg(jsonb_build_object('time', to_char(r.due_at AT TIME ZONE tz, 'HH24:MI'), 'title', r.title) ORDER BY r.due_at)
        FROM reminders r WHERE r.user_id = p_user AND r.kind = 'reminder' AND r.status = 'pending' AND r.due_at >= d0 AND r.due_at <= now()
          AND NOT EXISTS (SELECT 1 FROM fin_entries f WHERE f.reminder_id = r.id)), '[]'::jsonb),
    'tomorrow_reminders', COALESCE((SELECT jsonb_agg(jsonb_build_object('time', to_char(r.due_at AT TIME ZONE tz, 'HH24:MI'), 'title', r.title) ORDER BY r.due_at)
        FROM reminders r WHERE r.user_id = p_user AND r.kind = 'reminder' AND r.status = 'pending' AND r.due_at >= d1 AND r.due_at < d2
          AND NOT EXISTS (SELECT 1 FROM fin_entries f WHERE f.reminder_id = r.id)), '[]'::jsonb),
    'supplies', COALESCE((SELECT jsonb_agg(jsonb_build_object('item', item, 'units_left', units_left, 'runs_out_on', to_char(runs_out_on, 'DD/MM')))
        FROM supplies_status WHERE user_id = p_user AND status = 'active' AND alert_on <= today), '[]'::jsonb),
    'bills', COALESCE((SELECT jsonb_agg(jsonb_build_object('description', description, 'amount', amount, 'due', to_char(due_on, 'DD/MM'),
          'late', due_on < today, 'today', due_on = today, 'tomorrow', due_on = today + 1, 'kind', kind) ORDER BY due_on, id)
        FROM (SELECT * FROM fin_entries WHERE user_id = p_user AND status = 'pending' AND kind = 'expense' AND due_on <= today + 7 ORDER BY due_on, id LIMIT 8) b), '[]'::jsonb),
    'yesterday_spent', (SELECT sum(amount) FROM fin_entries WHERE user_id = p_user AND kind = 'expense' AND status = 'paid' AND occurred_on = today - 1),
    'budget_alerts', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', c.name, 'spent', s.sp, 'budget', c.budget, 'pct', round(s.sp / c.budget * 100)) ORDER BY s.sp / c.budget DESC)
        FROM fin_categories c CROSS JOIN LATERAL (SELECT f_fin_spent(p_user, c.id, ps, pe) AS sp) s
        WHERE c.user_id = p_user AND c.kind = 'expense' AND c.budget IS NOT NULL AND s.sp / c.budget >= 0.8), '[]'::jsonb),
    'cards', COALESCE((SELECT jsonb_agg(q.x ORDER BY (q.x->>'days')::int) FROM (SELECT f_card_due_info(fc.id) AS x FROM fin_cards fc WHERE fc.user_id = p_user AND fc.active) q WHERE q.x IS NOT NULL), '[]'::jsonb)
  ) INTO v;
  RETURN v;
END $$;
