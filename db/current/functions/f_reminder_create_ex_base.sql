-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_reminder_create_ex_base(p_user bigint, p_title text, p_due timestamptz, p_shared boolean, p_lead integer, p_source text, p_repeat jsonb)
-- Origem da definicao atual: 028_custo_ia_anuais.sql (linha 159) [dentro de bloco DO/EXECUTE, criacao condicional]
-- Definicoes (migracao:linha), da mais antiga a atual: 028_custo_ia_anuais.sql:159
CREATE FUNCTION agente.f_reminder_create_ex_base(p_user bigint, p_title text, p_due timestamptz, p_shared boolean DEFAULT false,
                                                 p_lead integer DEFAULT NULL, p_source text DEFAULT 'text', p_repeat jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'agente','public' AS $b$
DECLARE res jsonb; v_until date; v_cnt integer; v_rid bigint; v_grp uuid; tz text; loc timestamp; v_lead integer;
BEGIN
  IF lower(nullif(p_repeat->>'freq', '')) IS DISTINCT FROM 'yearly' THEN
    RETURN agente.f_reminder_create_ex_base_pre_m4(p_user, p_title, p_due, p_shared, p_lead, p_source, p_repeat);
  END IF;
  v_until := agente.f_safe_date(p_repeat->>'until');
  BEGIN v_cnt := nullif(p_repeat->>'count', '')::int; EXCEPTION WHEN others THEN v_cnt := NULL; END;
  v_lead := coalesce(p_lead, 21600);
  res := agente.f_reminder_create_ex_base_pre_m4(p_user, p_title, p_due, p_shared, v_lead, p_source, NULL);
  v_rid := (res->>'reminder_id')::bigint;
  SELECT shared_group INTO v_grp FROM agente.reminders WHERE id = v_rid;
  UPDATE agente.reminders SET repeat_rule = 'yearly', repeat_until = v_until,
         repeat_left = CASE WHEN v_cnt IS NOT NULL AND v_cnt >= 1 THEN v_cnt - 1 END
   WHERE id = v_rid OR (v_grp IS NOT NULL AND shared_group = v_grp);
  SELECT timezone INTO tz FROM agente.users WHERE id = p_user;
  loc := p_due AT TIME ZONE tz;
  RETURN res || jsonb_build_object('repeat_rule', 'yearly', 'repeat_text',
    'todo ano em ' || to_char(loc, 'DD/MM') || ' às ' || to_char(loc, 'HH24:MI')
    || CASE WHEN v_lead >= 1440 THEN ' (aviso ' || (v_lead / 1440) || ' dias antes)' ELSE '' END
    || CASE WHEN v_until IS NOT NULL THEN ' (até ' || to_char(v_until, 'DD/MM/YYYY') || ')'
            WHEN v_cnt IS NOT NULL AND v_cnt > 1 THEN ' (' || v_cnt || ' vezes)' ELSE '' END);
END $b$;
