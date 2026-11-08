-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_expired(p_entry bigint)
-- Origem da definicao atual: 026_recibo_alertas.sql (linha 15)
-- Definicoes (migracao:linha), da mais antiga a atual: 026_recibo_alertas.sql:15
CREATE OR REPLACE FUNCTION agente.f_fin_expired(p_entry bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'agente', 'public'
AS $function$
  SELECT coalesce((SELECT created_at < now() - interval '24 hours' FROM fin_entries WHERE id = p_entry), false)
$function$;
