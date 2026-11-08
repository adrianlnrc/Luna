-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_card_status_text(p_card bigint)
-- Origem da definicao atual: 026_recibo_alertas.sql (linha 267) [dentro de bloco DO/EXECUTE, criacao condicional]
-- Definicoes (migracao:linha), da mais antiga a atual: 026_recibo_alertas.sql:267
CREATE FUNCTION agente.f_card_status_text(p_card bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE t text := f_card_status_text_pre_m2(p_card); al text := '';
BEGIN
  BEGIN al := f_card_invoice_alert(p_card); EXCEPTION WHEN others THEN al := ''; END;
  IF al <> '' THEN t := t || chr(10) || al; END IF;
  RETURN t;
END $function$;
