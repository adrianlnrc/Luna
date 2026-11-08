-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_menu_pre_m4(p_user bigint, p_key text)
-- Origem da definicao atual: 027_relatorios.sql (linha 139) [dentro de bloco DO/EXECUTE, criacao condicional]
-- Definicoes (migracao:linha), da mais antiga a atual: 027_relatorios.sql:139
-- Renomeada de f_menu para f_menu_pre_m4 em 028_custo_ia_anuais.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_menu_pre_m4).
CREATE FUNCTION agente.f_menu(p_user bigint, p_key text) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public'
AS $b$
DECLARE res jsonb;
BEGIN
  res := f_menu_pre_report(p_user, p_key);
  IF lower(coalesce(btrim(p_key), '')) = 'dinheiro' AND res ? 'text' AND position('relatório' in res->>'text') = 0 THEN
    res := jsonb_set(res, '{text}', to_jsonb((res->>'text') || E'\n\nRelatórios: "me manda o relatório do mês em Excel", "extrato de outubro em CSV", "gastos do ano em Excel" ou "relatório para o imposto de renda" (Saúde e Educação). Não gero PDF.'));
  END IF;
  RETURN res;
END $b$;
