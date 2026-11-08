-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_card_inv_avg(p_card bigint, p_before date)
-- Origem da definicao atual: 026_recibo_alertas.sql (linha 25)
-- Definicoes (migracao:linha), da mais antiga a atual: 026_recibo_alertas.sql:25
CREATE OR REPLACE FUNCTION agente.f_card_inv_avg(p_card bigint, p_before date)
 RETURNS numeric[]
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE c fin_cards%ROWTYPE; pe date := p_before; ps date; x numeric; tot numeric := 0; n integer := 0; k integer;
BEGIN
  SELECT * INTO c FROM fin_cards WHERE id = p_card;
  IF NOT FOUND THEN RETURN ARRAY[0, 0]::numeric[]; END IF;
  FOR k IN 1..3 LOOP
    ps := f_card_close_le(c.closing_day, pe - 1);
    x := f_card_sum(c.id, ps, pe);
    IF x > 0 THEN tot := tot + x; n := n + 1; END IF;
    pe := ps;
  END LOOP;
  IF n = 0 THEN RETURN ARRAY[0, 0]::numeric[]; END IF;
  RETURN ARRAY[round(tot / n, 2), n]::numeric[];
END $function$;
