-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_consent_set(p_user bigint, p_tipo text, p_versao text, p_aceita boolean)
-- Origem da definicao atual: 037_assessor_base.sql (linha 60)
-- Definicoes (migracao:linha), da mais antiga a atual: 037_assessor_base.sql:60
CREATE OR REPLACE FUNCTION f_consent_set(p_user bigint, p_tipo text, p_versao text, p_aceita boolean) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
BEGIN
  IF p_tipo NOT IN ('politica', 'saude') THEN RETURN jsonb_build_object('ok', false, 'error', 'tipo_invalido'); END IF;
  IF p_aceita THEN
    IF NOT f_consent_ok(p_user, p_tipo) THEN
      INSERT INTO user_consents (user_id, tipo, versao) VALUES (p_user, p_tipo, coalesce(nullif(p_versao, ''), '1'));
    END IF;
  ELSE
    UPDATE user_consents SET revogado_em = now() WHERE user_id = p_user AND tipo = p_tipo AND revogado_em IS NULL;
  END IF;
  RETURN jsonb_build_object('ok', true, 'tipo', p_tipo, 'aceito', p_aceita);
END $$;
