-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agenda_cb(p_user bigint, p_data text)
-- Origem da definicao atual: 012_agenda.sql (linha 359)
-- Definicoes (migracao:linha), da mais antiga a atual: 012_agenda.sql:359
CREATE OR REPLACE FUNCTION f_agenda_cb(p_user bigint, p_data text) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  a text := split_part(p_data, ':', 1); v_id bigint := nullif(split_part(p_data, ':', 2), '')::bigint; v3 text := split_part(p_data, ':', 3);
  pd agenda_pending%ROWTYPE; pk agenda_pending%ROWTYPE; tz text; cal jsonb; idx int; t text; orig text;
  gone jsonb := jsonb_build_object('text', 'Essa ação já foi resolvida ou expirou.', 'kb', 'none');
BEGIN
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  IF a NOT IN ('agok', 'agno', 'agpk', 'agsc', 'agfy', 'agfo', 'agrs', 'agrn') THEN
    RETURN jsonb_build_object('text', 'Não entendi esse botão.', 'kb', 'none');
  END IF;
  SELECT * INTO pd FROM agenda_pending WHERE id = v_id AND user_id = p_user AND state = 'open';
  IF NOT FOUND THEN RETURN gone; END IF;

  IF a = 'agno' THEN
    UPDATE agenda_pending SET state = 'cancelled' WHERE user_id = p_user AND state = 'open' AND (id = pd.id OR (pd.grp IS NOT NULL AND grp = pd.grp));
    RETURN jsonb_build_object('text', CASE pd.kind WHEN 'move' THEN 'Ok, não movi nada.' WHEN 'cancel' THEN 'Ok, não cancelei nada.'
                                                    WHEN 'create' THEN 'Ok, não marquei nada.' ELSE 'Ok.' END, 'kb', 'none');
  END IF;

  IF a = 'agpk' THEN
    idx := coalesce(nullif(v3, '')::int, 0);
    IF pd.grp IS NULL THEN SELECT * INTO pk FROM agenda_pending WHERE id = pd.id;
    ELSE
      SELECT * INTO pk FROM agenda_pending WHERE id = (SELECT s.id FROM (SELECT x.id, row_number() OVER (ORDER BY x.id) rn FROM agenda_pending x
                             WHERE x.user_id = p_user AND x.grp = pd.grp AND x.state = 'open') s WHERE s.rn = idx);
    END IF;
    IF pk.id IS NULL THEN RETURN jsonb_build_object('text', 'Não achei essa opção. Peça de novo.', 'kb', 'none'); END IF;
    UPDATE agenda_pending SET state = 'cancelled' WHERE user_id = p_user AND state = 'open' AND grp IS NOT NULL AND grp = pd.grp AND id <> pk.id;
    RETURN f_ag_confirm(pk.id);
  END IF;

  IF a IN ('agrs', 'agrn') THEN
    IF pd.kind <> 'respond' THEN RETURN gone; END IF;
    UPDATE agenda_pending SET payload = payload || jsonb_build_object('response', CASE WHEN a = 'agrs' THEN 'accepted' ELSE 'declined' END, 'dispatched_at', now()) WHERE id = pd.id RETURNING * INTO pd;
    RETURN jsonb_build_object('text', 'Respondendo ao convite...', 'kb', 'none', 'cal', f_ag_cal(pd, ''));
  END IF;

  IF a = 'agfo' THEN
    IF pd.kind <> 'create' THEN RETURN gone; END IF;
    UPDATE agenda_pending SET state = 'cancelled' WHERE id = pd.id;
    orig := 'Marcar "' || coalesce(pd.payload->>'summary', pd.title) || '" em outro horário (o pedido antes era ' || f_ag_fmt(coalesce(f_ag_ts(pd.payload->>'start'), pd.new_start), tz)
         || ', duração ' || round(extract(epoch FROM (coalesce(f_ag_ts(pd.payload->>'end'), pd.new_end) - coalesce(f_ag_ts(pd.payload->>'start'), pd.new_start))) / 60)::int || ' min'
         || CASE WHEN coalesce(pd.payload->>'location', '') <> '' THEN ', local ' || (pd.payload->>'location') ELSE '' END
         || CASE WHEN coalesce(pd.payload->>'repeat_freq', '') <> '' THEN ', repete ' || (pd.payload->>'repeat_freq') ELSE '' END || ')';
    RETURN jsonb_build_object('text', 'Ok. Qual outro horário para "' || coalesce(pd.payload->>'summary', pd.title) || '"? Me diga o dia e a hora.', 'kb', 'none',
                              'state', jsonb_build_object('kind', 'clarify', 'original', orig)::text);
  END IF;

  -- agok, agsc, agfy: executam algo no Google (protecao contra toque duplo: 60 s)
  IF coalesce(f_ag_ts(pd.payload->>'dispatched_at'), '-infinity') > now() - interval '60 seconds' THEN
    RETURN jsonb_build_object('text', 'Já estou cuidando disso, só um instante.', 'kb', 'none');
  END IF;
  IF a = 'agsc' THEN
    IF pd.kind <> 'cancel' OR v3 NOT IN ('1', 'a') THEN RETURN gone; END IF;
    UPDATE agenda_pending SET payload = payload || jsonb_build_object('scope', v3, 'dispatched_at', now()) WHERE id = pd.id RETURNING * INTO pd;
    RETURN jsonb_build_object('text', 'Cancelando...', 'kb', 'none', 'cal', f_ag_cal(pd, v3));
  ELSIF a = 'agfy' THEN
    IF pd.kind <> 'create' THEN RETURN gone; END IF;
    UPDATE agenda_pending SET payload = payload || jsonb_build_object('force', true, 'dispatched_at', now()) WHERE id = pd.id RETURNING * INTO pd;
    RETURN jsonb_build_object('text', 'Marcando mesmo assim...', 'kb', 'none', 'cal', f_ag_cal(pd, ''));
  ELSE -- agok
    IF pd.kind = 'respond' THEN RETURN gone; END IF;
    IF pd.kind = 'cancel' AND coalesce(pd.payload->>'recurring_id', '') <> '' AND coalesce(pd.payload->>'scope', '') = '' THEN
      RETURN f_ag_confirm(pd.id);   -- recorrente: precisa do escopo antes
    END IF;
    UPDATE agenda_pending SET payload = payload || jsonb_build_object('dispatched_at', now()) WHERE id = pd.id RETURNING * INTO pd;
    RETURN jsonb_build_object('text', 'Certo, fazendo...', 'kb', 'none', 'cal', f_ag_cal(pd, coalesce(pd.payload->>'scope', '')));
  END IF;
EXCEPTION WHEN others THEN
  RETURN jsonb_build_object('text', 'Não consegui processar esse botão agora. Tente de novo.', 'kb', 'none', 'err', SQLERRM);
END $$;
