-- 036: menu reformulado (13 -> 9 areas), tom de secretaria, "Ver mais" por area.
-- Contrato e chaves: ver 036_menu_contrato.md. NAO aplicado em producao.
-- Idempotente. Substitui agente.f_menu(bigint, text) por uma funcao autocontida (a anterior vira f_menu_pre_f13).
-- Retorno: jsonb {text, kb, rid}.
--   inicio            -> kb 'menu'       rid 0
--   area n (1..9)     -> kb 'menu_area'  rid n   (botoes: Ver mais = mn:mais<n>, Voltar ao menu = mn:inicio)
--   mais da area n    -> kb 'menu_mais'  rid n   (botoes: Voltar a area = mn:a<n>, Menu = mn:inicio)
SET search_path TO agente, public;

DO $do$
BEGIN
  IF to_regproc('agente.f_menu_pre_f13') IS NULL THEN
    ALTER FUNCTION agente.f_menu(bigint, text) RENAME TO f_menu_pre_f13;
  END IF;
END $do$;

CREATE OR REPLACE FUNCTION agente.f_menu(p_user bigint, p_key text) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $f$
DECLARE
  k text := lower(btrim(coalesce(p_key, 'inicio')));
  n int;
  mais boolean := false;
  t text;
  dica text := 'Pode mandar vários pedidos juntos: eu faço todos e mostro num Feito:. Se errar, toque em Desfazer tudo.';
BEGIN
  -- atalhos vindos dos botoes: mais<n> (Ver mais) e a<n> (Voltar a area)
  IF k ~ '^mais[1-9]$' THEN
    n := substr(k, 5)::int; mais := true;
  ELSIF k ~ '^a[1-9]$' THEN
    n := substr(k, 2)::int;
  ELSE
    IF k ~ '_mais$' THEN mais := true; k := regexp_replace(k, '_mais$', ''); END IF;
    n := CASE k
      WHEN 'lemb' THEN 1 WHEN 'lembretes' THEN 1 WHEN 'agenda' THEN 1 WHEN 'resumos' THEN 1
      WHEN 'tar' THEN 2 WHEN 'tarefas' THEN 2 WHEN 'listas' THEN 2 WHEN 'notas' THEN 2
      WHEN 'din' THEN 3 WHEN 'dinheiro' THEN 3
      WHEN 'rem' THEN 4 WHEN 'remedios' THEN 4
      WHEN 'proj' THEN 5 WHEN 'projetos' THEN 5
      WHEN 'doc' THEN 6 WHEN 'docs' THEN 6 WHEN 'documentos' THEN 6
      WHEN 'pess' THEN 7 WHEN 'pessoas' THEN 7 WHEN 'contatos' THEN 7 WHEN 'locais' THEN 7 WHEN 'memoria' THEN 7
      WHEN 'foto' THEN 8 WHEN 'entrada' THEN 8 WHEN 'pesquisa' THEN 8
      WHEN 'aj' THEN 9 WHEN 'ajustes' THEN 9
      ELSE NULL END;
  END IF;

  IF n IS NULL THEN
    t := $m$O que eu faço

Toque numa área para ver exemplos. Pode falar do jeito do dia a dia, por texto ou áudio.

Errei? Diga: "na verdade o dentista é às 10".

Outros exemplos:
- "gastei 42 no mercado"
- "me lembra amanhã às 9h de ligar pro contador"
- "reunião sexta às 14h"

Pode mandar vários pedidos juntos: eu faço todos e mostro num Feito:. Se errar, toque em Desfazer tudo.$m$;
    RETURN jsonb_build_object('text', t, 'kb', 'menu', 'rid', 0);
  END IF;

  IF NOT mais THEN
    t := CASE n
    WHEN 1 THEN $m$Lembretes e agenda
Eu aviso na hora e você escolhe: Feito, Adiar 1h ou Adiar amanhã. A agenda é o seu Google Agenda.

Tente dizer:
- "me lembra amanhã às 9h de passar na farmácia"
- "toda sexta às 18h me lembra de pagar a diarista"
- "o que tenho hoje?" ou "o que tenho essa semana?"
- "reunião sexta às 10h, me lembra 1h antes"
- mande a foto da sua agenda de papel e eu monto o rascunho

Mudar ou cancelar compromisso eu confirmo com você antes.$m$
    WHEN 2 THEN $m$Tarefas e listas
Tarefa é afazer solto, sem hora. Lista serve para marcar itens. Nota guarda texto livre.

Tente dizer:
- "anota na lista: ligar pro contador"
- "o que tenho nas tarefas?"
- "conclui a tarefa do contador"
- "preciso comprar leite" (vai para a lista de mercado)
- "anota a ideia da assinatura anual"$m$
    WHEN 3 THEN $m$Dinheiro
Registro gastos e receitas e mostro para onde o dinheiro foi.

Tente dizer:
- "gastei 42 no mercado" (texto, áudio, foto ou PDF do recibo)
- "tênis 600 em 3x" ou "aluguel 1500 todo dia 5"
- "quanto gastei esse mês?"
- "orçamento de mercado 800" (aviso em 80% e 100%)
- "o que tenho a pagar?" e "já paguei o aluguel"

Cada lançamento vem com Desfazer e Editar, por 24 horas.$m$
    WHEN 4 THEN $m$Remédios
Controlo quanto resta, aviso na hora de tomar e quando está acabando.

Tente dizer:
- "me lembra de tomar losartana todo dia às 8h" (repito a cada 10 min até você tocar Tomei)
- "tomei a vitamina D"
- "comprei a vitamina D"
- "tenho 12 na cartela"
- mande a foto da cartela e eu leio o nome e quantos comprimidos restam$m$
    WHEN 5 THEN $m$Projetos
Trabalhos maiores, com prazo e várias tarefas. Eles também aparecem no Google Tarefas.

Tente dizer:
- "novo projeto Reforma, prazo 30/11"
- "adiciona as tarefas pintar sala e trocar piso"
- "quebra o projeto em tarefas" (eu sugiro e você confirma)
- "marca contratar pintor como feito"
- "como está a reforma?"$m$
    WHEN 6 THEN $m$Documentos
Guardo seus arquivos por pasta e devolvo quando você pedir.

Tente dizer:
- mande a foto ou o PDF e diga "guarda na pasta Casa"
- "acha a apólice"
- "me manda tudo da pasta Reforma"
- "me avisa antes do alvará vencer em 20/12"$m$
    WHEN 7 THEN $m$Pessoas e memória
Guardo contatos, grupos e lugares para marcar compromissos com um pedido só. Também lembro de fatos seus.

Tente dizer:
- "salva o e-mail da Cláudia: claudia@x.com"
- "cria o grupo família com Ana e Bia"
- "o local igreja é Rua das Flores, 120"
- "festa da igreja na sexta com a família"
- "esquece isso" (apago o último fato que anotei)

/memoria mostra o que eu sei de você e deixa apagar.$m$
    WHEN 8 THEN $m$Fotos, áudio e pesquisa
Pode falar comigo como falaria com uma pessoa.

Tente:
- áudio: eu transcrevo e faço o pedido
- foto ou PDF de recibo, nota ou boleto: eu leio e lanço o gasto para você confirmar
- foto da cartela de remédio: eu leio o nome e a quantidade
- foto da agenda de papel: eu monto o rascunho
- pesquisa: "câmbio do dólar hoje" (respondo curto, com as fontes)

Cada pesquisa gasta um pouco da minha conta de IA. Mostro a estimativa em reais no fim da resposta.$m$
    WHEN 9 THEN $m$Ajustes
/config mostra suas preferências. Para mudar, é só pedir:
- "me chama de Dri"
- "sem emojis"
- "sempre me avise 30 min antes"
- "resumo às 8h"
- "avise o estoque com 7 dias"

/custo mostra quanto gastei de IA hoje e no mês.$m$
    END;
    t := t || E'\n\n' || dica;
    RETURN jsonb_build_object('text', t, 'kb', 'menu_area', 'rid', n);
  END IF;

  t := CASE n
  WHEN 1 THEN $m$Lembretes e agenda: ver mais

Lembretes:
- "lembra nos dois de comprar pão às 18h" (aviso para você e para a outra pessoa)
- "sempre me avise 30 min antes dos compromissos"
- "para de me lembrar da vitamina D"
- "me lembra todo ano do IPVA em 15/01" (aviso 15 dias antes, sem pedir)

Agenda:
- "move a reunião de sexta para 15h"
- "cancela a reunião de amanhã"
- "quando estou livre quinta à tarde?"
Convites que você receber chegam aqui com Aceitar e Recusar.

Agenda de papel: eu leio a foto e mostro um rascunho. Você corrige ("o 3 é na segunda") e só então eu crio.

Resumos:
De manhã (padrão 07:30) mando compromissos, tarefas, lembretes, contas e estoque. No fim do dia (20:00), o que ficou pendente e o que vem amanhã.
- "resumo às 8h"
- "desliga o resumo do fim do dia"$m$
  WHEN 2 THEN $m$Tarefas e listas: ver mais

Tarefas:
- "o que eu concluí essa semana?"
Com hora, vira lembrete: "me lembra de comprar pão às 18h".

Listas:
- "lista de mercado: arroz, café e detergente"
- "marca o arroz" ou "comprei o café"
- "me mostra a lista de mercado"

Lista de compras:
- sem hora ("acabou o café"), o item entra na lista Mercado
- vários itens: um por linha, começando com traço (- leite, - 2 pães, - ovos)
- se a primeira linha tiver outro nome ("Farmácia:"), os itens vão para essa lista
"Compras", "mercado", "supermercado" e "feira" são a mesma lista.

Notas:
- "o que eu anotei sobre a expansão?"
- "minhas últimas notas"

Apagar ou esvaziar uma lista eu confirmo antes.$m$
  WHEN 3 THEN $m$Dinheiro: ver mais

Mais pedidos:
- "compara com o mês passado"
- "o João me deve 50"
- "fecha dia 10" (muda o dia de fechamento do mês)
- "gastei 120 na farmácia e 80 no mercado" (vira dois lançamentos)

Corrigir um lançamento (depois das 24 horas, ou outro qualquer):
- "corrige para 50"
- "isso é Lazer"
- "foi dia 12"

Relatórios:
- "me manda o relatório do mês em Excel"
- "extrato de outubro em CSV"
- "gastos do ano em Excel"
- "relatório para o imposto de renda" (Saúde e Educação)
Não gero PDF.

Avisos automáticos, sem bloquear nada:
- assinatura que mudou de valor ("Spotify subiu de R$ 21,90 para R$ 27,90")
- cobrança que parece repetida
- fatura do cartão 30% ou mais acima da média$m$
  WHEN 4 THEN $m$Remédios: ver mais

Estoque:
- o aviso de compra vem no resumo da manhã
- "avise o estoque com 7 dias" muda a antecedência

Corrigir e apagar:
- "o nome é sertralina" (corrijo o nome de um item genérico)
- "apaga o remédio sertralina" (eu confirmo por botão)

Se faltar o nome ao cadastrar, eu pergunto.$m$
  WHEN 5 THEN $m$Projetos: ver mais

Mais pedidos:
- "o que está atrasado?"
- "coloca a tarefa ligar pro contador no projeto Reforma"
- "marca contratar pintor como urgente"
- "tira a urgência de contratar pintor"

Projetos com prazo perto aparecem no resumo da manhã.
A tarefa do Google Tasks continua lá. Diga "conclui a tarefa ..." para dar baixa.$m$
  WHEN 6 THEN $m$Documentos: ver mais

- aceito arquivos de até 50 MB cada
- eu guardo só o identificador do arquivo no Telegram, não o conteúdo
- "me manda tudo da pasta Reforma" devolve os arquivos da pasta
- para vencimentos, diga a data: "me avisa antes do alvará vencer em 20/12"$m$
  WHEN 7 THEN $m$Pessoas e memória: ver mais

Pessoas, grupos e lugares:
- "festa da igreja na sexta com a família": uso o endereço e o grupo salvos, pergunto só a hora e confirmo antes de enviar o convite
- os lugares ficam só para você, no meu banco de dados
- /contatos mostra só pessoas e grupos
- /locais mostra só lugares

Memória:
- quando eu guardo um fato seu, aviso com "Anotei: ..."
- "esquece isso" ou "esquece que a Marta é minha sogra"
- "o que você sabe de mim?"
- "desliga a memória" para eu parar de anotar, "liga a memória" para voltar
Cada pessoa tem a sua memória. Ninguém vê a do outro.$m$
  WHEN 8 THEN $m$Fotos, áudio e pesquisa: ver mais

Quando eu perguntar algo ("Que horas?"), responda numa mensagem só, como "às 19h".

Pesquisa na web:
- respondo curto, com as fontes (título e link)
- se não achar fonte confiável, eu digo
- "preço médio de um notebook para arquitetura"
- "qual a regra do IPVA em SP?"
- "norma de acessibilidade para rampa"

Custo: mostro no fim da resposta a estimativa em reais, mais o total do dia e do mês. É só um aviso: a pesquisa sempre é feita. Se o gasto do dia passar do limite (padrão R$ 1,00), o aviso fica em destaque.

Limite: 3 pesquisas por minuto. Envio à OpenAI só a sua pergunta, nada da sua agenda, finanças ou contatos. Pedidos pessoais não vão para a pesquisa.$m$
  WHEN 9 THEN $m$Ajustes: ver mais

Comandos:
- /menu mostra esta tela
- /memoria mostra o que eu sei de você
- /config mostra suas preferências
- /custo mostra o gasto de IA

Mais pedidos:
- "fecha dia 10" (dia de fechamento do mês)
- "desliga o resumo do fim do dia"
- "quanto estou gastando de IA?"

O /custo mostra o gasto por tipo, com a projeção do mês. É uma estimativa.$m$
  END;
  RETURN jsonb_build_object('text', t, 'kb', 'menu_mais', 'rid', n);
END $f$;
