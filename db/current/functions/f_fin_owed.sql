-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_owed(p_user bigint, p jsonb)
-- Origem da definicao atual: 008_financas.sql (linha 532)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:532
CREATE OR REPLACE FUNCTION f_fin_owed(p_user bigint, p jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE t text := ''; r record; tot numeric := 0; n integer := 0;
BEGIN
  FOR r IN SELECT person, sum(amount) s, min(due_on) since FROM fin_entries WHERE user_id = p_user AND status = 'pending' AND kind = 'income' AND person IS NOT NULL GROUP BY person ORDER BY 2 DESC LOOP
    n := n + 1; tot := tot + r.s; t := t || E'\n- ' || r.person || ': ' || f_brl(r.s) || ' (desde ' || to_char(r.since, 'DD/MM') || ')';
  END LOOP;
  IF n = 0 THEN RETURN jsonb_build_object('text', 'Ninguém te deve nada anotado. Para anotar: "o João me deve 50".', 'kb', 'none'); END IF;
  RETURN jsonb_build_object('text', 'Quem te deve (' || f_brl(tot) || '):' || t || E'\nQuando pagarem, diga por exemplo "o João pagou".', 'kb', 'none');
END $$;
