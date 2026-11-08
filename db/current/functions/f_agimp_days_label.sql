-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agimp_days_label(p_days date [ ])
-- Origem da definicao atual: 032_resumo_enxuto.sql (linha 39)
-- Definicoes (migracao:linha), da mais antiga a atual: 032_resumo_enxuto.sql:39
CREATE OR REPLACE FUNCTION f_agimp_days_label(p_days date[]) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path TO 'agente','public' AS $$
DECLARE ab text[] := ARRAY['dom','seg','ter','qua','qui','sex','sáb']; ds int[]; i int; r text := ''; run_start int; prev int; contiguous boolean := true;
BEGIN
  SELECT array_agg(DISTINCT extract(dow FROM d)::int ORDER BY extract(dow FROM d)::int) INTO ds FROM unnest(p_days) d;
  FOR i IN 2..coalesce(array_length(ds, 1), 0) LOOP
    IF ds[i] <> ds[i-1] + 1 THEN contiguous := false; END IF;
  END LOOP;
  IF array_length(ds, 1) >= 3 AND contiguous THEN
    RETURN ab[ds[1] + 1] || ' a ' || ab[ds[array_length(ds, 1)] + 1];
  END IF;
  SELECT string_agg(ab[x + 1], ', ' ORDER BY x) INTO r FROM unnest(ds) x;
  RETURN coalesce(r, '');
END $$;
