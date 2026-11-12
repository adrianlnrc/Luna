-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_insights_expire(p_user bigint)
-- Origem da definicao atual: 039_insights.sql (linha 242)
-- Definicoes (migracao:linha), da mais antiga a atual: 039_insights.sql:242
CREATE OR REPLACE FUNCTION f_insights_expire(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE n int; r record; desl text[] := '{}';
BEGIN
  WITH upd AS (
    UPDATE insights_log SET resposta = 'ignorado', respondido_em = now()
     WHERE user_id = p_user AND resposta IS NULL AND via <> 'revisao' AND enviado_em < now() - interval '24 hours' RETURNING 1)
  SELECT count(*) INTO n FROM upd;
  PERFORM f_insight_prefs(p_user);
  IF n > 0 THEN
    UPDATE insight_prefs SET ignorados_seguidos = ignorados_seguidos + n, atualizado_em = now() WHERE user_id = p_user;
  END IF;
  FOR r IN SELECT regra FROM insights_log
            WHERE user_id = p_user AND enviado_em > now() - interval '30 days'
            GROUP BY regra
           HAVING count(*) FILTER (WHERE resposta IN ('agora_nao', 'silenciado')) >= 3 AND count(*) FILTER (WHERE resposta = 'aceito') = 0 LOOP
    desl := desl || r.regra;
  END LOOP;
  IF array_length(desl, 1) > 0 THEN
    UPDATE insight_prefs SET regras_desligadas = (SELECT array_agg(DISTINCT x) FROM unnest(regras_desligadas || desl) x), atualizado_em = now()
     WHERE user_id = p_user;
  END IF;
  RETURN jsonb_build_object('ignorados', n, 'desligadas', to_jsonb(desl));
END $$;
