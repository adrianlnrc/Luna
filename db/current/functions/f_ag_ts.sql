-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ag_ts(p text)
-- Origem da definicao atual: 012_agenda.sql (linha 41)
-- Definicoes (migracao:linha), da mais antiga a atual: 012_agenda.sql:41
CREATE OR REPLACE FUNCTION f_ag_ts(p text) RETURNS timestamptz
LANGUAGE plpgsql IMMUTABLE SET search_path TO 'agente', 'public' AS $$
BEGIN
  IF p IS NULL OR btrim(p) = '' THEN RETURN NULL; END IF;
  RETURN p::timestamptz;
EXCEPTION WHEN others THEN RETURN NULL;
END $$;
