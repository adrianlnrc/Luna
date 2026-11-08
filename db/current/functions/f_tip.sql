-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_tip(p_user bigint)
-- Origem da definicao atual: 022_menu.sql (linha 61)
-- Definicoes (migracao:linha), da mais antiga a atual: 022_menu.sql:61
CREATE OR REPLACE FUNCTION f_tip(p_user bigint) RETURNS text
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE tz text; n timestamp; tips text[] := ARRAY[
  'Você sabia? Mande a foto de um recibo e eu lanço o gasto para você confirmar.',
  'Você sabia? Diga "o local igreja é Rua das Flores, 120" uma vez e depois só "festa da igreja na sexta com a família".',
  'Você sabia? "Quebra o projeto em tarefas" e eu sugiro as tarefas para você confirmar.',
  'Você sabia? "Me manda tudo da pasta Casa" reenvia os documentos que você guardou.',
  'Você sabia? "Orçamento de mercado 800" e eu aviso quando passar de 80%.',
  'Você sabia? "Lembra nos dois de comprar pão às 18h" avisa você e a outra pessoa.',
  'Você sabia? Mande a foto da cartela do remédio e eu leio o nome e quantos comprimidos restam.',
  'Você sabia? "Quanto gastei esse mês?" mostra o resumo por categoria.',
  'Você sabia? "Marca 30 min com a contadora e manda o link" cria o convite com Meet, depois que você confirmar.',
  'Você sabia? Toque em /menu para ver tudo o que eu faço, com exemplos.'];
BEGIN
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  n := now() AT TIME ZONE coalesce(tz, 'America/Sao_Paulo');
  IF extract(hour FROM n) >= 12 OR extract(dow FROM n) NOT IN (1, 4) THEN RETURN ''; END IF;
  RETURN tips[1 + (extract(doy FROM n)::int + extract(year FROM n)::int) % array_length(tips, 1)];
END $$;
