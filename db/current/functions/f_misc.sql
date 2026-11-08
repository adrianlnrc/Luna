-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_misc(p_user bigint, p jsonb)
-- Origem da definicao atual: 013_extras.sql (linha 665)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:665
CREATE OR REPLACE FUNCTION f_misc(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE kind text := coalesce(p->>'kind', ''); q text := f_norm(p->>'title'); toks text[]; tz text; t text := ''; r record; k integer := 0; n integer; nxt timestamptz; ttl text;
BEGIN
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  IF kind = 'calendar_link' THEN
    RETURN jsonb_build_object('text', 'Aqui está o seu Google Agenda (abre o Google Agenda): https://calendar.google.com/calendar/u/0/r', 'kb', 'none');
  END IF;
  IF kind = 'reminder_history' THEN
    SELECT array_agg(x) INTO toks FROM unnest(string_to_array(q, ' ')) x
     WHERE length(x) >= 3 AND x NOT IN ('que','com','pra','para','dos','das','meu','minha','voce','aviso','avisou','avisar','lembrete','sobre','vc');
    IF toks IS NULL THEN
      RETURN jsonb_build_object('text', 'Sobre qual lembrete? Ex.: "você me avisou da conta de luz?".', 'kb', 'none');
    END IF;
    FOR r IN
      SELECT n.sent_at, n.type, rm.title, rm.due_at FROM notifications n JOIN reminders rm ON rm.id = n.reminder_id
      WHERE n.user_id = p_user AND n.state = 'sent' AND n.sent_at > now() - interval '120 days'
        AND (SELECT bool_and(f_norm(rm.title) LIKE '%' || x || '%') FROM unnest(toks) x)
      ORDER BY n.sent_at DESC LIMIT 5
    LOOP
      k := k + 1;
      t := t || E'\n- ' || r.title || ': ' || CASE r.type WHEN 'pre_alert' THEN 'pré-aviso' WHEN 'repeat' THEN 'repetição' ELSE 'lembrete' END || ' enviado em ' || to_char(r.sent_at AT TIME ZONE tz, 'DD/MM "às" HH24:MI');
    END LOOP;
    IF k > 0 THEN RETURN jsonb_build_object('text', 'Sim, já te avisei:' || t, 'kb', 'none'); END IF;
    SELECT rm.title, n.fire_at INTO ttl, nxt FROM reminders rm JOIN notifications n ON n.reminder_id = rm.id AND n.state = 'pending'
     WHERE rm.user_id = p_user AND rm.status = 'pending' AND (SELECT bool_and(f_norm(rm.title) LIKE '%' || x || '%') FROM unnest(toks) x)
     ORDER BY n.fire_at LIMIT 1;
    IF ttl IS NOT NULL THEN
      RETURN jsonb_build_object('text', 'Ainda não te avisei. O lembrete "' || ttl || '" está agendado para ' || to_char(nxt AT TIME ZONE tz, 'DD/MM "às" HH24:MI') || '.', 'kb', 'none');
    END IF;
    SELECT count(*) INTO n FROM reminders rm WHERE rm.user_id = p_user AND (SELECT bool_and(f_norm(rm.title) LIKE '%' || x || '%') FROM unnest(toks) x);
    IF n > 0 THEN RETURN jsonb_build_object('text', 'Achei o lembrete, mas não tenho registro de aviso enviado nos últimos 120 dias.', 'kb', 'none'); END IF;
    RETURN jsonb_build_object('text', 'Não achei nenhum lembrete parecido com "' || btrim(p->>'title') || '", então não tenho registro de aviso.', 'kb', 'none');
  END IF;
  RETURN jsonb_build_object('text', 'Não entendi essa consulta.', 'kb', 'none');
EXCEPTION WHEN others THEN
  RAISE WARNING 'f_misc: %', SQLERRM;
  RETURN jsonb_build_object('text', 'Não consegui consultar agora. Tente de novo.', 'kb', 'none');
END $$;
