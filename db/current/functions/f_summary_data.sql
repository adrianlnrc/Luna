-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_summary_data(p_user bigint)
-- Origem da definicao atual: 026_recibo_alertas.sql (linha 286) [dentro de bloco DO/EXECUTE, criacao condicional]
-- Definicoes (migracao:linha), da mais antiga a atual: 026_recibo_alertas.sql:286
CREATE FUNCTION agente.f_summary_data(p_user bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE v jsonb := f_summary_data_pre_m2(p_user); al text := ''; ex text;
BEGIN
  BEGIN al := f_card_alerts_user(p_user); EXCEPTION WHEN others THEN al := ''; END;
  IF al <> '' THEN
    ex := coalesce(v->>'extras_text', '');
    v := v || jsonb_build_object('extras_text', al || CASE WHEN ex <> '' THEN chr(10) || chr(10) || ex ELSE '' END);
  END IF;
  RETURN v;
END $function$;
