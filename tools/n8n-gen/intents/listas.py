# Intencoes list_manage e note_manage (Fase 4, modulo N): listas de itens e notas livres.
# Depende de db (agente.f_lists, f_notes, f_lists_cb).
from .core import Intent, Edit

INTERPRET = """if (out.intent === 'list_manage') {
  out.list_json = JSON.stringify({
    list_action: out.list_action || '', list_name: out.list_name || '',
    list_items: Array.isArray(out.list_items) ? out.list_items.filter(function (x) { return String(x || '').trim() !== ''; }) : [],
    text: String(out.transcript || u.text || '')
  });
}
if (out.intent === 'note_manage') {
  out.note_json = JSON.stringify({
    note_action: out.note_action || '', note_text: out.note_text || '', note_query: out.note_query || '',
    text: String(out.transcript || u.text || '')
  });
}"""

# (cada regra vira uma linha so: as quebras de linha sao trocadas por espaco, como no patch original)
RULES = [r.replace(chr(10), ' ') for r in [
 """LISTAS (intent=list_manage): lista de ITENS para comprar, levar ou organizar (mercado, farmacia, compras, mala de viagem, material de obra). NAO e create_task (create_task = pendencia solta do Google Tasks, uma ACAO a fazer: ligar pro contador, pagar o IPTU, renovar a CNH) e NAO e nota livre. list_action: create (lista de mercado: arroz, cafe e detergente = list_name mercado, list_items [arroz, cafe, detergente]), add (adiciona sabao em po na lista; poe leite e pao na lista de mercado; coloca ovos na lista), remove (tira o cafe; tira o cafe da lista), check (marca o arroz; comprei o cafe; ja peguei o leite e o pao), uncheck (desmarca o arroz), show (me mostra a lista de mercado; o que falta comprar?; o que tem na lista?), clear (limpa a lista; esvazia a lista de mercado: esvazia os itens e mantem a lista), delete (apaga a lista de mercado; exclui a lista da farmacia: apaga a lista inteira), lists (minhas listas; quais listas eu tenho?). list_name = so o nome (mercado, farmacia), sem a palavra lista; null se o usuario nao citou. list_items = um item por posicao, curto e sem verbo (2 kg de arroz fica 2 kg de arroz). Em list_manage preencha reply com texto vazio.""",
 """LISTA x TAREFA x NOTA x LEMBRETE: anota na lista: ligar pro contador = create_task (acao). comprar leite, sem citar lista nem mercado = create_task. poe leite na lista = list_manage add. leite, pao e ovos na lista de mercado = list_manage. me lembra de comprar pao as 18h = create_reminder (tem horario). anota a ideia da assinatura anual = note_manage save. comprei a vitamina D, quando for item de estoque ou remedio cadastrado, continua supply_bought; comprei o cafe da lista = list_manage check.""",
 """NOTAS (intent=note_manage): texto livre para consultar depois (ideia, informacao, codigo, algo que alguem disse), SEM horario de aviso e que nao e uma acao a fazer nem item de compra. note_action: save (anota a ideia da assinatura anual; anota: o wifi do escritorio e 12345; guarda essa ideia: ...; note_text = o conteudo fiel ao que o usuario disse, sem o verbo anota e sem resumir), search (o que eu tinha anotado sobre a expansao?; acha minha nota do wifi; note_query = so as palavras-chave do assunto), list (minhas ultimas notas; minhas notas), delete (apaga a nota da assinatura; exclui a ultima nota; note_query = palavras-chave, vazio para a ultima nota). Em note_manage preencha reply com texto vazio.""",
]]


# campos do schema da IA (inseridos antes da ancora, na ordem em que os modulos entram)
SCHEMA_LIST = """list_action: { type: ['string', 'null'], enum: ['create', 'show', 'add', 'remove', 'check', 'uncheck', 'clear', 'delete', 'lists', null] },
  list_name: NN('string'), list_items: { type: ['array', 'null'], items: { type: 'string' } },"""
SCHEMA_NOTE = """note_action: { type: ['string', 'null'], enum: ['save', 'search', 'list', 'delete', null] },
  note_text: NN('string'), note_query: NN('string'),"""


def build():
    global nodes, byname
    IR = "$('Interpretar resposta').first().json."
    nodes.append(pg_node('Listas: executar', "SELECT agente.f_lists($1::bigint, $2::jsonb) AS r",
      "={{ [ " + IR + "user_id, " + IR + "list_json ] }}", [4480, 4400]))
    nodes.append(pg_node('Notas: executar', "SELECT agente.f_notes($1::bigint, $2::jsonb) AS r",
      "={{ [ " + IR + "user_id, " + IR + "note_json ] }}", [4480, 4592]))
    nodes.append(code_node('Listas: resposta',
      "const a = $('Interpretar resposta').first().json;\nconst r = $input.first().json.r || {};\nreturn [{ json: { chat_id: a.chat_id, text: r.text || 'Nao consegui agora. Tente de novo.', kb: r.kb || 'none', rid: r.rid || 0, state: '' } }];",
      [4704, 4496]))
    _refresh()
    for _n in ('Listas: executar', 'Notas: executar'):
        byname[_n]['onError'] = 'continueRegularOutput'
    setc('Listas: executar', ['Listas: resposta'])
    setc('Notas: executar', ['Listas: resposta'])
    setc('Listas: resposta', ['Preparar envio'])
    add_kb('ls_confirm', [('Confirmar', 'lsok:{rid}'), ('Cancelar', 'lsno:{rid}')])

    # /start e /ajuda
    rc = byname['Resposta do comando']['parameters']['jsCode']
    rc = rep(rc, "    'Privacidade: para entender", "    'Listas e notas: \"lista de mercado: arroz, cafe e detergente\", \"marca o arroz\", \"anota a ideia da assinatura anual\", \"o que eu tinha anotado sobre a expansao?\".', '',\n    'Privacidade: para entender")
    rc = rep(rc, "    'Quando eu avisar um lembrete, use os botoes:", """    '- "lista de mercado: arroz, cafe e detergente" / "adiciona sabao em po na lista" / "tira o cafe" / "marca o arroz" (ou "comprei o cafe") / "me mostra a lista de mercado" / "minhas listas" / "limpa a lista" / "apaga a lista de mercado" (confirmo antes de apagar)',
    '- "anota a ideia da assinatura anual" / "o que eu tinha anotado sobre a expansao?" / "minhas ultimas notas" / "apaga a nota da assinatura" (confirmo antes de apagar)',
    'Quando eu avisar um lembrete, use os botoes:""")
    byname['Resposta do comando']['parameters']['jsCode'] = rc
    _refresh()


INTENT = Intent(
    name='list_manage',
    also=['note_manage'],
    enum_after='document_manage',
    also_after={'note_manage': 'list_manage'},
    schema_parts=[(SCHEMA_LIST, "\n  ", "card: NN('string'),"), (SCHEMA_NOTE, "\n  ", "card: NN('string'),")],
    hint='list_manage (listas de itens: mercado, farmacia, compras, mala), note_manage (notas livres: ideias e informacoes para consultar depois)',
    rules=RULES,
    interpret_js=INTERPRET,
    edits=[Edit('Montar pedido a IA', 'jsCode', 'SEM horario: comprar leite, ligar pro contador)',
                'SEM horario, e uma ACAO a fazer: ligar pro contador, pagar o IPTU, renovar a CNH; itens de compra em lista sao list_manage)')],
    route=('listas', 'Listas: executar'),
    routes=[('notas', 'note_manage', 'Notas: executar')],
    build=build,
)
