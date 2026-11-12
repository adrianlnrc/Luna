-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_oauth_state_use(p_state text)
-- Origem da definicao atual: 041_rls.sql (linha 113)
-- Definicoes (migracao:linha), da mais antiga a atual: 041_rls.sql:113
CREATE OR REPLACE FUNCTION f_oauth_state_use(p_state text) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agente, public AS $$
DECLARE v_user bigint;
BEGIN
  UPDATE oauth_states SET usado_em = now()
   WHERE state = p_state AND usado_em IS NULL AND criado_em > now() - interval '15 minutes' RETURNING user_id INTO v_user;
  RETURN v_user;
END $$;
