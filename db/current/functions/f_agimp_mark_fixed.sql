-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agimp_mark_fixed(p_items jsonb)
-- Origem da definicao atual: 032_resumo_enxuto.sql (linha 24)
-- Definicoes (migracao:linha), da mais antiga a atual: 032_resumo_enxuto.sql:24
CREATE OR REPLACE FUNCTION f_agimp_mark_fixed(p_items jsonb) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  WITH it AS (
    SELECT x.e, x.ord, lower(trim(x.e->>'title')) AS t, x.e->>'start' AS s, x.e->>'end' AS en
      FROM jsonb_array_elements(p_items) WITH ORDINALITY AS x(e, ord)
  ), g AS (
    SELECT t, s, en FROM it WHERE it.e->>'kind' = 'event'
     GROUP BY t, s, en HAVING count(DISTINCT it.e->>'day') >= 2
  )
  SELECT coalesce(jsonb_agg(CASE WHEN it.e->>'kind' = 'event' AND EXISTS (SELECT 1 FROM g WHERE g.t = it.t AND g.s = it.s AND g.en = it.en)
                                 THEN jsonb_set(it.e, '{fixed}', 'true'::jsonb) ELSE jsonb_set(it.e, '{fixed}', 'false'::jsonb) END ORDER BY it.ord), '[]'::jsonb)
    FROM it
$$;
