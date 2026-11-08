-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_mem_relevant_txt(p_user bigint, p_msg text, p_max int)
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 197)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:197
CREATE OR REPLACE FUNCTION agente.f_mem_relevant_txt(p_user bigint, p_msg text, p_max int DEFAULT 8) RETURNS text
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE toks text[] := f_mem_tokens(p_msg); res text; ids bigint[]; v_max int := greatest(coalesce(p_max, 8), 1);
BEGIN
  IF NOT f_mem_sw(p_user, 'mem_enabled') THEN RETURN ''; END IF;
  WITH sc AS (
    SELECT m.id, m.texto, m.criado_em, m.ultimo_uso,
           (SELECT count(*) FROM unnest(toks) t WHERE strpos(' ' || m.norm || ' ', ' ' || t) > 0) AS s
      FROM user_memory m WHERE m.user_id = p_user AND m.ativo),
  matched AS (SELECT * FROM sc WHERE s > 0 ORDER BY s DESC, greatest(criado_em, coalesce(ultimo_uso, criado_em)) DESC, id DESC LIMIT v_max),
  recent  AS (SELECT * FROM sc WHERE s = 0 ORDER BY greatest(criado_em, coalesce(ultimo_uso, criado_em)) DESC, id DESC
               LIMIT least(4, greatest(v_max - (SELECT count(*) FROM matched), 0))),
  u AS (SELECT 0 AS grp, row_number() OVER (ORDER BY s DESC, id DESC) AS ord, id, texto FROM matched
        UNION ALL
        SELECT 1, row_number() OVER (ORDER BY id DESC), id, texto FROM recent)
  SELECT string_agg('- ' || texto, E'\n' ORDER BY grp, ord), array_agg(id) FILTER (WHERE grp = 0) INTO res, ids FROM u;
  IF ids IS NOT NULL THEN
    UPDATE user_memory SET ultimo_uso = now(), usos = usos + 1 WHERE id = ANY (ids);
  END IF;
  RETURN coalesce(res, '');
END $$;
