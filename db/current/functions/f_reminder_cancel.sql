-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_reminder_cancel(p_user bigint, p_title text)
-- Origem da definicao atual: 013_extras.sql (linha 294)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:294
CREATE OR REPLACE FUNCTION f_reminder_cancel(p_user bigint, p_title text) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE q text := f_norm(p_title); toks text[]; n integer := 0; v_chain bigint; v_ttl text; v_rec boolean; r record; t text := ''; tz text;
BEGIN
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  IF q = '' THEN
    RETURN jsonb_build_object('text', 'Qual lembrete eu cancelo? Diga o nome, por exemplo: "cancela o lembrete da conta de luz".', 'kb', 'none');
  END IF;
  SELECT array_agg(x) INTO toks FROM unnest(string_to_array(q, ' ')) x
   WHERE length(x) >= 3 AND x NOT IN ('que','com','pra','para','dos','das','meu','minha','lembrete','lembrar','lembra','cancela','cancelar','apaga','apagar','toda','todo','todos');
  IF toks IS NULL THEN toks := ARRAY[q]; END IF;
  FOR r IN
    SELECT DISTINCT ON (coalesce(rm.repeat_of, rm.id)) coalesce(rm.repeat_of, rm.id) AS chain, rm.title, rm.due_at, rm.repeat_rule IS NOT NULL AS rec
    FROM reminders rm
    WHERE rm.user_id = p_user AND rm.status IN ('pending','awaiting_time') AND rm.kind = 'reminder' AND rm.card_id IS NULL
      AND (SELECT bool_and(f_norm(rm.title) LIKE '%' || x || '%') FROM unnest(toks) x)
    ORDER BY coalesce(rm.repeat_of, rm.id), rm.due_at
  LOOP
    n := n + 1;
    IF n = 1 THEN v_chain := r.chain; v_ttl := r.title; v_rec := r.rec; END IF;
    IF n <= 6 THEN
      t := t || E'\n- ' || r.title || ' (' || to_char(r.due_at AT TIME ZONE tz, 'DD/MM HH24:MI') || CASE WHEN r.rec THEN ', se repete' ELSE '' END || ')';
    END IF;
  END LOOP;
  IF n = 0 THEN
    RETURN jsonb_build_object('text', 'Não achei nenhum lembrete pendente parecido com "' || btrim(p_title) || '".', 'kb', 'none');
  END IF;
  IF n > 1 THEN
    RETURN jsonb_build_object('text', 'Achei ' || n || ' lembretes parecidos:' || t || E'\nMe diga o nome com mais detalhe para eu saber qual cancelar.', 'kb', 'none');
  END IF;
  UPDATE notifications SET state = 'cancelled'
   WHERE state = 'pending' AND reminder_id IN (SELECT id FROM reminders WHERE user_id = p_user AND coalesce(repeat_of, id) = v_chain AND status IN ('pending','awaiting_time'));
  UPDATE reminders SET status = 'cancelled' WHERE user_id = p_user AND coalesce(repeat_of, id) = v_chain AND status IN ('pending','awaiting_time');
  UPDATE reminders SET repeat_rule = NULL WHERE user_id = p_user AND coalesce(repeat_of, id) = v_chain AND repeat_rule IS NOT NULL;
  RETURN jsonb_build_object('text', 'Cancelei o lembrete "' || v_ttl || '"' || CASE WHEN v_rec THEN ' e a repetição dele' ELSE '' END || '.', 'kb', 'none');
EXCEPTION WHEN others THEN
  RAISE WARNING 'f_reminder_cancel: %', SQLERRM;
  RETURN jsonb_build_object('text', 'Não consegui cancelar agora. Tente de novo.', 'kb', 'none');
END $$;
