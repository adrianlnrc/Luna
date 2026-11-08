# Intencoes agenda_import e agenda_import_edit (F8): importar agenda de papel por foto (compromissos -> Google Agenda, tarefas -> Google Tarefas).
# Depende de db/031_agenda_import.sql (agenda_import, f_agimp_create/edit/confirm/done/cb, f_callback com o prefixo ai*)
# e do sub-workflow "Agente | Importar agenda" (codigo em subworkflows/importar_agenda.sdk.js).
# Executar botao passa por 'Importar agenda: botao em massa?' antes de 'Agenda: acao externa?'.
from .core import Intent, Edit

AGENDA_RULE = ("AGENDA DE PAPEL (intent=agenda_import): foto de uma agenda, planner ou calendario de papel com VARIOS compromissos (pagina semanal ou mensal, grade de horarios, blocos coloridos ou anotacoes a mao por dia). "
  "Preencha reply com texto vazio e title, date e time vazios. NAO e create_event: convite, cartaz ou print com UM evento so continua create_event. "
  "Se a pessoa pedir para importar, passar ou copiar a agenda mas NAO mandou foto, use chat e peca a foto da pagina inteira. "
  "CORRECAO DA IMPORTACAO (intent=agenda_import_edit): quando a conversa recente traz a mensagem do assistente que comeca com Li sua agenda (lista numerada de compromissos e tarefas) "
  "e a pessoa corrige, tira, muda ou confirma algo dela, use agenda_import_edit com imp_action = edit (o 3 e na segunda, o 4 termina as 16h, o 2 e as 14h, muda o titulo do 5 para Prova, o 6 e uma tarefa), "
  "remove (tira o 5, nao precisa do 2), confirm (pode criar, cria tudo, confirma) ou cancel (cancela, deixa pra la). "
  "imp_n = numero do item na lista (null se nao citou); date = a NOVA data YYYY-MM-DD dentro da semana da lista (na segunda = a segunda dessa semana; vazio se nao mudou); "
  "time = NOVA hora de inicio HH:MM (vazio se nao mudou); imp_end = NOVA hora de fim HH:MM (null se nao mudou); title = novo titulo (vazio se nao mudou). Preencha reply com texto vazio.")

INTERPRET = """if (out.intent === 'agenda_import' && ctx.via_photo !== true) {
  out.intent = 'chat';
  out.reply = 'Para importar a sua agenda, mande a foto da página inteira, bem iluminada e sem reflexo. Eu leio e mostro tudo antes de criar.';
}
if (out.intent === 'agenda_import_edit') {
  const iact = (out.imp_action === 'edit' || out.imp_action === 'remove' || out.imp_action === 'confirm' || out.imp_action === 'cancel') ? out.imp_action : 'edit';
  const hm2 = function (v) { return (v && okTime.test(v)) ? (v.length === 4 ? '0' + v : v) : ''; };
  out.imp_json = JSON.stringify({ act: iact, n: (typeof out.imp_n === 'number') ? out.imp_n : null, title: out.title || '',
    date: (out.date && okDate.test(out.date)) ? out.date : '', time: hm2(out.time), end: hm2(out.imp_end) });
}"""


def build():
    global nodes, byname
    IMPORTAR_WF_ID = '30nv9jzvF504UQUu'   # Agente | Importar agenda
    PFX = 'Importar agenda: '
    MPI = "$('" + PFX + "montar pedido').first().json."

    # 3) Leitura da foto: pedido dedicado (so a imagem e a legenda vao a IA)
    MONTAR = r"""const m = $('Montar pedido a IA').first().json;
const a = $('Interpretar resposta').first().json;
const NL = String.fromCharCode(10);
const tz = a.tz || 'America/Sao_Paulo';
let hoje = '';
try { hoje = DateTime.now().setZone(tz).toFormat('yyyy-MM-dd'); } catch (e) { hoje = new Date().toISOString().slice(0, 10); }
const regras = [
  'Voce le a FOTO de uma agenda ou planner de papel e devolve os compromissos e as tarefas da pagina em JSON, sem inventar nada.',
  'A foto pode estar girada 90 graus ou torta: gire mentalmente para ler. Pode haver duas paginas lado a lado (a semana inteira em duas paginas).',
  'Hoje e ' + hoje + ' (fuso ' + tz + '). Leia o cabecalho de cada dia (nome, numero do dia e o mes impresso) e monte as datas completas YYYY-MM-DD. Se o ano nao estiver escrito, use o ano de hoje. week_start = a segunda-feira (ou o primeiro dia) da semana mostrada.',
  'LEGENDA: se a pagina tem legenda de cores (quadrados coloridos com nomes como Academia, Faculdade, Estagio, Igreja, Tarefas), a cor de cada bloco indica a categoria. Copie os nomes exatamente como estao escritos e liste a legenda em legend.',
  'GRADE DE HORARIOS: as linhas marcadas com horas (7h, 8h... 22h) formam a grade de cada dia. Um bloco colorido que cobre linhas de uma hora a outra e UM compromisso: start = hora da primeira linha coberta, end = hora logo apos a ultima linha coberta (HH:MM). Junte linhas seguidas da mesma cor no mesmo dia em um unico compromisso. Se o horario nao estiver claro, estime e marque uncertain=true.',
  'BLOCOS COLORIDOS SAO OBRIGATORIOS: percorra dia por dia, da primeira ate a ultima hora da grade, e liste TODOS os blocos coloridos de cada dia como kind=evento, mesmo sem texto escrito (nesse caso title vazio e category = nome da cor na legenda). Nunca devolva so tarefas se a grade tem blocos coloridos. Cada dia da semana costuma ter varios blocos (por exemplo estagio todas as tardes de segunda a sexta).',
  'TITULO: se o bloco tem texto escrito a mao, use o texto em title e a categoria da cor em category. Sem texto: title vazio e category = nome da categoria da cor.',
  'TAREFAS: anotacoes sem horario (lista de tarefas ao pe do dia, caixas de marcar, destaques ou foco da semana) sao kind=tarefa, com day = o dia em que estao; destaque ou foco da semana sem dia: day = ultimo dia da semana. urgent=true so se estiver escrito entrega, prova, prazo, urgente ou com exclamacao.',
  'NAO inclua: blocos riscados ou rabiscados, linhas vazias, texto impresso da agenda (frases, calendario pequeno do mes). Se a letra for duvidosa, inclua o item com uncertain=true; se for ilegivel, nao inclua e descreva em notes (ex.: a quinta a tarde esta ilegivel).',
  'Responda somente o JSON do schema.'
];
const S = function (t) { return { type: t }; };
const N = function (t) { return { type: [t, 'null'] }; };
const itemProps = { day: S('string'), kind: { type: 'string', enum: ['evento', 'tarefa'] }, start: N('string'), end: N('string'), title: S('string'), category: N('string'), urgent: S('boolean'), uncertain: S('boolean') };
const legProps = { color: S('string'), category: S('string') };
const props = {
  week_start: N('string'),
  legend: { type: 'array', items: { type: 'object', properties: legProps, required: Object.keys(legProps), additionalProperties: false } },
  items: { type: 'array', items: { type: 'object', properties: itemProps, required: Object.keys(itemProps), additionalProperties: false } },
  notes: { type: 'array', items: S('string') }
};
const schema = { type: 'object', properties: props, required: Object.keys(props), additionalProperties: false };
let legenda = String(m.texto_atual || '').trim();
if (legenda.indexOf('Imagem enviada pelo usuario') === 0) { legenda = ''; }
const prompt = 'Leia a agenda de papel desta foto.' + (legenda ? NL + 'Mensagem da pessoa: ' + legenda : '');
return [{ json: { modelo: 'gpt-6.1-sol', instrucoes: regras.join(NL), prompt: prompt, schema_json: JSON.stringify(schema), image_url: m.image_url } }];"""

    NORMALIZAR = r"""const r = $input.first().json;
const a = $('Interpretar resposta').first().json;
let g = null;
try {
  const itens = r && Array.isArray(r.output) ? r.output : [];
  let txt = '';
  itens.forEach(function (o) {
    if (o && o.type === 'message' && Array.isArray(o.content)) {
      o.content.forEach(function (p) { if (p && p.text && typeof p.text === 'object') { g = p.text; } else if (p && p.text) { txt += p.text; } });
    }
  });
  if (!g) { g = JSON.parse(txt); }
} catch (e) { g = null; }
const dre = /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/;
const hre = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;
const lista = (g && Array.isArray(g.items)) ? g.items : [];
const itens2 = [];
lista.slice(0, 80).forEach(function (it) {
  if (!it || !dre.test(String(it.day || ''))) { return; }
  const cat = String(it.category || '').trim();
  const t = String(it.title || '').trim();
  let label = t;
  if (cat && t && it.kind !== 'tarefa') { label = (t.toLowerCase().indexOf(cat.toLowerCase()) === 0) ? t : cat + ' · ' + t; }
  else if (cat && it.kind !== 'tarefa') { label = cat; }
  let kind = it.kind === 'tarefa' ? 'task' : 'event';
  let st = hre.test(String(it.start || '')) ? String(it.start) : '';
  let en = hre.test(String(it.end || '')) ? String(it.end) : '';
  let duvida = it.uncertain === true;
  if (kind === 'event' && !st) { kind = 'task'; duvida = true; }
  if (kind === 'event' && (!en || en <= st)) {
    const h = parseInt(st.slice(0, 2), 10) + 1;
    en = h > 23 ? '23:59' : (h < 10 ? '0' : '') + h + st.slice(2);
    duvida = true;
  }
  if (kind === 'task' && !t) { return; }
  itens2.push({ day: String(it.day), kind: kind, start: st, end: en, title: label || 'Compromisso', urgent: it.urgent === true, uncertain: duvida });
});
const notas = (g && Array.isArray(g.notes)) ? g.notes.map(function (n) { return String(n).slice(0, 160); }).slice(0, 6) : [];
const x = { week_start: (g && dre.test(String(g.week_start || ''))) ? g.week_start : null, items: itens2, notes: notas };
return [{ json: { user_id: a.user_id, x: JSON.stringify(x) } }];"""

    PREPARAR_CONCLUSAO = r"""const r = $input.first().json || {};
let id = r.draft_id;
if (!id) { try { id = $('Executar botao').first().json.r.imp.draft_id; } catch (e) { id = null; } }
if (!id) { try { id = $('Importar agenda: editar').first().json.r.imp.draft_id; } catch (e) { id = null; } }
let res = { events_ok: 0, events_fail: 0, tasks_ok: 0, tasks_fail: 0, errors: ['falha ao falar com o Google'] };
if (typeof r.events_ok === 'number') {
  res = { events_ok: r.events_ok, events_fail: r.events_fail || 0, tasks_ok: r.tasks_ok || 0, tasks_fail: r.tasks_fail || 0, errors: Array.isArray(r.errors) ? r.errors : [] };
}
return [{ json: { draft_id: id ? Number(id) : 0, res: JSON.stringify(res) } }];"""

    RESPOSTA = r"""const r = $input.first().json.r || {};
const u = $('Normalizar update').first().json;
return [{ json: { chat_id: u.chat_id, text: r.text || 'Ok.', kb: r.kb || 'none', rid: r.rid || 0, state: '' } }];"""

    nodes.append(code_node(PFX + 'montar pedido', MONTAR, [4480, 6000]))
    # OpenAI nativo: copia do no de foto com as referencias trocadas
    import copy as _copy
    _foto = _copy.deepcopy(byname['OpenAI interpreta foto'])
    _foto['name'] = PFX + 'ler foto'
    _foto['position'] = [4704, 6000]
    _fj = json.dumps(_foto['parameters'], ensure_ascii=False).replace("$('" + NEW + "').first().json.", MPI)
    _foto['parameters'] = json.loads(_fj)
    _foto['parameters']['responses']['values'][1]['imageDetail'] = 'high'
    _foto['parameters']['options']['maxTokens'] = 6000
    _foto['parameters']['options']['textFormat']['textOptions']['name'] = 'agenda'
    _foto['onError'] = 'continueRegularOutput'
    nodes.append(_foto)
    # aviso imediato (so neste ramo): a leitura da foto leva ~1 min; falha de envio nao impede a leitura
    nodes.append({"name": PFX + "avisar", "type": "n8n-nodes-base.telegram", "typeVersion": 1.2, "position": [4592, 6000],
      "onError": "continueRegularOutput",
      "parameters": {"resource": "message", "operation": "sendMessage",
        "chatId": "={{ $('Normalizar update').first().json.chat_id }}",
        "text": "Estou lendo sua agenda, isso leva cerca de 1 minuto.",
        "additionalFields": {"appendAttribution": False}}})
    nodes.append(code_node(PFX + 'normalizar', NORMALIZAR, [4928, 6000]))
    nodes.append(pg_node(PFX + 'rascunho', 'SELECT agente.f_agimp_create($1::bigint, $2::jsonb) AS r',
      "={{ [ $json.user_id, $json.x ] }}", [5152, 6000]))
    nodes.append(pg_node(PFX + 'editar', 'SELECT agente.f_agimp_edit($1::bigint, $2::jsonb) AS r',
      "={{ [ " + "$('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.imp_json" + " ] }}", [4480, 6200]))
    _if_expr = "={{ !!($json.r && $json.r.imp) }}"
    def _if_node(name, pos):
        return {"name": name, "type": "n8n-nodes-base.if", "typeVersion": 2.2, "position": pos,
          "parameters": {"conditions": {"options": {"caseSensitive": True, "leftValue": "", "typeValidation": "strict", "version": 2},
            "conditions": [{"leftValue": _if_expr, "operator": {"type": "boolean", "operation": "true", "singleValue": True}, "rightValue": ""}], "combinator": "and"}}}
    nodes.append(_if_node(PFX + 'criar em massa?', [4704, 6200]))
    nodes.append(_if_node(PFX + 'botao em massa?', [4480, 6400]))
    _ex = exec_wf(PFX + 'executar', IMPORTAR_WF_ID,
      {"draft_id": "={{ String($json.r.imp.draft_id) }}", "calendar_key": "={{ $json.r.imp.calendar_key }}",
       "eventos": "={{ JSON.stringify($json.r.imp.events) }}", "tarefas": "={{ JSON.stringify($json.r.imp.tasks) }}"}, [4928, 6300])
    _ex['onError'] = 'continueRegularOutput'
    nodes.append(_ex)
    nodes.append(code_node(PFX + 'preparar conclusao', PREPARAR_CONCLUSAO, [5152, 6300]))
    nodes.append(pg_node(PFX + 'concluir', 'SELECT agente.f_agimp_done($1::bigint, $2::bigint, $3::jsonb) AS r',
      "={{ [ $('Buscar usuario').first().json.id, $json.draft_id, $json.res ] }}", [5376, 6300]))
    nodes.append(code_node(PFX + 'resposta', RESPOSTA, [5600, 6150]))
    _refresh()

    def _outs(name, *dests):
        conns[name] = {'main': [[{'node': d, 'type': 'main', 'index': 0} for d in ds] for ds in dests]}
    setc(PFX + 'montar pedido', [PFX + 'avisar'])
    setc(PFX + 'avisar', [PFX + 'ler foto'])
    setc(PFX + 'ler foto', [PFX + 'normalizar'])
    setc(PFX + 'normalizar', [PFX + 'rascunho'])
    setc(PFX + 'rascunho', [PFX + 'resposta'])
    setc(PFX + 'editar', [PFX + 'criar em massa?'])
    _outs(PFX + 'criar em massa?', [PFX + 'executar'], [PFX + 'resposta'])
    _outs(PFX + 'botao em massa?', [PFX + 'executar'], ['Agenda: acao externa?'])
    setc(PFX + 'executar', [PFX + 'preparar conclusao'])
    setc(PFX + 'preparar conclusao', [PFX + 'concluir'])
    setc(PFX + 'concluir', [PFX + 'resposta'])
    setc(PFX + 'resposta', ['Preparar envio'])
    # o clique de botao passa primeiro pelo If de importacao em massa
    setc('Executar botao', [PFX + 'botao em massa?'])
    # teclado: Criar tudo / Cancelar (rid = id do rascunho)
    add_kb('agimp', [('Criar tudo', 'aiok:{rid}'), ('Cancelar', 'aino:{rid}')])
    _refresh()


INTENT = Intent(
    name='agenda_import',
    also=['agenda_import_edit'],
    hint='agenda_import (foto de agenda de papel com varios compromissos), agenda_import_edit (corrigir, tirar ou confirmar a importacao de agenda em aberto)',
    rules=[AGENDA_RULE],
    interpret_js=INTERPRET,
    edits=[
        Edit('Montar pedido a IA', 'jsCode', "research_query: NN('string')\n};",
        "research_query: NN('string'),\n  imp_action: { type: ['string', 'null'], enum: ['edit', 'remove', 'confirm', 'cancel', null] }, imp_n: NN('integer'), imp_end: NN('string')\n};")],
    route=('agenda importar', 'Importar agenda: montar pedido'),
    routes=[('agenda importar corrigir', 'agenda_import_edit', 'Importar agenda: editar')],
    build=build,
)
