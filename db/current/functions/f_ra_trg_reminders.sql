-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ra_trg_reminders()
-- Origem da definicao atual: 033_acoes_recentes.sql (linha 60)
-- Definicoes (migracao:linha), da mais antiga a atual: 033_acoes_recentes.sql:60
CREATE OR REPLACE FUNCTION agente.f_ra_trg_reminders() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE tz text; ck text;
BEGIN
  IF NEW.repeat_of IS NOT NULL OR NEW.card_id IS NOT NULL OR NEW.status NOT IN ('pending', 'awaiting_time') THEN RETURN NEW; END IF;
  IF NEW.kind = 'event' AND coalesce(NEW.calendar_event_id, '') = '' THEN RETURN NEW; END IF;
  SELECT coalesce(nullif(timezone, ''), 'America/Sao_Paulo'), calendar_key INTO tz, ck FROM users WHERE id = NEW.user_id;
  PERFORM f_ra_log(NEW.user_id, NEW.kind, NEW.id, NEW.calendar_event_id, ck,
    NEW.title || CASE WHEN NEW.due_at IS NOT NULL THEN ', ' || to_char(NEW.due_at AT TIME ZONE tz, 'DD/MM HH24:MI') ELSE '' END);
  RETURN NEW;
EXCEPTION WHEN others THEN
  RETURN NEW;
END $$;
