-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ag_cal(pd agenda_pending, p_scope text)
-- Origem da definicao atual: 012_agenda.sql (linha 331)
-- Definicoes (migracao:linha), da mais antiga a atual: 012_agenda.sql:331
CREATE OR REPLACE FUNCTION f_ag_cal(pd agenda_pending, p_scope text) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE n int := (CASE WHEN pd.payload->>'attendees' ~ '^[0-9]+$' THEN (pd.payload->>'attendees')::int ELSE 0 END); pl jsonb := pd.payload; att text;
BEGIN
  IF pd.kind = 'move' THEN
    RETURN jsonb_build_object('op', 'update', 'calendar_key', pd.calendar_key, 'pid', pd.id, 'event_id', pd.event_id,
      'start', f_ag_iso(pd.new_start), 'end', f_ag_iso(pd.new_end), 'send_updates', CASE WHEN n > 0 THEN 'all' ELSE 'none' END);
  ELSIF pd.kind = 'cancel' THEN
    RETURN jsonb_build_object('op', 'delete', 'calendar_key', pd.calendar_key, 'pid', pd.id,
      'event_id', CASE WHEN p_scope = 'a' AND coalesce(pl->>'recurring_id', '') <> '' THEN pl->>'recurring_id' ELSE pd.event_id END,
      'send_updates', CASE WHEN n > 0 THEN 'all' ELSE 'none' END);
  ELSIF pd.kind = 'create' THEN
    att := coalesce(pl->>'attendees', '');
    RETURN jsonb_build_object('op', 'create', 'calendar_key', pd.calendar_key, 'pid', pd.id,
      'summary', coalesce(pl->>'summary', pd.title), 'start', coalesce(pl->>'start', f_ag_iso(pd.new_start)), 'end', coalesce(pl->>'end', f_ag_iso(pd.new_end)),
      'location', coalesce(pl->>'location', ''), 'attendees', att,
      'meet', CASE WHEN coalesce(pl->>'meet', 'false') = 'true' THEN 'true' ELSE 'false' END,
      'repeat_freq', coalesce(pl->>'repeat_freq', ''), 'repeat_until', coalesce(pl->>'repeat_until', ''), 'repeat_count', coalesce(pl->>'repeat_count', ''),
      'force', CASE WHEN coalesce(pl->>'force', 'false') = 'true' THEN 'true' ELSE 'false' END,
      'send_updates', CASE WHEN att <> '' THEN 'all' ELSE 'none' END);
  ELSIF pd.kind = 'respond' THEN
    RETURN jsonb_build_object('op', 'respond', 'calendar_key', pd.calendar_key, 'pid', pd.id, 'event_id', pd.event_id,
      'response', coalesce(pl->>'response', 'accepted'));
  END IF;
  RETURN NULL;
END $$;
