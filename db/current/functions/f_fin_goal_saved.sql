-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_goal_saved(p_goal bigint)
-- Origem da definicao atual: 011_planejamento.sql (linha 36)
-- Definicoes (migracao:linha), da mais antiga a atual: 011_planejamento.sql:36
CREATE OR REPLACE FUNCTION f_fin_goal_saved(p_goal bigint) RETURNS numeric
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE g fin_goals%ROWTYPE; manual numeric; net numeric := 0; n integer;
BEGIN
  SELECT * INTO g FROM fin_goals WHERE id = p_goal;
  IF NOT FOUND THEN RETURN 0; END IF;
  SELECT coalesce(sum(amount), 0) INTO manual FROM fin_goal_deposits WHERE goal_id = p_goal;
  IF g.auto THEN
    SELECT count(*) INTO n FROM fin_goals WHERE user_id = g.user_id AND auto;
    SELECT greatest(0, coalesce(sum(CASE WHEN kind = 'income' THEN amount ELSE -amount END), 0)) INTO net
    FROM fin_entries WHERE user_id = g.user_id AND status = 'paid' AND occurred_on >= g.created_at::date AND occurred_on <= f_fin_today(g.user_id);
    manual := manual + round(net / greatest(n, 1), 2);
  END IF;
  RETURN greatest(manual, 0);
END $$;
