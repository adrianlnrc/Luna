-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_card_sum(p_card bigint, p_from date, p_to date)
-- Origem da definicao atual: 013_extras.sql (linha 79)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:79
CREATE OR REPLACE FUNCTION f_card_sum(p_card bigint, p_from date, p_to date) RETURNS numeric
LANGUAGE sql STABLE SET search_path TO 'agente','public' AS $$
  SELECT coalesce(sum(amount), 0) FROM fin_entries
  WHERE card_id = p_card AND kind = 'expense' AND status IN ('paid','pending') AND occurred_on >= p_from AND occurred_on < p_to
$$;
