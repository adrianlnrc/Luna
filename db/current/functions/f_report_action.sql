-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_report_action(p_user bigint, p jsonb)
-- Origem da definicao atual: 027_relatorios.sql (linha 99)
-- Definicoes (migracao:linha), da mais antiga a atual: 027_relatorios.sql:99
CREATE OR REPLACE FUNCTION agente.f_report_action(p_user bigint, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE fmt text := lower(coalesce(p->>'report_format', ''));
BEGIN
  PERFORM f_fin_seed(p_user);
  IF fmt = 'pdf' THEN
    RETURN jsonb_build_object('kb', 'none', 'text',
      'PDF eu ainda não gero. Posso mandar em Excel (.xlsx) ou CSV: diga, por exemplo, "relatório do mês em Excel".');
  END IF;
  IF fmt NOT IN ('csv', 'xlsx') THEN fmt := 'xlsx'; END IF;
  RETURN jsonb_build_object('kb', 'none', 'text', 'Preparando seu relatório...',
    'report', jsonb_build_object('period', coalesce(nullif(p->>'period', ''), 'current'),
                                 'month', coalesce(p->>'month', ''), 'format', fmt,
                                 'keywords', coalesce(p->>'keywords', '')));
END $function$;
