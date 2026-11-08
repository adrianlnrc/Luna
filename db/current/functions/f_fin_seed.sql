-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_seed(p_user bigint)
-- Origem da definicao atual: 008_financas.sql (linha 113)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:113
CREATE OR REPLACE FUNCTION f_fin_seed(p_user bigint) RETURNS void LANGUAGE plpgsql SET search_path = agente, public AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM fin_categories WHERE user_id = p_user) THEN RETURN; END IF;
  INSERT INTO fin_categories (user_id, name, kind, keywords, is_default) VALUES
    (p_user, 'Alimentação', 'expense', ARRAY['ifood','restaurante','lanche','pizza','almoco','jantar','cafe','padaria','hamburguer','sorvete','acai','comida'], true),
    (p_user, 'Mercado', 'expense', ARRAY['mercado','supermercado','feira','atacadao','hortifruti','acougue'], true),
    (p_user, 'Transporte', 'expense', ARRAY['uber','99','gasolina','combustivel','onibus','metro','estacionamento','pedagio','taxi','passagem'], true),
    (p_user, 'Moradia', 'expense', ARRAY['aluguel','condominio','luz','energia','agua','internet','gas','iptu','reforma','claro','vivo','tim','telefone','celular'], true),
    (p_user, 'Saúde', 'expense', ARRAY['farmacia','remedio','consulta','dentista','plano de saude','exame','psicologo','academia'], true),
    (p_user, 'Lazer', 'expense', ARRAY['cinema','bar','show','viagem','balada','jogo','passeio','festa'], true),
    (p_user, 'Educação', 'expense', ARRAY['curso','escola','faculdade','livro','mensalidade','material escolar'], true),
    (p_user, 'Assinaturas', 'expense', ARRAY['netflix','spotify','assinatura','icloud','youtube','prime','disney','hbo'], true),
    (p_user, 'Compras', 'expense', ARRAY['roupa','tenis','amazon','shopee','mercado livre','loja','presente','eletronico'], true),
    (p_user, 'Outros', 'expense', ARRAY[]::text[], true),
    (p_user, 'Recebimentos', 'income', ARRAY['recebi','pix recebido','reembolso','freela','freelance'], true),
    (p_user, 'Salário', 'income', ARRAY['salario','pagamento','holerite'], true)
  ON CONFLICT DO NOTHING;
END $$;
