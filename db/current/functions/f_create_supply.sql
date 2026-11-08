-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_create_supply(p_user bigint, p_item text, p_total integer, p_per_day numeric, p_started date, p_alert_days integer, p_kind text, p_take_time time without time zone, p_left integer)
-- Origem da definicao atual: 024_ciclo_correcoes.sql (linha 85)
-- Definicoes (migracao:linha), da mais antiga a atual: 024_ciclo_correcoes.sql:85
CREATE OR REPLACE FUNCTION agente.f_create_supply(p_user bigint, p_item text, p_total integer DEFAULT NULL::integer, p_per_day numeric DEFAULT 1, p_started date DEFAULT NULL::date, p_alert_days integer DEFAULT NULL::integer, p_kind text DEFAULT NULL::text, p_take_time time without time zone DEFAULT NULL::time without time zone, p_left integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE r jsonb; ask boolean;
BEGIN
  r := f_create_supply_base(p_user, p_item, p_total, p_per_day, p_started, p_alert_days, p_kind, p_take_time, p_left);
  -- pergunta a cartela so se o item e novo, sem quantidade, e a pessoa nunca informou quantidade de nenhum item
  ask := coalesce((r->>'created')::boolean, false) AND coalesce((r->>'needs_total')::boolean, false)
         AND NOT EXISTS (SELECT 1 FROM supplies WHERE user_id = p_user AND id <> (r->>'id')::bigint AND units_total IS NOT NULL);
  RETURN r || jsonb_build_object('ask_total', ask);
END $function$;
