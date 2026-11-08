-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_pre_report(p_user bigint, p jsonb)
-- Origem da definicao atual: 026_recibo_alertas.sql (linha 175) [dentro de bloco DO/EXECUTE, criacao condicional]
-- Definicoes (migracao:linha), da mais antiga a atual: 026_recibo_alertas.sql:175
-- Renomeada de f_fin para f_fin_pre_report em 027_relatorios.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_fin_pre_report).
CREATE FUNCTION agente.f_fin(p_user bigint, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE res jsonb := f_fin_pre_m2(p_user, p); rid bigint; al text := '';
BEGIN
  IF coalesce(p->>'action', '') = 'add' AND res->>'kb' = 'fin_undo' THEN
    rid := nullif(res->>'rid', '')::bigint;
    IF rid IS NOT NULL THEN
      BEGIN al := f_fin_alerts(p_user, rid); EXCEPTION WHEN others THEN al := ''; END;
    END IF;
    res := jsonb_set(res, '{text}', to_jsonb((res->>'text') || al));
    res := jsonb_set(res, '{kb}', '"fin_recibo"'::jsonb);
  END IF;
  RETURN res;
END $function$;
