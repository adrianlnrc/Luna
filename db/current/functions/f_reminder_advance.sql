-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_reminder_advance(p_rid bigint)
-- Origem da definicao atual: 028_custo_ia_anuais.sql (linha 236) [dentro de bloco DO/EXECUTE, criacao condicional]
-- Definicoes (migracao:linha), da mais antiga a atual: 028_custo_ia_anuais.sql:236
CREATE FUNCTION agente.f_reminder_advance(p_rid bigint) RETURNS bigint
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $b$
BEGIN
  IF EXISTS (SELECT 1 FROM agente.reminders WHERE id = p_rid AND repeat_rule = 'yearly') THEN
    RETURN agente.f_reminder_advance_yearly(p_rid);
  END IF;
  RETURN agente.f_reminder_advance_base(p_rid);
END $b$;
