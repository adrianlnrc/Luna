-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_goal_line(p_goal bigint)
-- Origem da definicao atual: 011_planejamento.sql (linha 65)
-- Definicoes (migracao:linha), da mais antiga a atual: 011_planejamento.sql:65
CREATE OR REPLACE FUNCTION f_fin_goal_line(p_goal bigint) RETURNS text
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE g fin_goals%ROWTYPE; sv numeric; today date; m integer; falta numeric; t text;
BEGIN
  SELECT * INTO g FROM fin_goals WHERE id = p_goal;
  sv := f_fin_goal_saved(p_goal); falta := greatest(g.target - sv, 0);
  today := f_fin_today(g.user_id);
  t := g.name || ': ' || f_brl(sv) || ' de ' || f_brl(g.target) || ' (' || round(sv / g.target * 100) || '%)';
  IF falta = 0 THEN RETURN t || ', meta batida!'; END IF;
  t := t || ', faltam ' || f_brl(falta);
  IF g.deadline IS NOT NULL THEN
    IF g.deadline < today THEN RETURN t || ', o prazo (' || to_char(g.deadline, 'DD/MM/YYYY') || ') já passou'; END IF;
    m := greatest(1, (extract(year FROM g.deadline)::int - extract(year FROM today)::int) * 12 + extract(month FROM g.deadline)::int - extract(month FROM today)::int);
    t := t || ' até ' || to_char(g.deadline, 'DD/MM/YYYY') || ', cerca de ' || f_brl(ceil(falta / m)) || ' por mês';
  END IF;
  RETURN t || CASE WHEN g.auto THEN '' ELSE ' (só manual)' END;
END $$;
