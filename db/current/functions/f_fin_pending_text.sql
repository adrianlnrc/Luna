-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_pending_text(p_user bigint)
-- Origem da definicao atual: 008_financas.sql (linha 444)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:444
CREATE OR REPLACE FUNCTION f_fin_pending_text(p_user bigint) RETURNS text LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE today date := f_fin_today(p_user); t text := ''; r record; n integer := 0; tot numeric := 0; late integer := 0;
BEGIN
  FOR r IN SELECT description, amount, due_on, person, kind FROM fin_entries WHERE user_id = p_user AND status = 'pending' AND kind = 'expense' ORDER BY due_on LIMIT 8 LOOP
    n := n + 1; tot := tot + r.amount;
    IF r.due_on < today THEN late := late + 1; END IF;
    t := t || E'\n- ' || r.description || ' ' || f_brl(r.amount) || ', ' || CASE WHEN r.due_on < today THEN 'ATRASADA desde ' ELSE 'vence ' END || to_char(r.due_on, 'DD/MM');
  END LOOP;
  IF n = 0 THEN RETURN ''; END IF;
  RETURN E'\n\nA pagar (' || n || '), ' || f_brl(tot) || CASE WHEN late > 0 THEN ', ' || late || ' atrasada(s). Diga "já paguei" quando quitar' ELSE '' END || ':' || t;
END $$;
