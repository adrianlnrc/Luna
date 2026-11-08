-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_plan(p_user bigint, p jsonb)
-- Origem da definicao atual: 011_planejamento.sql (linha 150)
-- Definicoes (migracao:linha), da mais antiga a atual: 011_planejamento.sql:150
CREATE OR REPLACE FUNCTION f_fin_plan(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE
  act text := p->>'action'; v_amt numeric := round(nullif(p->>'budget_amount', '')::numeric, 2);
  v_name text := btrim(coalesce(p->>'title', '')); v_new text := btrim(coalesce(p->>'category', ''));
  v_dl date := f_safe_date(p->>'date'); v_mode text := lower(coalesce(p->>'keywords', ''));
  g fin_goals%ROWTYPE; v_id bigint; t text; r record; n integer := 0; na integer;
BEGIN
  IF act = 'limit_set' THEN
    IF v_amt IS NULL OR v_amt <= 0 THEN RETURN jsonb_build_object('text', 'Qual o valor do limite? Ex.: "quero gastar no máximo 3000 por mês".', 'kb', 'none'); END IF;
    UPDATE users SET fin_total_limit = v_amt WHERE id = p_user;
    RETURN jsonb_build_object('text', 'Limite geral do mês: ' || f_brl(v_amt) || '. Aviso quando chegar a 80% e a 100%. ' || f_fin_limit_text(p_user), 'kb', 'none');
  ELSIF act = 'limit_clear' THEN
    UPDATE users SET fin_total_limit = NULL WHERE id = p_user;
    RETURN jsonb_build_object('text', 'Tirei o limite geral. Os orçamentos por categoria continuam.', 'kb', 'none');
  ELSIF act = 'limit_status' THEN
    RETURN jsonb_build_object('text', f_fin_limit_text(p_user), 'kb', 'none');
  ELSIF act = 'income_set' THEN
    IF v_amt IS NULL OR v_amt <= 0 THEN RETURN jsonb_build_object('text', 'Qual a sua renda mensal? Ex.: "minha renda é 5000".', 'kb', 'none'); END IF;
    UPDATE users SET fin_income = v_amt WHERE id = p_user;
    RETURN jsonb_build_object('text', 'Anotei: renda prevista de ' || f_brl(v_amt) || ' por mês. Diga "meu planejamento" para ver a visão do mês.', 'kb', 'none');
  ELSIF act = 'plan_status' THEN
    RETURN jsonb_build_object('text', f_fin_plan_text(p_user), 'kb', 'none');
  ELSIF act = 'goal_create' THEN
    IF v_name = '' THEN RETURN jsonb_build_object('text', 'Qual o nome da meta? Ex.: "juntar 800 até dezembro pro presente de Natal".', 'kb', 'none'); END IF;
    IF v_amt IS NULL OR v_amt <= 0 THEN RETURN jsonb_build_object('text', 'Qual o valor da meta "' || v_name || '"?', 'kb', 'none'); END IF;
    IF v_dl IS NOT NULL AND v_dl < f_fin_today(p_user) THEN RETURN jsonb_build_object('text', 'Esse prazo já passou. Qual a data limite da meta?', 'kb', 'none'); END IF;
    INSERT INTO fin_goals (user_id, name, norm_name, target, deadline, auto) VALUES (p_user, initcap(left(v_name, 60)), f_norm(v_name), v_amt, v_dl, v_mode <> 'manual') RETURNING id INTO v_id;
    SELECT count(*) INTO na FROM fin_goals WHERE user_id = p_user AND auto;
    RETURN jsonb_build_object('text', 'Meta criada. ' || f_fin_goal_line(v_id) || '.' ||
      CASE WHEN v_mode = 'manual' THEN ' O progresso é só manual: diga "guardei 100 pra ' || lower(v_name) || '".'
           WHEN na > 1 THEN ' O que sobrar do mês (receitas menos gastos) é dividido igualmente entre as ' || na || ' metas automáticas; diga "essa meta é só manual" para tirar uma da divisão.'
           ELSE ' O progresso é automático (receitas menos gastos desde agora); você também pode dizer "guardei 100".' END, 'kb', 'none');
  ELSIF act IN ('goal_deposit', 'goal_withdraw') THEN
    IF v_amt IS NULL OR v_amt <= 0 THEN RETURN jsonb_build_object('text', 'Quanto? Ex.: "guardei 100 pro presente".', 'kb', 'none'); END IF;
    v_id := f_fin_goal_find(p_user, v_name);
    IF v_id IS NULL THEN RETURN jsonb_build_object('text', CASE WHEN v_name = '' THEN 'Para qual meta? Diga "minhas metas" para ver a lista.' ELSE 'Não achei a meta "' || v_name || '". Diga "minhas metas" para ver a lista.' END, 'kb', 'none'); END IF;
    INSERT INTO fin_goal_deposits (goal_id, amount) VALUES (v_id, CASE WHEN act = 'goal_deposit' THEN v_amt ELSE -v_amt END);
    RETURN jsonb_build_object('text', CASE WHEN act = 'goal_deposit' THEN 'Guardei ' ELSE 'Tirei ' END || f_brl(v_amt) || '. ' || f_fin_goal_line(v_id) || '.', 'kb', 'none');
  ELSIF act = 'goal_status' THEN
    IF v_name <> '' THEN
      v_id := f_fin_goal_find(p_user, v_name);
      IF v_id IS NULL THEN RETURN jsonb_build_object('text', 'Não achei a meta "' || v_name || '".', 'kb', 'none'); END IF;
      RETURN jsonb_build_object('text', f_fin_goal_line(v_id) || '.', 'kb', 'none');
    END IF;
    FOR r IN SELECT id FROM fin_goals WHERE user_id = p_user ORDER BY id LOOP n := n + 1; t := coalesce(t, '') || E'\n- ' || f_fin_goal_line(r.id); END LOOP;
    IF n = 0 THEN RETURN jsonb_build_object('text', 'Você ainda não tem metas. Ex.: "quero juntar 800 até dezembro pro presente de Natal".', 'kb', 'none'); END IF;
    RETURN jsonb_build_object('text', 'Suas metas:' || t, 'kb', 'none');
  ELSIF act = 'goal_edit' THEN
    v_id := f_fin_goal_find(p_user, v_name);
    IF v_id IS NULL THEN RETURN jsonb_build_object('text', 'Qual meta você quer mudar? Diga "minhas metas" para ver a lista.', 'kb', 'none'); END IF;
    UPDATE fin_goals SET target = coalesce(v_amt, target), deadline = coalesce(v_dl, deadline),
      name = CASE WHEN v_new <> '' THEN initcap(left(v_new, 60)) ELSE name END, norm_name = CASE WHEN v_new <> '' THEN f_norm(v_new) ELSE norm_name END,
      auto = CASE WHEN v_mode = 'manual' THEN false WHEN v_mode = 'auto' THEN true ELSE auto END WHERE id = v_id;
    RETURN jsonb_build_object('text', 'Atualizei. ' || f_fin_goal_line(v_id) || '.', 'kb', 'none');
  ELSIF act = 'goal_remove' THEN
    v_id := f_fin_goal_find(p_user, v_name);
    IF v_id IS NULL THEN RETURN jsonb_build_object('text', 'Qual meta apagar? Diga "minhas metas" para ver a lista.', 'kb', 'none'); END IF;
    SELECT * INTO g FROM fin_goals WHERE id = v_id;
    RETURN jsonb_build_object('text', 'Apagar a meta ' || g.name || ' (' || f_brl(g.target) || ')?', 'kb', 'fin_delete', 'rid', -v_id);
  END IF;
  RETURN jsonb_build_object('text', 'Não entendi o que fazer com o planejamento.', 'kb', 'none');
END $$;
