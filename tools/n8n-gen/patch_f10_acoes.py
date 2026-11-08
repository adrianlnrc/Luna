# ---------- F10 / Etapa 1 da secretaria natural (spec-secretaria-natural.md) ----------
# (a) varias acoes numa mensagem executadas todas + resposta consolidada + "Desfazer tudo"
# (b) pedido em parte possivel (regra 48 reescrita: faz o que da, diz o que nao faz, oferece convidar em compromisso social)
# (c) correcao por texto de acoes recentes (tabela de acoes recentes, uso do reply do Telegram, busca por nome para o antigo)
# Depende de db/033_acoes_recentes.sql (APLICAR ANTES de enviar o workflow: a query do "Buscar usuario" chama f_recent_actions_txt).
# Entra em gen.py DEPOIS de patch_f8_agenda_import.py e ANTES de patch_zz_compact.py.
#
# ANCORAS ALTERADAS (todas via rep, uma ocorrencia):
#   [Normalizar update]   "return [{ json: { update_id: ..."             -> campo reply_text (mensagem respondida pelo usuario)
#   [Buscar usuario]      "agente.f_ai_groups(u.id) AS groups_txt"        -> recent_txt = agente.f_recent_actions_txt(u.id)
#   [Montar pedido a IA]  enum de intents, fim do schema, rule INTENTS, regras 42 (VARIOS PEDIDOS) e 48 (FORA DO ESCOPO) trocadas,
#                         regra nova CORRECAO DE ACAO RECENTE, prompt (ACOES RECENTES + RESPONDIDA antes da mensagem atual)
#   [Interpretar resposta] "if (out.intent === 'finance') {"             -> corr_json do intent correct_recent
#   [Preparar envio]      codigo todo: consolidacao "Feito:", Desfazer tudo, unsupported_note, "Quer chamar alguem?"
#   Conexoes: Restaurar interpretacao -> Lote: abrir -> Multi: preparar -> Multi: tem extras? -> (true: cadeia Multi) / (false e Multi: consolidar) -> Roteador
#             Executar botao -> Lote: desfazer Google? -> (true: cadeia Lote) / (false) -> Importar agenda: botao em massa?
# MUDANCAS DE SCHEMA DA IA: intent += correct_recent; campos novos recent_id, unsupported_note, social_event, more_actions (array de objetos).
# NOS NOVOS: prefixos 'Lote: ', 'Multi: ', 'Correcao: '; teclado 'multi_undo' (botao "Desfazer tudo", callback mu:<lote>).
# Sub-workflows usados (ids ja existentes): Agenda Adrian bBJo78YVQ1cOMX09, Agenda Maria 6bXuicjujajBuXbd, Tarefas dnVm8cfVhpqXGWmr.
_refresh()
AG_ADRIAN = 'bBJo78YVQ1cOMX09'
AG_MARIA = '6bXuicjujajBuXbd'
TAREFAS_WF = 'dnVm8cfVhpqXGWmr'


def _if_node(name, expr, pos):
    return {"name": name, "type": "n8n-nodes-base.if", "typeVersion": 2.3, "position": pos, "parameters": {"conditions": {
        "options": {"caseSensitive": True, "leftValue": "", "typeValidation": "strict", "version": 2},
        "conditions": [{"leftValue": expr, "operator": {"type": "boolean", "operation": "true", "singleValue": True}, "rightValue": ""}],
        "combinator": "and"}}}


def _swap_rule(mp, start, new):
    """Troca uma regra estatica inteira (linha '  'START...',') por outra."""
    key = "  '" + start
    assert mp.count(key) == 1, start
    i = mp.index(key)
    j = mp.index("\n", i)
    assert mp[i:j].rstrip().endswith("',"), start
    return mp[:i] + "  '" + new + "'," + mp[j:]


def _safe(s):
    assert "'" not in s and '`' not in s and '\\' not in s and '${' not in s, s[:60]
    return s


# =====================================================================================================
# 1) Intencao correct_recent (registro: intents/correct_recent.py): enum, hint, recent_id, regra CORRECAO DE ACAO RECENTE,
#    contexto ACOES RECENTES/RESPONDIDA do prompt, corr_json, coluna recent_txt do Buscar usuario, reply_text do Normalizar update,
#    nos 'Correcao: executar/resposta' e rota. Aplicada ANTES do restante porque o schema do pedido multiplo vem depois de recent_id.
# =====================================================================================================
from intents import REGISTRY, schema_add
REGISTRY.apply('correct_recent', globals())

# =====================================================================================================
# 3) Montar pedido a IA: schema, regras e prompt
# =====================================================================================================
mp = byname[NEW]['parameters']['jsCode']
mp = schema_add(mp, """unsupported_note: NN('string'), social_event: NN('boolean'),
more_actions: { type: ['array', 'null'], items: { type: 'object', properties: {
kind: { type: 'string', enum: ['lembrete', 'compromisso', 'tarefa', 'gasto', 'nota', 'lista', 'tomei'] }, title: { type: 'string' },
date: NN('string'), time: NN('string'), duration_minutes: NN('integer'), lead_minutes: NN('integer'), location: NN('string'),
amount: NN('number'), list_name: NN('string'), items: { type: ['array', 'null'], items: { type: 'string' } } },
required: ['kind', 'title', 'date', 'time', 'duration_minutes', 'lead_minutes', 'location', 'amount', 'list_name', 'items'], additionalProperties: false } }""", sep=', ')

R_MULTI = _safe(
    "VARIOS PEDIDOS NA MESMA MENSAGEM: o sistema executa TODOS. O primeiro pedido (ou o destrutivo, se houver) vai nos campos normais (intent, title, date, time...). "
    "Os demais vao em more_actions, um item por pedido, com kind = lembrete (aviso de algo, com hora), compromisso (evento na agenda, com hora), tarefa (coisa a fazer, sem hora; date opcional), "
    "gasto (valor pago: title = o que foi, amount), nota (anotar uma informacao: title = o texto), lista (itens para uma lista de compras ou outra: items = os itens, list_name = nome da lista ou null) "
    "ou tomei (marcar remedio ou vitamina tomado: title = nome do item). Preencha date YYYY-MM-DD e time HH:MM como nos pedidos normais, lead_minutes se disse quanto antes avisar, location se citou; o que nao se aplica fica null. "
    "Se faltar a hora de um lembrete ou compromisso, ainda assim ponha o item em more_actions com time null: o sistema faz o resto e pergunta so dessa parte. "
    "Pedido destrutivo (apagar, cancelar, remover) NUNCA vai em more_actions: ele e o principal (o sistema pede confirmacao); havendo dois destrutivos, trate o primeiro e cite o outro em extra_requests. "
    "Pedido que o sistema nao sabe fazer (reservar mesa) tambem nao vai em more_actions: use unsupported_note. Pedido unico: more_actions=null. "
    "Varios gastos na mesma frase continuam em fin_items (regra VARIOS GASTOS); gasto junto com outro tipo de pedido vai em more_actions com kind=gasto. "
    "Exemplo: amanha tenho dentista as 9h, preciso comprar leite e paguei 50 de uber = principal create_event (dentista, amanha, 09:00); more_actions = [tarefa leite, gasto uber 50]. "
    "extra_requests so para o que realmente nao pode ser executado e nao cabe em unsupported_note.")
mp = _swap_rule(mp, "VARIOS PEDIDOS NA MESMA MENSAGEM:", R_MULTI)

R_PARTE = _safe(
    "PEDIDO EM PARTE POSSIVEL: quando o pedido mistura algo que voce faz com algo que nao faz (reservar mesa ou restaurante, reservar passagem ou hotel, comprar ou pedir algo), FACA o que da e diga com franqueza o resto. "
    "Exemplo: reserva uma mesa na pizzaria Fratello Uno de Aguas Claras as 18:00 e marca na minha agenda = create_event (title Pizzaria Fratello Uno, date, time 18:00, location = endereco salvo do lugar se houver, senao o nome e a regiao) "
    "e unsupported_note = Reservar eu nao consigo; posso te lembrar de ligar antes. "
    "Preencha unsupported_note com UMA frase curta dizendo o que NAO sera feito e, se fizer sentido, o que voce oferece no lugar (um lembrete de ligar); o sistema junta isso a resposta. "
    "NUNCA escreva em reply que reservou, pediu ou comprou, e NUNCA prometa algo que nao foi gravado. Quando nao ha parte possivel (so reservar, so comprar, so pedir algo), use intent=chat e reply de UMA frase: "
    "Isso eu ainda nao faco (reservar mesa). Se fizer sentido, acrescente: Posso te lembrar de ligar para reservar. Sem fazer perguntas antes de dizer que nao faz. "
    "COMPROMISSO SOCIAL (restaurante, jantar, almoco com alguem, aniversario, festa, churrasco, cinema, encontro): em create_event ponha social_event=true; o sistema oferece chamar alguem. Nos demais casos social_event=null. Se o usuario responder a esse Quer chamar alguem? com nomes, use create_event com o mesmo title, date, time e location do compromisso que voce acabou de criar e invitees = os nomes citados.")
mp = _swap_rule(mp, "FORA DO ESCOPO:", R_PARTE)

# reconcilia a regra SEM OS FIXOS (fase 9): foi editada so no Redis/rules.json, nao no patch_f8; sem isto o gerador a apagaria
FIXOS_RULE = _safe(" SEM OS FIXOS: se a lista traz a secao Blocos fixos e a pessoa diz sem os fixos, tira os fixos, nao quero os fixos ou nao precisa dos blocos fixos, "
                   "use agenda_import_edit com imp_action = remove, imp_n = null, title = fixos, date, time vazios. Se ela aceitar os fixos (quero os fixos, pode deixar os fixos) e so confirmar, use confirm.")
mp = rep(mp, "novo titulo (vazio se nao mudou). Preencha reply com texto vazio.',", "novo titulo (vazio se nao mudou). Preencha reply com texto vazio." + FIXOS_RULE + "',")

byname[NEW]['parameters']['jsCode'] = mp

# =====================================================================================================
# 6) Varias acoes numa mensagem: cadeia entre "Restaurar interpretacao" e o Roteador
# =====================================================================================================
_SAFE = {"onError": "continueRegularOutput"}
lote = pg_node('Lote: abrir', "SELECT agente.f_batch_open($1::bigint) AS batch", "={{ [ $json.user_id ] }}", [2200, 5200])
lote.update(_SAFE)

PREPARAR = r"""const a = $('Interpretar resposta').first().json;
let batch = 0;
try { batch = Number($input.first().json.batch) || 0; } catch (e) { batch = 0; }
const tz = a.tz || 'America/Sao_Paulo';
const now = DateTime.now().setZone(tz);
const okDate = /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/;
const okTime = /^[0-9]{1,2}:[0-9]{2}$/;
const lista = Array.isArray(a.more_actions) ? a.more_actions.slice(0, 6) : [];
const db = []; const ev = []; const tk = []; const ask = [];
const q = function (s) { return '"' + s + '"'; };
lista.forEach(function (m) {
  if (!m || typeof m !== 'object') { return; }
  const kind = String(m.kind || '');
  const title = String(m.title || '').trim();
  if (kind === 'lista') {
    let its = Array.isArray(m.items) ? m.items.map(function (x) { return String(x || '').trim(); }).filter(function (x) { return x !== ''; }) : [];
    if (!its.length && title) { its = [title]; }
    if (!its.length) { return; }
    db.push({ kind: 'list', title: its.join(', '), list_name: m.list_name ? String(m.list_name) : '', items: its });
    return;
  }
  if (!title) { return; }
  if (kind === 'nota') { db.push({ kind: 'note', title: title }); return; }
  if (kind === 'tomei') { db.push({ kind: 'supply', title: title }); return; }
  if (kind === 'gasto') {
    const amt = Number(m.amount);
    if (!(amt > 0)) { ask.push('o valor de ' + q(title)); return; }
    db.push({ kind: 'expense', title: title, amount: amt });
    return;
  }
  if (kind === 'tarefa') {
    tk.push({ title: title, due: (m.date && okDate.test(String(m.date))) ? String(m.date) : '', calendar_key: a.calendar_key || '' });
    return;
  }
  if (kind === 'lembrete' || kind === 'compromisso') {
    const tm0 = (m.time && okTime.test(String(m.time))) ? String(m.time) : '';
    if (!tm0) { ask.push('a hora de ' + q(title)); return; }
    const hhmm = tm0.length === 4 ? '0' + tm0 : tm0;
    let d = (m.date && okDate.test(String(m.date))) ? String(m.date) : '';
    if (!d) {
      const t0 = DateTime.fromISO(now.toFormat('yyyy-MM-dd') + 'T' + hhmm, { zone: tz });
      d = (t0 > now ? t0 : t0.plus({ days: 1 })).toFormat('yyyy-MM-dd');
    }
    const due = DateTime.fromISO(d + 'T' + hhmm, { zone: tz });
    if (!due.isValid || due <= now) { ask.push('a data de ' + q(title)); return; }
    const lead = (typeof m.lead_minutes === 'number' && m.lead_minutes >= 0) ? String(m.lead_minutes) : '';
    if (kind === 'lembrete') {
      db.push({ kind: 'reminder', title: title, due_iso: due.toISO(), lead: lead });
    } else {
      const dur = (typeof m.duration_minutes === 'number' && m.duration_minutes > 0) ? m.duration_minutes : 60;
      ev.push({ title: title, due_iso: due.toISO(), end_iso: due.plus({ minutes: dur }).toISO(), location: m.location ? String(m.location) : '', lead_str: lead, calendar_key: a.calendar_key || '' });
    }
  }
});
return [{ json: Object.assign({}, a, { batch_id: batch, multi_db: db, multi_ev: ev, multi_tk: tk, multi_ask: ask, multi_n: db.length + ev.length + tk.length + ask.length }) }];"""

_MP = "$('Multi: preparar').first().json."
nodes += [
    lote,
    code_node('Multi: preparar', PREPARAR, [2450, 5200]),
    _if_node('Multi: tem extras?', "={{ $json.multi_n > 0 }}", [2700, 5200]),
    pg_node('Multi: banco', "SELECT agente.f_multi_db($1::bigint,$2::jsonb) AS r",
            "={{ [ " + _MP + "user_id, JSON.stringify(" + _MP + "multi_db || []) ] }}", [2950, 5100]),
    _if_node('Multi: tem compromissos?', "={{ (" + _MP + "multi_ev || []).length > 0 }}", [3200, 5100]),
    code_node('Multi: expandir compromissos', "return ($('Multi: preparar').first().json.multi_ev || []).map(function (x) { return { json: x }; });", [3450, 5000]),
    switch_cal('Multi: qual calendario', [3700, 5000]),
    exec_wf('Multi: Agenda Adrian', AG_ADRIAN, {
        "action": "create", "summary": "={{ $json.title }}", "start": "={{ $json.due_iso }}", "end": "={{ $json.end_iso }}",
        "location": "={{ $json.location || '' }}", "attendees": "", "send_updates": "all", "force": "false", "meet": "false",
        "repeat_freq": "", "repeat_until": "", "repeat_count": ""}, [3950, 4900]),
    exec_wf('Multi: Agenda Maria Clara', AG_MARIA, {
        "action": "create", "summary": "={{ $json.title }}", "start": "={{ $json.due_iso }}", "end": "={{ $json.end_iso }}",
        "location": "={{ $json.location || '' }}", "attendees": "", "send_updates": "all", "force": "false", "meet": "false",
        "repeat_freq": "", "repeat_until": "", "repeat_count": ""}, [3950, 5060]),
    code_node('Multi: sem calendario', "return $input.all().map(function () { return { json: { ok: false, error: 'agenda nao conectada' } }; });", [3950, 5220]),
    code_node('Multi: concluir compromissos', r"""const base = $('Multi: expandir compromissos').all();
const outs = $input.all();
const p = $('Multi: preparar').first().json;
const items = base.map(function (b, i) {
  const x = b.json;
  const o = (outs[i] && outs[i].json) ? outs[i].json : { error: 'sem resposta' };
  let res = o;
  if (o.ok !== true && o.ok !== false) { res = { ok: false, error: String((o.error && o.error.message) ? o.error.message : (o.error || 'sem resposta')).slice(0, 120) }; }
  return { req: { title: x.title, due_iso: x.due_iso, end_iso: x.end_iso, location: x.location || '', lead_str: x.lead_str || '', source: 'text', calendar_key: x.calendar_key || '',
    repeat_freq: '', repeat_until: '', repeat_count: '', attendees: '', meet: 'false' }, result: res };
});
return [{ json: { user_id: p.user_id, items_json: JSON.stringify(items) } }];""", [4200, 5000]),
    pg_node('Multi: compromissos no banco', "SELECT agente.f_multi_events($1::bigint,$2::jsonb) AS r", "={{ [ $json.user_id, $json.items_json ] }}", [4450, 5000]),
    _if_node('Multi: tem tarefas?', "={{ (" + _MP + "multi_tk || []).length > 0 }}", [4700, 5100]),
    code_node('Multi: expandir tarefas', "return ($('Multi: preparar').first().json.multi_tk || []).map(function (x) { return { json: x }; });", [4950, 5200]),
    exec_wf('Multi: Google Tarefas', TAREFAS_WF, {
        "calendar_key": "={{ $json.calendar_key }}", "action": "add", "title": "={{ $json.title }}", "due": "={{ $json.due }}"}, [5200, 5200]),
    code_node('Multi: concluir tarefas', r"""const base = $('Multi: expandir tarefas').all();
const outs = $input.all();
const p = $('Multi: preparar').first().json;
const items = base.map(function (b, i) {
  const x = b.json;
  const o = (outs[i] && outs[i].json) ? outs[i].json : {};
  return { title: x.title, due: x.due || '', calendar_key: x.calendar_key || '', result: o };
});
return [{ json: { user_id: p.user_id, items_json: JSON.stringify(items) } }];""", [5450, 5200]),
    pg_node('Multi: tarefas no banco', "SELECT agente.f_multi_tasks($1::bigint,$2::jsonb) AS r", "={{ [ $json.user_id, $json.items_json ] }}", [5700, 5200]),
    code_node('Multi: consolidar', r"""const p = $('Multi: preparar').first().json;
const lines = []; const fails = [];
['Multi: banco', 'Multi: compromissos no banco', 'Multi: tarefas no banco'].forEach(function (nm) {
  try {
    const r = $(nm).first().json.r;
    if (r) {
      (Array.isArray(r.lines) ? r.lines : []).forEach(function (x) { lines.push(String(x)); });
      (Array.isArray(r.fails) ? r.fails : []).forEach(function (x) { fails.push(String(x)); });
    }
  } catch (e) {}
});
return [{ json: Object.assign({}, p, { multi_lines: lines, multi_fails: fails }) }];""", [5950, 5200]),
]
for _n in nodes:
    if _n['name'].startswith('Multi: ') and _n['type'] in ('n8n-nodes-base.postgres', 'n8n-nodes-base.executeWorkflow'):
        _n.update(_SAFE)
        if _n['type'] == 'n8n-nodes-base.executeWorkflow':
            _n['parameters']['mode'] = 'each'
_refresh()

# ligacoes
setc('Restaurar interpretacao', ['Lote: abrir'])
setc('Lote: abrir', ['Multi: preparar'])
setc('Multi: preparar', ['Multi: tem extras?'])
conns['Multi: tem extras?'] = {'main': [[{'node': 'Multi: banco', 'type': 'main', 'index': 0}], [{'node': 'Roteador de intencao', 'type': 'main', 'index': 0}]]}
setc('Multi: banco', ['Multi: tem compromissos?'])
conns['Multi: tem compromissos?'] = {'main': [[{'node': 'Multi: expandir compromissos', 'type': 'main', 'index': 0}], [{'node': 'Multi: tem tarefas?', 'type': 'main', 'index': 0}]]}
setc('Multi: expandir compromissos', ['Multi: qual calendario'])
conns['Multi: qual calendario'] = {'main': [[{'node': 'Multi: Agenda Adrian', 'type': 'main', 'index': 0}], [{'node': 'Multi: Agenda Maria Clara', 'type': 'main', 'index': 0}], [{'node': 'Multi: sem calendario', 'type': 'main', 'index': 0}]]}
setc('Multi: Agenda Adrian', ['Multi: concluir compromissos'])
setc('Multi: Agenda Maria Clara', ['Multi: concluir compromissos'])
setc('Multi: sem calendario', ['Multi: concluir compromissos'])
setc('Multi: concluir compromissos', ['Multi: compromissos no banco'])
setc('Multi: compromissos no banco', ['Multi: tem tarefas?'])
conns['Multi: tem tarefas?'] = {'main': [[{'node': 'Multi: expandir tarefas', 'type': 'main', 'index': 0}], [{'node': 'Multi: consolidar', 'type': 'main', 'index': 0}]]}
setc('Multi: expandir tarefas', ['Multi: Google Tarefas'])
setc('Multi: Google Tarefas', ['Multi: concluir tarefas'])
setc('Multi: concluir tarefas', ['Multi: tarefas no banco'])
setc('Multi: tarefas no banco', ['Multi: consolidar'])
setc('Multi: consolidar', ['Roteador de intencao'])

# =====================================================================================================
# 7) Desfazer tudo: teclado e cadeia no caminho dos botoes
# =====================================================================================================
add_kb('multi_undo', [('Desfazer tudo', 'mu:{rid}')])
_refresh()
_p = byname['Enviar com multi undo']['parameters']
_p['text'] = "={{ $('Preparar envio').first().json.html }}"
_p['additionalFields']['parse_mode'] = 'HTML'

_ER = "$('Executar botao').first().json.r"
nodes += [
    _if_node('Lote: desfazer Google?', "={{ !!($json.r && Array.isArray($json.r.cals) && $json.r.cals.length > 0) }}", [1000, 5400]),
    code_node('Lote: expandir exclusoes', "return (($('Executar botao').first().json.r || {}).cals || []).map(function (c) { return { json: c }; });", [1250, 5300]),
    switch_cal('Lote: qual calendario', [1500, 5300]),
    exec_wf('Lote: Agenda Adrian', AG_ADRIAN, {
        "action": "delete", "summary": "", "start": "", "end": "", "location": "", "attendees": "", "event_id": "={{ $json.event_id }}",
        "send_updates": "none", "force": "", "meet": "", "repeat_freq": "", "repeat_until": "", "repeat_count": "", "response": ""}, [1750, 5200]),
    exec_wf('Lote: Agenda Maria Clara', AG_MARIA, {
        "action": "delete", "summary": "", "start": "", "end": "", "location": "", "attendees": "", "event_id": "={{ $json.event_id }}",
        "send_updates": "none", "force": "", "meet": "", "repeat_freq": "", "repeat_until": "", "repeat_count": "", "response": ""}, [1750, 5360]),
    code_node('Lote: sem calendario', "return $input.all().map(function () { return { json: { ok: false, error: 'agenda nao conectada' } }; });", [1750, 5520]),
    code_node('Lote: concluir desfazer', r"""const u = $('Normalizar update').first().json;
const r = $('Executar botao').first().json.r || {};
const cals = Array.isArray(r.cals) ? r.cals : [];
const outs = $input.all();
const NL = String.fromCharCode(10);
const falhas = [];
cals.forEach(function (c, i) {
  const o = (outs[i] && outs[i].json) ? outs[i].json : {};
  if (o.ok !== true) { falhas.push('- ' + String(c.title || 'compromisso').slice(0, 60)); }
});
let text = String(r.text || 'Desfeito.');
if (falhas.length) { text += NL + NL + 'Não consegui apagar estes compromissos do Google (apague na agenda se quiser):' + NL + falhas.join(NL); }
return [{ json: { chat_id: u.chat_id, text: text, kb: 'none', rid: 0, state: '' } }];""", [2000, 5300]),
]
for _n in nodes:
    if _n['name'].startswith('Lote: ') and _n['type'] == 'n8n-nodes-base.executeWorkflow':
        _n.update(_SAFE)
        _n['parameters']['mode'] = 'each'
_refresh()
setc('Executar botao', ['Lote: desfazer Google?'])
conns['Lote: desfazer Google?'] = {'main': [[{'node': 'Lote: expandir exclusoes', 'type': 'main', 'index': 0}], [{'node': 'Importar agenda: botao em massa?', 'type': 'main', 'index': 0}]]}
setc('Lote: expandir exclusoes', ['Lote: qual calendario'])
conns['Lote: qual calendario'] = {'main': [[{'node': 'Lote: Agenda Adrian', 'type': 'main', 'index': 0}], [{'node': 'Lote: Agenda Maria Clara', 'type': 'main', 'index': 0}], [{'node': 'Lote: sem calendario', 'type': 'main', 'index': 0}]]}
setc('Lote: Agenda Adrian', ['Lote: concluir desfazer'])
setc('Lote: Agenda Maria Clara', ['Lote: concluir desfazer'])
setc('Lote: sem calendario', ['Lote: concluir desfazer'])
setc('Lote: concluir desfazer', ['Preparar envio'])

# =====================================================================================================
# 8) Preparar envio: consolidacao, Desfazer tudo, parte nao feita, convite social
# =====================================================================================================
byname['Preparar envio']['parameters']['jsCode'] = r"""const r = $input.first().json;
const NL = String.fromCharCode(10);
let text = String(r.text || 'Ok.');
if (text.length > 3900) { text = text.slice(0, 3900) + '...'; }
let kb = r.kb || 'none';
let rid = r.rid || 0;
let state = r.state || '';
let ia = {};
try { ia = $('Interpretar resposta').first().json || {}; } catch (e) { ia = {}; }
let mu = null;
try { mu = $('Multi: consolidar').first().json; } catch (e) { mu = null; }
const lines = (mu && Array.isArray(mu.multi_lines)) ? mu.multi_lines : [];
const fails = (mu && Array.isArray(mu.multi_fails)) ? mu.multi_fails : [];
const asks = (mu && Array.isArray(mu.multi_ask)) ? mu.multi_ask : [];
if (lines.length || fails.length || asks.length) {
  const mainOk = kb === 'none' && text.indexOf('?') < 0 && text.length <= 200 && ia.intent !== 'clarify' && ia.intent !== 'chat';
  const bul = [];
  if (mainOk && lines.length) { bul.push(text.split(NL).join(' ')); }
  lines.forEach(function (l) { bul.push(l); });
  let out = '';
  if (bul.length) { out = 'Feito:' + NL + bul.map(function (l) { return '- ' + l; }).join(NL); }
  if (!(mainOk && lines.length)) { out = (out ? out + NL + NL : '') + text; }
  if (fails.length) { out += NL + NL + fails.join(NL); }
  if (asks.length) { out += NL + NL + 'Faltou saber ' + asks.join(' e ') + '. Me diz que eu faço.'; }
  text = out;
  if (asks.length && !state && kb === 'none') {
    state = JSON.stringify({ kind: 'clarify', original: 'Falta so ' + asks.join(' e ') + ' (o resto do pedido anterior JA foi feito: nao repita nada, crie apenas o que faltava)' });
  }
  if (lines.length && kb === 'none' && mu && Number(mu.batch_id) > 0) { kb = 'multi_undo'; rid = Number(mu.batch_id); }
}
const un = String(ia.unsupported_note || '').trim();
if (un.length > 2 && ia.intent !== 'chat' && ia.intent !== 'clarify' && text.indexOf(un) < 0) { text = text + NL + NL + un; }
if (ia.social_event === true && ia.intent === 'create_event' && kb === 'none' && text.indexOf('?') < 0) { text = text + NL + 'Quer chamar alguém?'; }
let extra = '';
try { extra = String($('Interpretar resposta').first().json.extra_requests || '').trim(); } catch (e) { extra = ''; }
while (extra.length && '.!, '.indexOf(extra.charAt(extra.length - 1)) >= 0) { extra = extra.slice(0, -1); }
if (extra.length > 2 && ['null', 'nenhum', 'nenhuma', 'nada', 'none'].indexOf(extra.toLowerCase()) < 0) {
text = text + NL + NL + 'Também vi: ' + extra + '. Me manda isso separado que eu faço.';
}
const html = text.split('**').join('').split('&').join('&amp;').split('<').join('&lt;').split('>').join('&gt;');
return [{ json: { chat_id: r.chat_id, text: text, html: html, kb: kb, rid: rid, state: state } }];"""

byname = _refresh()
