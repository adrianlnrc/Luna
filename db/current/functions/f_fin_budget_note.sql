-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_budget_note(p_user bigint, p_cat bigint, p_added numeric, p_on date)
-- Origem da definicao atual: 011_planejamento.sql (linha 104)
-- Definicoes (migracao:linha), da mais antiga a atual: 011_planejamento.sql:104
CREATE OR REPLACE FUNCTION f_fin_budget_note(p_user bigint, p_cat bigint, p_added numeric, p_on date) RETURNS text
LANGUAGE sql STABLE SET search_path = agente, public AS $$
  SELECT f_fin_cat_note(p_user, p_cat, p_added, p_on) || f_fin_limit_note(p_user, p_added, p_on)
$$;
