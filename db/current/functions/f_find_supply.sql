-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_find_supply(p_user bigint, p_item text)
-- Origem da definicao atual: 006_cadastro_simples.sql (linha 29)
-- Definicoes (migracao:linha), da mais antiga a atual: 006_cadastro_simples.sql:29
CREATE OR REPLACE FUNCTION f_find_supply(p_user bigint, p_item text) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_id bigint;
BEGIN
  IF COALESCE(trim(p_item), '') <> '' THEN
    SELECT id INTO v_id FROM supplies
    WHERE user_id = p_user AND status = 'active'
      AND (item ILIKE '%' || p_item || '%' OR p_item ILIKE '%' || item || '%')
    ORDER BY created_at DESC LIMIT 1;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  END IF;
  IF (SELECT count(*) FROM supplies WHERE user_id = p_user AND status = 'active') = 1 THEN
    SELECT id INTO v_id FROM supplies WHERE user_id = p_user AND status = 'active';
    RETURN v_id;
  END IF;
  RETURN NULL;
END $$;
