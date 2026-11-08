-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ag_confirm(p_pid bigint)
-- Origem da definicao atual: 012_agenda.sql (linha 130)
-- Definicoes (migracao:linha), da mais antiga a atual: 012_agenda.sql:130
CREATE OR REPLACE FUNCTION f_ag_confirm(p_pid bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE pd agenda_pending%ROWTYPE; tz text; t text; n int; conf text; rec boolean;
BEGIN
  SELECT * INTO pd FROM agenda_pending WHERE id = p_pid;
  IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Não encontrei essa ação.', 'kb', 'none'); END IF;
  SELECT timezone INTO tz FROM users WHERE id = pd.user_id;
  n := (CASE WHEN pd.payload->>'attendees' ~ '^[0-9]+$' THEN (pd.payload->>'attendees')::int ELSE 0 END);
  rec := coalesce(pd.payload->>'recurring_id', '') <> '';
  SELECT string_agg((c->>'title') || ' (' || to_char((c->>'start')::timestamptz AT TIME ZONE tz, 'HH24:MI') || '–' || to_char((c->>'end')::timestamptz AT TIME ZONE tz, 'HH24:MI') || ')', ', ')
    INTO conf FROM jsonb_array_elements(coalesce(pd.payload->'conflicts', '[]'::jsonb)) c;
  IF pd.kind = 'cancel' THEN
    IF rec THEN
      t := 'Cancelar "' || pd.title || '" (' || f_ag_fmt(pd.old_start, tz) || ')? Esse compromisso se repete: cancelo só este dia ou a série inteira?';
      IF n > 0 THEN t := t || ' Os ' || n || ' convidado(s) serão avisados pelo Google.'; END IF;
      RETURN jsonb_build_object('text', t, 'kb', 'ag_scope', 'rid', pd.id);
    END IF;
    t := 'Cancelar "' || pd.title || '" (' || f_ag_fmt(pd.old_start, tz) || ')? Apago do Google Agenda e cancelo os avisos que eu tinha.';
    IF n > 0 THEN t := t || ' Os ' || n || ' convidado(s) serão avisados pelo Google.'; END IF;
    RETURN jsonb_build_object('text', t, 'kb', 'ag_confirm', 'rid', pd.id);
  ELSIF pd.kind = 'move' THEN
    t := 'Mover "' || pd.title || '" de ' || f_ag_fmt(pd.old_start, tz) || ' para ' || f_ag_fmt(pd.new_start, tz) || '?';
    IF rec THEN t := t || ' Esse compromisso se repete: movo só esta ocorrência, a série continua igual.'; END IF;
    IF n > 0 THEN t := t || ' Os ' || n || ' convidado(s) serão avisados pelo Google.'; END IF;
    IF conf IS NOT NULL THEN t := t || ' Atenção: conflita com ' || conf || '.'; END IF;
    RETURN jsonb_build_object('text', t, 'kb', 'ag_confirm', 'rid', pd.id);
  END IF;
  RETURN jsonb_build_object('text', 'Confirmar?', 'kb', 'ag_confirm', 'rid', pd.id);
END $$;
