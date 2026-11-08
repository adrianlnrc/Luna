-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin(p_user bigint, p jsonb)
-- Origem da definicao atual: 027_relatorios.sql (linha 122) [dentro de bloco DO/EXECUTE, criacao condicional]
-- Definicoes (migracao:linha), da mais antiga a atual: 027_relatorios.sql:122
CREATE FUNCTION agente.f_fin(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public'
AS $b$
BEGIN
  IF coalesce(p->>'action', '') = 'report' THEN
    RETURN f_report_action(p_user, p);
  END IF;
  RETURN f_fin_pre_report(p_user, p);
END $b$;
