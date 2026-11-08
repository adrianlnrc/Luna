-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_suggest_pick(p_user bigint, p_dry boolean)
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 561)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:561
CREATE OR REPLACE FUNCTION agente.f_suggest_pick(p_user bigint, p_dry boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  tz text; v_today date; v_dom int; r record; v_kind text; v_key text; v_txt text; v_data jsonb; v_n int;
  dias text[] := ARRAY['domingos', 'segundas', 'terças', 'quartas', 'quintas', 'sextas', 'sábados'];
BEGIN
  IF NOT f_mem_sw(p_user, 'suggest_enabled') THEN RETURN jsonb_build_object('suggest', false, 'reason', 'disabled'); END IF;
  SELECT coalesce(nullif(timezone, ''), 'America/Sao_Paulo') INTO tz FROM users WHERE id = p_user;
  IF tz IS NULL THEN RETURN jsonb_build_object('suggest', false, 'reason', 'no_user'); END IF;
  v_today := (now() AT TIME ZONE tz)::date; v_dom := extract(day FROM v_today)::int;
  IF EXISTS (SELECT 1 FROM suggestions_log WHERE user_id = p_user AND day = v_today) THEN
    RETURN jsonb_build_object('suggest', false, 'reason', 'already_today');
  END IF;

  -- (a) conta que costuma aparecer todo mes
  SELECT x.norm_desc, x.descr, x.dia, x.valor, x.meses INTO r
    FROM (SELECT e.norm_desc,
                 (array_agg(e.description ORDER BY e.d DESC))[1] AS descr,
                 count(DISTINCT date_trunc('month', e.d)) AS meses,
                 percentile_disc(0.5) WITHIN GROUP (ORDER BY extract(day FROM e.d)) ::int AS dia,
                 max(extract(day FROM e.d)) - min(extract(day FROM e.d)) AS spread,
                 percentile_disc(0.5) WITHIN GROUP (ORDER BY e.amount) AS valor,
                 max(e.d) AS ultimo
            FROM (SELECT fe.norm_desc, fe.description, fe.amount, coalesce(fe.due_on, fe.occurred_on) AS d
                    FROM fin_entries fe
                   WHERE fe.user_id = p_user AND fe.kind = 'expense' AND fe.status IN ('paid', 'pending')
                     AND fe.recurring_id IS NULL AND coalesce(fe.installments, 1) <= 1 AND coalesce(fe.installment_no, 1) = 1
                     AND coalesce(fe.due_on, fe.occurred_on) >= date_trunc('month', v_today)::date - interval '6 months'
                     AND coalesce(fe.due_on, fe.occurred_on) <  date_trunc('month', v_today)::date) e
           GROUP BY e.norm_desc) x
   WHERE x.meses >= 3 AND x.spread <= 4 AND x.ultimo >= v_today - 75
     AND v_dom >= x.dia - 2 AND v_dom <= x.dia + 10
     AND NOT EXISTS (SELECT 1 FROM fin_entries t WHERE t.user_id = p_user AND t.norm_desc = x.norm_desc
                        AND coalesce(t.due_on, t.occurred_on) >= date_trunc('month', v_today)::date
                        AND coalesce(t.due_on, t.occurred_on) <  (date_trunc('month', v_today) + interval '1 month')::date)
     AND NOT EXISTS (SELECT 1 FROM fin_recurring fr WHERE fr.user_id = p_user AND fr.active AND f_norm(fr.description) = x.norm_desc)
     AND NOT EXISTS (SELECT 1 FROM suggestions_log s WHERE s.user_id = p_user AND s.key = 'conta:' || x.norm_desc AND s.created_at > now() - interval '30 days')
   ORDER BY x.meses DESC, x.ultimo DESC LIMIT 1;
  IF FOUND THEN
    v_kind := 'conta'; v_key := 'conta:' || r.norm_desc;
    v_txt := initcap(r.descr) || ' costuma cair no dia ' || r.dia || ' (em geral ' || f_brl(r.valor) || '). Já cadastro este mês?';
    v_data := jsonb_build_object('description', r.descr, 'day', r.dia, 'amount', r.valor, 'months', r.meses);
  ELSE
    -- (b) lembrete que sempre se repete e ainda nao tem repeticao
    SELECT x.nt, x.titulo, x.n, x.dows INTO r
      FROM (SELECT f_norm(rm.title) AS nt, (array_agg(rm.title ORDER BY rm.created_at DESC))[1] AS titulo, count(*) AS n,
                   array_agg(DISTINCT extract(dow FROM rm.due_at AT TIME ZONE tz)::int) AS dows
              FROM reminders rm
             WHERE rm.user_id = p_user AND rm.kind = 'reminder' AND rm.repeat_rule IS NULL AND rm.repeat_of IS NULL AND rm.card_id IS NULL
                   AND rm.status <> 'cancelled' AND rm.due_at IS NOT NULL AND rm.created_at > now() - interval '60 days'
             GROUP BY f_norm(rm.title) HAVING count(*) >= 3) x
     WHERE x.nt <> ''
       AND NOT EXISTS (SELECT 1 FROM reminders q WHERE q.user_id = p_user AND f_norm(q.title) = x.nt AND q.repeat_rule IS NOT NULL AND q.status IN ('pending', 'awaiting_time'))
       AND NOT EXISTS (SELECT 1 FROM suggestions_log s WHERE s.user_id = p_user AND s.key = 'lembrete:' || x.nt AND s.created_at > now() - interval '30 days')
     ORDER BY x.n DESC LIMIT 1;
    IF FOUND THEN
      v_kind := 'lembrete'; v_key := 'lembrete:' || r.nt;
      v_txt := 'Você já criou "' || r.titulo || '" ' || r.n || ' vezes nos últimos dois meses. Quer que eu deixe repetir sozinho'
               || CASE WHEN cardinality(r.dows) = 1 THEN ' toda semana, às ' || dias[r.dows[1] + 1] ELSE '' END || '?';
      v_data := jsonb_build_object('title', r.titulo, 'times', r.n, 'weekday', CASE WHEN cardinality(r.dows) = 1 THEN r.dows[1] END);
    END IF;
  END IF;

  IF v_kind IS NULL THEN RETURN jsonb_build_object('suggest', false, 'reason', 'no_pattern'); END IF;
  IF NOT p_dry THEN
    INSERT INTO suggestions_log(user_id, day, kind, key, texto) VALUES (p_user, v_today, v_kind, v_key, v_txt) ON CONFLICT (user_id, day) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n = 0 THEN RETURN jsonb_build_object('suggest', false, 'reason', 'already_today'); END IF;
  END IF;
  RETURN jsonb_build_object('suggest', true, 'kind', v_kind, 'key', v_key, 'text', v_txt, 'data', v_data, 'dry', p_dry);
END $$;
