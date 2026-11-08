-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_reminder_create_ex_base_pre_m4(p_user bigint, p_title text, p_due timestamptz, p_shared boolean, p_lead integer, p_source text, p_repeat jsonb)
-- Origem da definicao atual: 013_extras.sql (linha 211)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:211
-- Renomeada de f_reminder_create_ex_base para f_reminder_create_ex_base_pre_m4 em 028_custo_ia_anuais.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_reminder_create_ex_base_pre_m4).
CREATE OR REPLACE FUNCTION f_reminder_create_ex(p_user bigint, p_title text, p_due timestamptz, p_shared boolean DEFAULT false,
    p_lead integer DEFAULT NULL, p_source text DEFAULT 'text', p_repeat jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE res jsonb; v_freq text := lower(nullif(p_repeat->>'freq', '')); v_until date := f_safe_date(p_repeat->>'until');
        v_cnt integer; v_rid bigint; v_grp uuid; tz text; loc timestamp; lbl text;
        dow text[] := ARRAY['domingo','segunda','terça','quarta','quinta','sexta','sábado'];
BEGIN
  BEGIN v_cnt := nullif(p_repeat->>'count', '')::int; EXCEPTION WHEN others THEN v_cnt := NULL; END;
  res := f_create_reminder(p_user, p_title, p_due, p_shared, p_lead, 'reminder', NULL, coalesce(p_source, 'text'));
  IF v_freq IS NULL OR v_freq NOT IN ('daily','weekly','monthly') THEN RETURN res; END IF;
  v_rid := (res->>'reminder_id')::bigint;
  SELECT shared_group INTO v_grp FROM reminders WHERE id = v_rid;
  UPDATE reminders SET repeat_rule = v_freq, repeat_until = v_until,
         repeat_left = CASE WHEN v_cnt IS NOT NULL AND v_cnt >= 1 THEN v_cnt - 1 END
   WHERE id = v_rid OR (v_grp IS NOT NULL AND shared_group = v_grp);
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  loc := p_due AT TIME ZONE tz;
  lbl := CASE v_freq
    WHEN 'daily' THEN 'todo dia'
    WHEN 'weekly' THEN CASE WHEN extract(dow FROM loc) IN (0, 6) THEN 'todo ' ELSE 'toda ' END || dow[extract(dow FROM loc)::int + 1]
    ELSE 'todo dia ' || extract(day FROM loc)::int END || ' às ' || to_char(loc, 'HH24:MI') ||
    CASE WHEN v_until IS NOT NULL THEN ' (até ' || to_char(v_until, 'DD/MM/YYYY') || ')'
         WHEN v_cnt IS NOT NULL AND v_cnt > 1 THEN ' (' || v_cnt || ' vezes)' ELSE '' END;
  RETURN res || jsonb_build_object('repeat_rule', v_freq, 'repeat_text', lbl);
END $$;
