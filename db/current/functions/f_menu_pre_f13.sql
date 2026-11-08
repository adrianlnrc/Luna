-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_menu_pre_f13(p_user bigint, p_key text)
-- Origem da definicao atual: 029_pesquisa.sql (linha 113)
-- Definicoes (migracao:linha), da mais antiga a atual: 029_pesquisa.sql:113
-- Renomeada de f_menu para f_menu_pre_f13 em 036_menu_secretaria.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_menu_pre_f13).
CREATE OR REPLACE FUNCTION agente.f_menu(p_user bigint, p_key text) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE k text := lower(coalesce(btrim(p_key), 'inicio'));
BEGIN
  IF k = 'pesquisa' THEN
    RETURN jsonb_build_object('rid', 0, 'kb', 'menu', 'text',
      E'Pesquisa na web\nPergunto na internet e respondo curto, com as fontes (título e link). Se não achar fonte confiável, eu digo.\n\nTente dizer:\n- "câmbio do dólar hoje"\n- "preço médio de um notebook para arquitetura"\n- "qual a regra do IPVA em SP?"\n- "norma de acessibilidade para rampa"\n\nCusto: cada pesquisa gasta um pouco da minha conta de IA, e eu mostro no fim da resposta uma estimativa em reais, mais o total do dia e do mês. É só um aviso: a pesquisa sempre é feita. Se o gasto do dia passar do limite (padrão R$ 1,00), o aviso fica em destaque.\n\nLimite: 3 pesquisas por minuto. Eu envio à OpenAI só a sua pergunta (nada da sua agenda, finanças ou contatos), e o texto da web é tratado como informação, nunca como ordem.\n\nPedidos pessoais (agenda, gastos, lembretes) não vão para a pesquisa.');
  END IF;
  RETURN f_menu_pre_m5(p_user, p_key);
END $$;
