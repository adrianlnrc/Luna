-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_limit_text(p_user bigint)
-- Origem da definicao atual: 011_planejamento.sql (linha 109)
-- Definicoes (migracao:linha), da mais antiga a atual: 011_planejamento.sql:109
CREATE OR REPLACE FUNCTION f_fin_limit_text(p_user bigint) RETURNS text
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE lim numeric; ps date; pe date; sp numeric; days integer;
BEGIN
  SELECT fin_total_limit INTO lim FROM users WHERE id = p_user;
  IF lim IS NULL THEN RETURN 'Você ainda não definiu um limite geral. Ex.: "quero gastar no máximo 3000 por mês".'; END IF;
  SELECT p_start, p_end INTO ps, pe FROM f_fin_period(p_user, 0);
  sp := f_fin_total_spent(p_user, ps, pe);
  days := greatest(pe - f_fin_today(p_user) + 1, 1);
  RETURN 'Limite geral ' || f_brl(lim) || ' (mês financeiro ' || to_char(ps, 'DD/MM') || ' a ' || to_char(pe, 'DD/MM') || '): gasto ' || f_brl(sp) || ' (' || round(sp / lim * 100) || '%). ' ||
    CASE WHEN lim > sp THEN 'Ainda pode gastar ' || f_brl(lim - sp) || ', cerca de ' || f_brl((lim - sp) / days) || ' por dia nos ' || days || ' dia(s) que restam.'
         ELSE 'Passou ' || f_brl(sp - lim) || ' do limite.' END;
END $$;
