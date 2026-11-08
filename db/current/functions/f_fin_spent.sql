-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_spent(p_user bigint, p_cat bigint, p_start date, p_end date)
-- Origem da definicao atual: 008_financas.sql (linha 175)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:175
CREATE OR REPLACE FUNCTION f_fin_spent(p_user bigint, p_cat bigint, p_start date, p_end date) RETURNS numeric
LANGUAGE sql STABLE SET search_path = agente, public AS $$
  SELECT coalesce(sum(amount), 0) FROM fin_entries
  WHERE user_id = p_user AND category_id = p_cat AND kind = 'expense' AND status = 'paid' AND occurred_on BETWEEN p_start AND p_end
$$;
