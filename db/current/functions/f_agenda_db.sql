-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agenda_db(p_user bigint, p_from timestamptz, p_to timestamptz)
-- Origem da definicao atual: 003_functions.sql (linha 179)
-- Definicoes (migracao:linha), da mais antiga a atual: 003_functions.sql:179
CREATE OR REPLACE FUNCTION f_agenda_db(p_user bigint, p_from timestamptz, p_to timestamptz)
RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    'reminders', COALESCE((SELECT jsonb_agg(jsonb_build_object('title', r.title, 'due', to_char(r.due_at AT TIME ZONE u.timezone, 'DD/MM HH24:MI')) ORDER BY r.due_at)
                           FROM reminders r JOIN users u ON u.id = r.user_id
                           WHERE r.user_id = p_user AND r.kind = 'reminder' AND r.status = 'pending'
                             AND r.due_at >= p_from AND r.due_at < p_to), '[]'::jsonb),
    'supplies',  COALESCE((SELECT jsonb_agg(jsonb_build_object('item', item, 'units_left', units_left, 'runs_out_on', to_char(runs_out_on, 'DD/MM')))
                           FROM supplies_status WHERE user_id = p_user AND status = 'active' AND alert_on <= p_to::date), '[]'::jsonb));
$$;
