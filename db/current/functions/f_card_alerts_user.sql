-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_card_alerts_user(p_user bigint)
-- Origem da definicao atual: 026_recibo_alertas.sql (linha 80)
-- Definicoes (migracao:linha), da mais antiga a atual: 026_recibo_alertas.sql:80
CREATE OR REPLACE FUNCTION agente.f_card_alerts_user(p_user bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE c record; t text := ''; x text; NL text := chr(10);
BEGIN
  FOR c IN SELECT id FROM fin_cards WHERE user_id = p_user AND active ORDER BY id LOOP
    x := f_card_invoice_alert(c.id);
    IF x <> '' THEN t := t || CASE WHEN t <> '' THEN NL ELSE '' END || x; END IF;
  END LOOP;
  RETURN t;
END $function$;
