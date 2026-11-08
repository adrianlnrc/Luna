-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_set_prefs(p_user bigint, p jsonb)
-- Origem da definicao atual: 034_tom_preferencias.sql (linha 2)
-- Definicoes (migracao:linha), da mais antiga a atual: 011_planejamento.sql:284, 012_agenda.sql:688, 034_tom_preferencias.sql:2
CREATE OR REPLACE FUNCTION agente.f_set_prefs(p_user bigint, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE
  t text := ''; v text; tm time; n integer; ws time; we time; u users%ROWTYPE;
BEGIN
  IF nullif(p->>'lead', '') IS NOT NULL THEN
    UPDATE users SET default_lead_minutes = (p->>'lead')::int WHERE id = p_user;
    t := t || E'\nAviso padrão: ' || (p->>'lead') || ' min antes dos compromissos.';
  END IF;
  IF nullif(p->>'supply_days', '') IS NOT NULL THEN
    UPDATE users SET supply_alert_days = (p->>'supply_days')::int WHERE id = p_user;
    t := t || E'\nAviso de estoque: ' || (p->>'supply_days') || ' dia(s) antes de acabar.';
  END IF;
  v := nullif(btrim(coalesce(p->>'summary', '')), '');
  IF v IS NOT NULL THEN
    IF lower(v) IN ('off', 'desligar') THEN UPDATE users SET morning_enabled = false WHERE id = p_user; t := t || E'\nDesliguei o resumo da manhã.';
    ELSIF lower(v) = 'on' THEN UPDATE users SET morning_enabled = true WHERE id = p_user; t := t || E'\nLiguei o resumo da manhã.';
    ELSE BEGIN tm := v::time; UPDATE users SET summary_time = tm, morning_enabled = true WHERE id = p_user; t := t || E'\nResumo da manhã às ' || to_char(tm, 'HH24:MI') || '.';
      EXCEPTION WHEN others THEN t := t || E'\nNão entendi o horário "' || v || '" do resumo da manhã.'; END;
    END IF;
  END IF;
  v := nullif(btrim(coalesce(p->>'evening', '')), '');
  IF v IS NOT NULL THEN
    IF lower(v) = 'off' THEN UPDATE users SET evening_enabled = false WHERE id = p_user; t := t || E'\nDesliguei o resumo do fim do dia.';
    ELSIF lower(v) = 'on' THEN UPDATE users SET evening_enabled = true WHERE id = p_user; t := t || E'\nLiguei o resumo do fim do dia.';
    ELSE BEGIN tm := v::time; UPDATE users SET evening_time = tm, evening_enabled = true WHERE id = p_user; t := t || E'\nResumo do fim do dia às ' || to_char(tm, 'HH24:MI') || '.';
      EXCEPTION WHEN others THEN t := t || E'\nNão entendi o horário "' || v || '" do resumo do fim do dia.'; END;
    END IF;
  END IF;
  IF nullif(btrim(coalesce(p->>'nickname', '')), '') IS NOT NULL THEN
    UPDATE users SET nickname = left(btrim(p->>'nickname'), 30) WHERE id = p_user;
    t := t || E'\nDaqui pra frente te chamo de ' || left(btrim(p->>'nickname'), 30) || '.';
  END IF;
  IF nullif(p->>'no_emoji', '') IS NOT NULL THEN
    UPDATE users SET no_emoji = (p->>'no_emoji')::boolean WHERE id = p_user;
    t := t || CASE WHEN (p->>'no_emoji')::boolean THEN E'\nBeleza, sem emoji daqui pra frente.' ELSE E'\nCombinado, volto a usar emoji.' END;
  END IF;
  v := nullif(btrim(coalesce(p->>'timezone', '')), '');
  IF v IS NOT NULL THEN
    SELECT count(*) INTO n FROM pg_timezone_names WHERE name = v;
    IF n = 1 THEN UPDATE users SET timezone = v WHERE id = p_user; t := t || E'\nFuso ajustado para ' || v || '. Lembretes já marcados continuam no horário absoluto.';
    ELSE t := t || E'\nNão reconheci o fuso "' || v || '". Diga a cidade, ex.: Lisboa.'; END IF;
  END IF;
  -- expediente (usado na busca de horario livre)
  IF nullif(btrim(coalesce(p->>'work_start', '')), '') IS NOT NULL OR nullif(btrim(coalesce(p->>'work_end', '')), '') IS NOT NULL THEN
    SELECT * INTO u FROM users WHERE id = p_user;
    ws := u.work_start; we := u.work_end;
    BEGIN
      IF nullif(btrim(coalesce(p->>'work_start', '')), '') IS NOT NULL THEN ws := btrim(p->>'work_start')::time; END IF;
      IF nullif(btrim(coalesce(p->>'work_end', '')), '') IS NOT NULL THEN we := btrim(p->>'work_end')::time; END IF;
      IF we <= ws THEN
        t := t || E'\nO fim do expediente precisa ser depois do início.';
      ELSE
        UPDATE users SET work_start = ws, work_end = we WHERE id = p_user;
        t := t || E'\nExpediente: ' || to_char(ws, 'HH24:MI') || ' às ' || to_char(we, 'HH24:MI') || ' (uso para achar horário livre).';
      END IF;
    EXCEPTION WHEN others THEN t := t || E'\nNão entendi o horário do expediente.'; END;
  END IF;
  IF t = '' THEN t := E'\nNão achei nada para mudar.'; END IF;
  RETURN jsonb_build_object('text', CASE WHEN length(t) - length(replace(t, E'\n', '')) <= 1 THEN btrim(t, E'\n') ELSE 'Feito:' || t END);
END $function$;
