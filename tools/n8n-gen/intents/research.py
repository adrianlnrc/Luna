# Intencao research (M5 / fase 5): pesquisa com fonte citada e aviso de custo sem bloqueio.
# Depende de db/029_pesquisa.sql e do sub-workflow "Agente | Pesquisa" (codigo em subworkflows/gen_pesquisa.py).
from .core import Intent

PESQUISA_WF_ID = 'HHhnrZ4dMoKxs5YI'   # Agente | Pesquisa

PESQUISA_RULE = ("PESQUISA (intent=research): pergunta sobre FATO ATUAL OU EXTERNO que so se responde buscando na internet: cambio e cotacao (cambio do dolar hoje), "
  "preco medio de um produto (preco medio de um notebook para arquitetura), regra ou lei (qual a regra do IPVA em SP), norma tecnica (norma de acessibilidade para rampa), "
  "noticia, previsao do tempo, indicacao de lugar ou servico. research_query = a pergunta reescrita completa e autocontida, numa frase, SEM nome da pessoa, endereco, telefone, "
  "e-mail, valores dela ou qualquer dado pessoal (so o assunto). Preencha reply com texto vazio e title, date e time vazios. "
  "NAO use research para pedidos pessoais: agenda, lembretes, gastos, listas, notas, tarefas, projetos, documentos, contatos, remedios, nem para conversa simples (ola, obrigado, o que voce faz). "
  "Esses seguem as outras regras. Reservar mesa, hotel ou passagem e comprar ou pedir algo continuam fora do escopo (intent=chat).")

INTERPRET = """if (out.intent === 'research') {
  let pq = String(out.research_query || '').trim();
  if (pq === '') { pq = String(out.transcript || u.text || '').trim(); }
  out.research_query = pq.slice(0, 500);
}"""


def build():
    # roda com as globais do gen.py: constantes deste modulo entram por import
    from intents.research import PESQUISA_WF_ID
    IR = "$('Interpretar resposta').first().json."
    ex = exec_wf('Pesquisa: executar', PESQUISA_WF_ID,
      {"user_id": "={{ String(" + IR + "user_id) }}", "chat_id": "={{ String(" + IR + "chat_id) }}", "pergunta": "={{ " + IR + "research_query }}"},
      [4480, 4800])
    ex['onError'] = 'continueRegularOutput'
    nodes.append(ex)
    nodes.append(code_node('Pesquisa: resposta',
      "const a = $('Interpretar resposta').first().json;\nconst r = $input.first().json || {};\n"
      "const text = r.text ? String(r.text) : 'Não consegui pesquisar agora. Tente de novo daqui a pouco.';\n"
      "return [{ json: { chat_id: a.chat_id, text: text, kb: 'none', rid: 0, state: '' } }];", [4704, 4800]))
    _refresh()
    setc('Pesquisa: executar', ['Pesquisa: resposta'])
    setc('Pesquisa: resposta', ['Preparar envio'])


INTENT = Intent(
    name='research',
    hint="research (pergunta sobre fato atual ou externo que precisa de busca na internet: cambio, preco medio, regra ou lei, norma tecnica, noticia, tempo)",
    schema="  research_query: NN('string')",     # a 2 espacos de indentacao, como no patch original
    rules=[PESQUISA_RULE],
    interpret_js=INTERPRET,
    route=('pesquisa', 'Pesquisa: executar'),
    build=build,
)
