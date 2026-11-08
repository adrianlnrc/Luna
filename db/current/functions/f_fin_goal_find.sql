-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_goal_find(p_user bigint, p_name text)
-- Origem da definicao atual: 011_planejamento.sql (linha 52)
-- Definicoes (migracao:linha), da mais antiga a atual: 011_planejamento.sql:52
CREATE OR REPLACE FUNCTION f_fin_goal_find(p_user bigint, p_name text) RETURNS bigint
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE q text := f_norm(coalesce(p_name, '')); v_id bigint; n integer;
BEGIN
  IF q <> '' THEN
    SELECT id INTO v_id FROM fin_goals WHERE user_id = p_user AND (norm_name LIKE '%' || q || '%' OR q LIKE '%' || norm_name || '%') ORDER BY id DESC LIMIT 1;
    RETURN v_id;
  END IF;
  SELECT count(*) INTO n FROM fin_goals WHERE user_id = p_user;
  IF n = 1 THEN SELECT id INTO v_id FROM fin_goals WHERE user_id = p_user; END IF;
  RETURN v_id;
END $$;
