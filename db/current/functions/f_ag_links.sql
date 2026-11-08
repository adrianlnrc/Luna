-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ag_links(p_user bigint, p_event text, p_rec text, p_title text, p_start timestamptz, p_scope text)
-- Origem da definicao atual: 012_agenda.sql (linha 83)
-- Definicoes (migracao:linha), da mais antiga a atual: 012_agenda.sql:83
CREATE OR REPLACE FUNCTION f_ag_links(p_user bigint, p_event text, p_rec text, p_title text, p_start timestamptz, p_scope text)
RETURNS bigint[] LANGUAGE sql STABLE SET search_path TO 'agente', 'public' AS $$
  SELECT coalesce(array_agg(r.id), '{}')
  FROM reminders r
  WHERE r.user_id = p_user AND r.status = 'pending'
    AND (
         (p_event <> '' AND r.calendar_event_id = p_event)
      OR (p_rec <> '' AND r.calendar_event_id = p_rec AND (p_scope = 'a' OR (r.due_at IS NOT NULL AND p_start IS NOT NULL AND abs(extract(epoch FROM r.due_at - p_start)) < 60)))
      OR (p_rec <> '' AND r.series_id IN (SELECT s.id FROM agenda_series s WHERE s.user_id = p_user AND s.calendar_event_id = p_rec)
          AND (p_scope = 'a' OR (r.due_at IS NOT NULL AND p_start IS NOT NULL AND abs(extract(epoch FROM r.due_at - p_start)) < 60)))
      OR (r.kind = 'event' AND r.calendar_event_id IS NULL AND f_norm(r.title) = f_norm(p_title)
          AND r.due_at IS NOT NULL AND p_start IS NOT NULL AND abs(extract(epoch FROM r.due_at - p_start)) < 60)
    )
$$;
