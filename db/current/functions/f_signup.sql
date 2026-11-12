-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_signup(p_canal text, p_id_externo text, p_nome text, p_codigo text, p_exige_convite boolean)
-- Origem da definicao atual: 041_rls.sql (linha 89)
-- Definicoes (migracao:linha), da mais antiga a atual: 041_rls.sql:89
CREATE OR REPLACE FUNCTION f_signup(p_canal text, p_id_externo text, p_nome text, p_codigo text, p_exige_convite boolean DEFAULT true) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agente, public AS $$
DECLARE v_id bigint; v_cod text := upper(btrim(coalesce(p_codigo, '')));
BEGIN
  IF EXISTS (SELECT 1 FROM user_channels WHERE canal = p_canal AND id_externo = p_id_externo) THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'ja_cadastrado');
  END IF;
  IF p_canal <> 'telegram' OR p_id_externo !~ '^[0-9]+$' THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'canal');
  END IF;
  IF p_exige_convite THEN
    PERFORM 1 FROM invite_codes WHERE codigo = v_cod AND usado_por IS NULL FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'motivo', 'convite'); END IF;
  END IF;
  INSERT INTO users (telegram_id, name, onboarding_step, papel)
  VALUES (p_id_externo::bigint, left(coalesce(nullif(btrim(p_nome), ''), 'Você'), 60), 'aceite', 'cliente') RETURNING id INTO v_id;
  INSERT INTO user_channels (user_id, canal, id_externo) VALUES (v_id, p_canal, p_id_externo);
  IF p_exige_convite THEN
    UPDATE invite_codes SET usado_por = v_id, usado_em = now() WHERE codigo = v_cod;
  END IF;
  RETURN jsonb_build_object('ok', true, 'user_id', v_id);
END $$;
