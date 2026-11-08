-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_base(p_user bigint, p jsonb)
-- Origem da definicao atual: 013_extras.sql (linha 616)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:632, 011_planejamento.sql:215, 013_extras.sql:616
-- Renomeada de f_fin para f_fin_base em 024_ciclo_correcoes.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_fin_base).
CREATE OR REPLACE FUNCTION f_fin(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE act text := coalesce(p->>'action', ''); res jsonb; intro boolean; d integer;
BEGIN
  PERFORM f_fin_seed(p_user);
  IF act = 'add' THEN res := f_card_link(p_user, p, f_fin_add(p_user, p));
  ELSIF act = 'pay' THEN res := f_fin_pay(p_user, p);
  ELSIF act = 'correct' THEN res := f_fin_correct(p_user, p);
  ELSIF act = 'remove' THEN res := f_fin_remove(p_user, p);
  ELSIF act IN ('summary', 'compare', 'top', 'by_day') THEN res := f_fin_report(p_user, p);
  ELSIF act IN ('budget_set', 'budget_status') THEN res := f_fin_budget(p_user, p);
  ELSIF act IN ('category_create', 'category_list') THEN res := f_fin_category(p_user, p);
  ELSIF act = 'closing_set' THEN res := f_fin_closing(p_user, p);
  ELSIF act = 'owed' THEN res := f_fin_owed(p_user, p);
  ELSIF act IN ('limit_set', 'limit_status', 'limit_clear', 'income_set', 'plan_status', 'goal_create', 'goal_deposit', 'goal_withdraw', 'goal_status', 'goal_edit', 'goal_remove') THEN res := f_fin_plan(p_user, p);
  ELSIF act IN ('card_create', 'card_edit', 'card_remove', 'card_list', 'card_status') THEN res := f_card_action(p_user, p);
  ELSIF act IN ('category_total', 'method_total', 'left_to_close', 'committed') THEN res := f_fin_query(p_user, p);
  ELSE res := jsonb_build_object('text', coalesce(nullif(p->>'reply', ''), 'Não entendi o que fazer com o dinheiro. Exemplos: "gastei 42 no mercado", "quanto gastei esse mês?", "orçamento de lazer 300".'), 'kb', 'none');
  END IF;
  SELECT fin_intro_done, fin_closing_day INTO intro, d FROM users WHERE id = p_user;
  IF NOT intro AND act IN ('add', 'summary', 'budget_set', 'budget_status') THEN
    UPDATE users SET fin_intro_done = true WHERE id = p_user;
    res := jsonb_set(res, '{text}', to_jsonb((res->>'text') || E'\n\nDica: seu mês financeiro fecha no dia ' || d || ' (diga "fecha dia 10" para mudar). Quer um orçamento? Ex.: "orçamento de mercado 800".'));
  END IF;
  RETURN res;
END $$;
