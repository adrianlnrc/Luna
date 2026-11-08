-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_menu_base(p_user bigint, p_key text)
-- Origem da definicao atual: 023_locais_pergunta.sql (linha 246)
-- Definicoes (migracao:linha), da mais antiga a atual: 022_menu.sql:8, 023_locais_pergunta.sql:246
-- Renomeada de f_menu para f_menu_base em 024_ciclo_correcoes.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_menu_base).
CREATE OR REPLACE FUNCTION f_menu(p_user bigint, p_key text) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE k text := lower(coalesce(btrim(p_key), 'inicio')); t text;
BEGIN
  t := CASE k
  WHEN 'lembretes' THEN
    E'Lembretes e avisos\nEu aviso na hora e você escolhe: Feito, Adiar 1h ou Adiar amanhã.\n\nTente dizer:\n- "me lembre amanhã às 9h de passar na farmácia"\n- "toda sexta às 18h me lembre de pagar a diarista"\n- "lembra nos dois de comprar pão às 18h" (aviso para você e para a outra pessoa)\n- "sempre me avise 30 min antes dos compromissos"\n- "para de me lembrar da vitamina D"'
  WHEN 'agenda' THEN
    E'Agenda (Google Agenda)\nCrio, mostro, movo e cancelo compromissos. Convites que você receber chegam aqui com Aceitar e Recusar.\n\nTente dizer:\n- "o que tenho hoje?" ou "o que tenho essa semana?"\n- "reunião sexta às 10h, me lembre 1h antes"\n- "move a reunião de sexta para 15h"\n- "cancela a reunião de amanhã"\n- "quando estou livre quinta à tarde?"\n\nMudanças e cancelamentos pedem confirmação por botão.'
  WHEN 'tarefas' THEN
    E'Tarefas (Google Tasks)\nAfazeres soltos, sem hora marcada.\n\nTente dizer:\n- "anota na lista: ligar pro contador"\n- "o que tenho nas tarefas?"\n- "conclui a tarefa do contador"\n- "o que eu concluí essa semana?"\n\nPara guardar uma ideia ou um texto livre, use as Notas: "anota a ideia ...".'
  WHEN 'remedios' THEN
    E'Remédios e estoque\nControlo quanto resta, aviso na hora de tomar e quando está acabando.\n\nTente dizer:\n- "me lembre de tomar losartana todo dia às 8h" (repito a cada 10 min até você tocar Tomei)\n- "tomei a vitamina D"\n- "comprei a vitamina D"\n- "tenho 12 na cartela"\n\nPode mandar a foto da cartela: eu leio o nome e quantos comprimidos restam. O aviso de compra vem no resumo da manhã.'
  WHEN 'dinheiro' THEN
    E'Dinheiro\nRegistro gastos e receitas e mostro para onde o dinheiro foi.\n\nTente dizer:\n- "gastei 42 no mercado" (texto, áudio, foto ou PDF do recibo)\n- "tênis 600 em 3x" ou "aluguel 1500 todo dia 5"\n- "quanto gastei esse mês?" ou "compara com o mês passado"\n- "orçamento de mercado 800" (aviso em 80% e 100%)\n- "o que tenho a pagar?" e "já paguei o aluguel"\n- "o João me deve 50"\n\nO botão Desfazer apaga o último lançamento. "Fecha dia 10" muda o dia de fechamento do mês.'
  WHEN 'pessoas' THEN
    E'Contatos, grupos e locais\nGuardo e-mails, grupos e endereços para marcar compromissos com um pedido só. Os locais ficam guardados só para você, no meu banco de dados.\n\nTente dizer:\n- "salva o e-mail da Cláudia: claudia@x.com"\n- "cria o grupo família com Ana e Bia"\n- "o local igreja é Rua das Flores, 120"\n- "festa da igreja na sexta com a família" (uso o endereço e o grupo salvos, pergunto só a hora e confirmo antes de enviar o convite)\n\nSe você marcar algo num lugar que eu não conheço (por exemplo "na igreja"), eu pergunto o endereço e salvo para as próximas vezes.\n\n/contatos mostra contatos, grupos e locais. /locais mostra só os locais, e como salvar e tirar.'
  WHEN 'docs' THEN
    E'Documentos\nGuardo seus arquivos por pasta e devolvo quando você pedir. Eu guardo só o identificador do arquivo no Telegram, não o conteúdo. Até 50 MB cada.\n\nTente:\n- mandar a foto ou o PDF e dizer "guarda na pasta Casa"\n- "acha a apólice"\n- "me manda tudo da pasta Reforma"\n- "me avisa antes do alvará vencer em 20/12"'
  WHEN 'listas' THEN
    E'Listas e notas\nListas para marcar e notas de texto livre para achar depois.\n\nTente dizer:\n- "lista de mercado: arroz, café e detergente"\n- "marca o arroz" ou "comprei o café"\n- "me mostra a lista de mercado"\n- "anota a ideia da assinatura anual"\n- "o que eu anotei sobre a expansão?"\n- "minhas últimas notas"\n\nApagar ou esvaziar pede confirmação.'
  WHEN 'projetos' THEN
    E'Projetos\nTrabalhos maiores, com prazo e várias tarefas.\n\nTente dizer:\n- "novo projeto Reforma, prazo 30/11"\n- "adiciona as tarefas pintar sala e trocar piso"\n- "quebra o projeto em tarefas" (eu sugiro e você confirma)\n- "marca contratar pintor como feito"\n- "como está a reforma?"\n- "o que está atrasado?"\n\nProjetos com prazo perto aparecem no resumo da manhã.'
  WHEN 'resumos' THEN
    E'Resumos\nManhã (padrão 07:30): compromissos, tarefas, lembretes, contas, estoque e projetos. Fim do dia (20:00): o que ficou pendente e o que vem amanhã.\n\nTente dizer:\n- "resumo às 8h"\n- "desliga o resumo do fim do dia"'
  WHEN 'ajustes' THEN
    E'Ajustes\n/config mostra suas preferências. Para mudar, é só pedir:\n- "me chama de Dri"\n- "sem emojis"\n- "sempre me avise 30 min antes"\n- "avise o estoque com 7 dias"\n- "fecha dia 10"'
  WHEN 'entrada' THEN
    E'Voz, foto e PDF\nPode falar comigo como falaria com uma pessoa.\n\n- Áudio: eu transcrevo e faço o pedido.\n- Foto ou PDF de recibo, nota ou boleto: eu leio e lanço o gasto para você confirmar.\n- Foto da cartela de remédio: eu leio o nome e a quantidade.\n- Quando eu perguntar algo ("Que horas?"), responda numa mensagem só, como "às 19h".'
  ELSE
    E'O que eu faço\nToque numa área para ver o que dá para pedir, com exemplos. Você pode falar do jeito que fala no dia a dia, por texto ou áudio.'
  END;
  RETURN jsonb_build_object('text', t, 'kb', 'menu', 'rid', 0);
END $$;
