-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_safe_date(p text)
-- Origem da definicao atual: 008_financas.sql (linha 77)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:77
CREATE OR REPLACE FUNCTION f_safe_date(p text) RETURNS date LANGUAGE plpgsql IMMUTABLE SET search_path = agente, public AS $$
BEGIN
  IF p IS NULL OR p = '' THEN RETURN NULL; END IF;
  RETURN p::date;
EXCEPTION WHEN others THEN RETURN NULL;
END $$;
