-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_closing(p_user bigint, p jsonb)
-- Origem da definicao atual: 008_financas.sql (linha 620)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:620
CREATE OR REPLACE FUNCTION f_fin_closing(p_user bigint, p jsonb) RETURNS jsonb LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE d integer := nullif(p->>'closing_day', '')::int; ps date; pe date;
BEGIN
  IF d IS NULL OR d NOT BETWEEN 1 AND 28 THEN
    RETURN jsonb_build_object('text', 'Em que dia (1 a 28) fecha o seu mês financeiro? Ex.: "fecha dia 5".', 'kb', 'none');
  END IF;
  UPDATE users SET fin_closing_day = d, fin_intro_done = true WHERE id = p_user;
  SELECT p_start, p_end INTO ps, pe FROM f_fin_period(p_user, 0);
  RETURN jsonb_build_object('text', 'Pronto: seu mês financeiro agora fecha no dia ' || d || '. O período atual vai de ' || to_char(ps, 'DD/MM') || ' a ' || to_char(pe, 'DD/MM') || '.', 'kb', 'none');
END $$;
