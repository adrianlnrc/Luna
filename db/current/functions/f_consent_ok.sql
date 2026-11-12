-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_consent_ok(p_user bigint, p_tipo text)
-- Origem da definicao atual: 037_assessor_base.sql (linha 55)
-- Definicoes (migracao:linha), da mais antiga a atual: 037_assessor_base.sql:55
CREATE OR REPLACE FUNCTION f_consent_ok(p_user bigint, p_tipo text) RETURNS boolean
LANGUAGE sql STABLE SET search_path = agente, public AS $$
  SELECT EXISTS (SELECT 1 FROM user_consents WHERE user_id = p_user AND tipo = p_tipo AND revogado_em IS NULL)
$$;
