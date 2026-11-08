-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_multi_events(p_user bigint, p_items jsonb)
-- Origem da definicao atual: 033_acoes_recentes.sql (linha 186)
-- Definicoes (migracao:linha), da mais antiga a atual: 033_acoes_recentes.sql:186
CREATE OR REPLACE FUNCTION agente.f_multi_events(p_user bigint, p_items jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  it jsonb; rq jsonb; rs jsonb; tz text; v_lines jsonb := '[]'::jsonb; v_fails jsonb := '[]'::jsonb; v_title text; v_due timestamptz; conf text; out_r jsonb;
BEGIN
  SELECT coalesce(nullif(timezone, ''), 'America/Sao_Paulo') INTO tz FROM users WHERE id = p_user;
  FOR it IN SELECT * FROM jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) LOOP
    rq := it->'req'; rs := coalesce(it->'result', '{}'::jsonb); v_title := coalesce(rq->>'title', ''); v_due := (rq->>'due_iso')::timestamptz;
    BEGIN
      IF coalesce(rs->>'ok', '') <> 'true' THEN
        v_fails := v_fails || to_jsonb('Não consegui marcar "' || left(v_title, 60) || '" no Google Agenda'
                     || CASE WHEN jsonb_typeof(rs->'error') = 'string' THEN ' (' || left(rs->>'error', 100) || ')' ELSE '' END || '.');
      ELSIF coalesce(rs->>'conflict', '') = 'true' THEN
        SELECT string_agg(c->>'title', ', ') INTO conf FROM jsonb_array_elements(coalesce(rs->'conflicts', '[]'::jsonb)) c;
        v_fails := v_fails || to_jsonb('Não marquei "' || left(v_title, 60) || '" (' || to_char(v_due AT TIME ZONE tz, 'DD/MM "às" HH24:MI')
                     || '): conflita com ' || coalesce(conf, 'outro compromisso') || '. Me peça ele sozinho que eu pergunto se marco mesmo assim.');
      ELSE
        out_r := f_agenda_after_create(p_user, rq, rs);
        v_lines := v_lines || to_jsonb('Compromisso: ' || v_title || ', ' || to_char(v_due AT TIME ZONE tz, 'DD/MM "às" HH24:MI')
                     || CASE WHEN coalesce(rq->>'location', '') <> '' THEN ' em ' || (rq->>'location') ELSE '' END);
        IF out_r ? 'err' THEN
          v_fails := v_fails || to_jsonb('"' || left(v_title, 60) || '" foi para o Google, mas deu problema nos avisos daqui.');
        END IF;
      END IF;
    EXCEPTION WHEN others THEN
      v_fails := v_fails || to_jsonb('Não consegui registrar "' || left(v_title, 60) || '".');
    END;
  END LOOP;
  RETURN jsonb_build_object('lines', v_lines, 'fails', v_fails);
END $$;
