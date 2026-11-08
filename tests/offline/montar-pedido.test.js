'use strict';
// Montar pedido a IA / Importar agenda / Docs / Preparar PDF
const test = require('node:test');
const assert = require('node:assert/strict');
const { rodar1, runCodeNode, WF, NL, AGORA } = require('./helpers');
const { runCodeNodeAsync } = require('../../tools/n8n-gen/nodetest');

const pedido = function (o) {
  o = o || {};
  const nos = {
    'Ler configuracao do modelo': [{ modelo: o.modelo }],
    'Normalizar update': [Object.assign({ chat_id: 111, kind: 'text', text: 'oi' }, o.u)],
    'Buscar usuario': [Object.assign({ id: 7, name: 'Adrian', timezone: 'America/Sao_Paulo' }, o.user)],
  };
  if (o.state) { nos['Ler estado da conversa'] = [{ state: JSON.stringify(o.state) }]; }
  if (o.hist) { nos['Ler historico da conversa'] = [{ hist: JSON.stringify(o.hist) }]; }
  if (o.regras) { nos['Ler regras'] = [{ regras: JSON.stringify(o.regras) }]; }
  return rodar1('Montar pedido a IA', { entrada: [o.entrada || {}], nos: nos, agora: AGORA });
};

test('Montar pedido a IA: modelo padrao, config simples ou JSON, ignorando nao-gpt', () => {
  assert.equal(pedido().modelo, 'gpt-6-luna');
  assert.equal(pedido({ modelo: 'gpt-9' }).modelo, 'gpt-9');
  assert.equal(pedido({ modelo: '{"modelo":"gpt-7"}' }).modelo, 'gpt-7');
  assert.equal(pedido({ modelo: '{"modelo":"claude"}' }).modelo, 'gpt-6-luna');
  assert.equal(pedido({ modelo: 'outro' }).modelo, 'gpt-6-luna');
});

test('Montar pedido a IA: instrucoes tem data de agora, fuso, usuario, regras e categorias', () => {
  const o = pedido({ user: { nickname: 'Dri', supply_items: 'Losartana', places_txt: 'Casa = Rua A', no_emoji: true }, regras: ['REGRA-ESTATICA-1'] });
  assert.match(o.instrucoes, /assistente pessoal de Dri/);
  assert.match(o.instrucoes, /Agora: 2026-11-08 12:00 \(domingo\), fuso America\/Sao_Paulo/);
  assert.match(o.instrucoes, /estoque\/remedio ja cadastrados deste usuario: Losartana/);
  assert.match(o.instrucoes, /NUNCA use emoji/); assert.match(o.instrucoes, /Casa = Rua A/);
  assert.match(o.instrucoes, /REGRA-ESTATICA-1/); assert.match(o.instrucoes, /Categorias deste usuario: Alimentação, Mercado/);
  assert.match(pedido().instrucoes, /use intent=clarify\. Responda sempre no schema/); // regra padrao sem 'Ler regras'
});

test('Montar pedido a IA: estados clarify e snooze acrescentam contexto', () => {
  assert.match(pedido({ state: { kind: 'clarify', original: 'reuniao sexta' } }).instrucoes, /mensagem anterior do usuario estava incompleta: reuniao sexta/);
  assert.match(pedido({ state: { kind: 'snooze' } }).instrucoes, /adiar um lembrete/);
  assert.doesNotMatch(pedido().instrucoes, /CONTEXTO:/);
});

test('Montar pedido a IA: prompt tem historico (comeca no user), mensagem atual e ofertas validas', () => {
  const T = Date.parse(AGORA);
  const o = pedido({
    u: { text: 'sim', reply_text: 'Quer salvar?' }, user: { recent_txt: 'lembrete X', mem_txt: 'MEMORIA: gosta de cafe' },
    hist: [{ r: 'model', t: 'orfa', ts: T - 1000 }, { r: 'user', t: 'oi', ts: T - 1000 }, { r: 'model', t: 'ola', ts: T - 900 }, { r: 'user', t: 'velho', ts: T - 9 * 3600000 }],
    state: { kind: 'offer', pessoa: 'Maria', ts: T - 1000 },
  });
  assert.ok(o.prompt.startsWith('CONVERSA RECENTE (mais antiga primeiro):' + NL + 'Usuario: oi' + NL + 'Assistente: ola'));
  assert.doesNotMatch(o.prompt, /orfa|velho/); assert.equal(o.history_size, 2);
  assert.match(o.prompt, /ACOES RECENTES[^]*lembrete X/); assert.match(o.prompt, /RESPONDIDA[^]*Quer salvar\?/);
  assert.match(o.prompt, /MEMORIA: gosta de cafe/); assert.match(o.prompt, /OFERTA PENDENTE \(voce perguntou se salva a pessoa Maria\)/);
  assert.ok(o.prompt.endsWith('MENSAGEM ATUAL DO USUARIO:' + NL + 'sim'));
  const velha = pedido({ state: { kind: 'offer', ts: T - 16 * 60000 } });
  assert.doesNotMatch(velha.prompt, /OFERTA PENDENTE/);
});

test('Montar pedido a IA: foto, PDF, imagem como documento e audio ajustam midia e flags', () => {
  let o = pedido({ u: { kind: 'photo', text: '' }, entrada: { audio_b64: 'QUJD' } });
  assert.equal(o.via_photo, true); assert.equal(o.image_url, 'data:image/jpeg;base64,QUJD'); assert.equal(o.texto_atual, 'Imagem enviada pelo usuario, sem legenda.');
  assert.match(o.prompt, /Uma imagem esta anexada/);
  o = pedido({ u: { kind: 'document', mime: 'application/pdf', file_name: 'a.pdf', text: '' }, entrada: { audio_b64: 'QUJD' } });
  assert.deepEqual([o.via_pdf, o.via_photo, o.image_url, o.file_b64, o.file_name], [true, false, '', 'QUJD', 'a.pdf']);
  assert.match(o.prompt, /Um arquivo PDF chamado a\.pdf/);
  o = pedido({ u: { kind: 'document', mime: 'image/png', text: 'x' }, entrada: { audio_b64: 'QUJD' } });
  assert.equal(o.via_photo, true); assert.equal(o.image_url, 'data:image/png;base64,QUJD');
  o = pedido({ u: { kind: 'voice' }, entrada: { text: '  tomei agua ' } });
  assert.equal(o.via_audio, true); assert.equal(o.texto_atual, 'tomei agua'); assert.match(o.prompt, /\(transcricao de audio\):/);
  assert.equal(pedido({ u: { kind: 'photo' } }).via_photo, false); // sem midia baixada
});

// schema estrito da OpenAI: required == todas as chaves, additionalProperties false, nulos declarados com 'null'
function validarEstrito(s, caminho, erros) {
  if (s.type === 'object' || (Array.isArray(s.type) && s.type.includes('object'))) {
    const ks = Object.keys(s.properties || {});
    if (s.additionalProperties !== false) { erros.push(caminho + ': additionalProperties deve ser false'); }
    if (JSON.stringify((s.required || []).slice().sort()) !== JSON.stringify(ks.slice().sort())) { erros.push(caminho + ': required difere das propriedades'); }
    ks.forEach(function (k) { validarEstrito(s.properties[k], caminho + '.' + k, erros); });
  }
  if (s.type === 'array' || (Array.isArray(s.type) && s.type.includes('array'))) {
    if (!s.items) { erros.push(caminho + ': array sem items'); } else { validarEstrito(s.items, caminho + '[]', erros); }
  }
  if (s.type === undefined) { erros.push(caminho + ': sem type'); }
  if (s.enum) {
    if (new Set(s.enum).size !== s.enum.length) { erros.push(caminho + ': enum com duplicados'); }
    if (Array.isArray(s.type) && s.type.includes('null') && !s.enum.includes(null)) { erros.push(caminho + ': tipo aceita null mas enum nao'); }
  }
}

test('Montar pedido a IA: schema_json e JSON valido e atende o modo estrito da OpenAI', () => {
  const sc = JSON.parse(pedido().schema_json);
  const erros = []; validarEstrito(sc, 'raiz', erros);
  assert.deepEqual(erros, []);
});

test('Montar pedido a IA: enum de intent sem duplicados e inclui intents essenciais', () => {
  const en = JSON.parse(pedido().schema_json).properties.intent.enum;
  ['create_reminder', 'create_event', 'finance', 'list_manage', 'correct_recent', 'memory_manage', 'agenda_import', 'clarify', 'chat'].forEach(function (i) { assert.ok(en.includes(i), 'falta ' + i); });
});

test('Contrato: cada intent tratado em Interpretar resposta existe no enum do schema', () => {
  const codigo = WF.nodes.find(function (n) { return n.name === 'Interpretar resposta'; }).parameters.jsCode;
  const en = JSON.parse(pedido().schema_json).properties.intent.enum;
  const usados = new Set();
  for (const m of codigo.matchAll(/intent (?:===|!==) '([a-z_]+)'/g)) { usados.add(m[1]); }
  for (const m of codigo.matchAll(/out\.intent = '([a-z_]+)'/g)) { usados.add(m[1]); }
  const sinteticos = new Set(['invite_event', 'link_reminder']); // gerados pelo codigo, nao pelo modelo
  const faltando = [...usados].filter(function (i) { return !en.includes(i) && !sinteticos.has(i); });
  assert.deepEqual(faltando, []);
});

// ---------- Importar agenda ----------
test('Importar agenda: montar pedido - schema estrito, modelo e legenda', () => {
  const nos = { 'Montar pedido a IA': [{ texto_atual: 'Imagem enviada pelo usuario, sem legenda.', image_url: 'data:x' }], 'Interpretar resposta': [{ tz: 'America/Sao_Paulo' }] };
  let o = rodar1('Importar agenda: montar pedido', { nos, agora: AGORA });
  const erros = []; validarEstrito(JSON.parse(o.schema_json), 'raiz', erros);
  assert.deepEqual(erros, []);
  assert.equal(o.prompt, 'Leia a agenda de papel desta foto.'); assert.equal(o.image_url, 'data:x'); assert.match(o.instrucoes, /Hoje e 2026-11-08/);
  nos['Montar pedido a IA'] = [{ texto_atual: 'semana da faculdade', image_url: 'data:x' }];
  o = rodar1('Importar agenda: montar pedido', { nos, agora: AGORA });
  assert.equal(o.prompt, 'Leia a agenda de papel desta foto.' + NL + 'Mensagem da pessoa: semana da faculdade');
});

test('Importar agenda: normalizar - eventos, tarefas, hora ausente, fim invalido, rotulo de categoria', () => {
  const resp = { output: [{ type: 'message', content: [{ text: JSON.stringify({ week_start: '2026-11-09', notes: ['quinta ilegivel'], items: [
    { day: '2026-11-09', kind: 'evento', start: '14:00', end: '17:00', title: '', category: 'Estagio', urgent: false, uncertain: false },
    { day: '2026-11-10', kind: 'evento', start: '09:00', end: '08:00', title: 'Prova', category: 'Faculdade', urgent: true, uncertain: false },
    { day: '2026-11-11', kind: 'evento', start: '23:30', end: null, title: 'Aula', category: null },
    { day: '2026-11-12', kind: 'evento', start: null, end: null, title: 'Sem hora', category: null },
    { day: '2026-11-13', kind: 'tarefa', title: 'Entregar', category: 'Tarefas', urgent: true },
    { day: 'ruim', kind: 'tarefa', title: 'x' }, { day: '2026-11-13', kind: 'tarefa', title: '' },
  ] }) }] }] };
  const o = rodar1('Importar agenda: normalizar', { entrada: [resp], nos: { 'Interpretar resposta': [{ user_id: 7 }] } });
  const x = JSON.parse(o.x); assert.equal(o.user_id, 7);
  assert.equal(x.week_start, '2026-11-09'); assert.deepEqual(x.notes, ['quinta ilegivel']); assert.equal(x.items.length, 5);
  assert.deepEqual(x.items[0], { day: '2026-11-09', kind: 'event', start: '14:00', end: '17:00', title: 'Estagio', urgent: false, uncertain: false });
  assert.deepEqual([x.items[1].title, x.items[1].end, x.items[1].uncertain, x.items[1].urgent], ['Faculdade · Prova', '10:00', true, true]);
  assert.deepEqual([x.items[2].start, x.items[2].end], ['23:30', '23:59']);
  assert.deepEqual([x.items[3].kind, x.items[3].uncertain, x.items[3].title], ['task', true, 'Sem hora']);
  assert.deepEqual([x.items[4].kind, x.items[4].urgent], ['task', true]);
});

test('Importar agenda: normalizar - resposta invalida da IA gera lista vazia', () => {
  const x = JSON.parse(rodar1('Importar agenda: normalizar', { entrada: [{ output: [] }], nos: { 'Interpretar resposta': [{ user_id: 7 }] } }).x);
  assert.deepEqual(x, { week_start: null, items: [], notes: [] });
});

test('Importar agenda: preparar conclusao - resultado do Google, falha e origem do draft_id', () => {
  let o = rodar1('Importar agenda: preparar conclusao', { entrada: [{ draft_id: '5', events_ok: 3, tasks_ok: 1, errors: ['e'] }] });
  assert.equal(o.draft_id, 5); assert.deepEqual(JSON.parse(o.res), { events_ok: 3, events_fail: 0, tasks_ok: 1, tasks_fail: 0, errors: ['e'] });
  o = rodar1('Importar agenda: preparar conclusao', { entrada: [{ error: 'x' }], nos: { 'Executar botao': [{ r: { imp: { draft_id: 9 } } }] } });
  assert.equal(o.draft_id, 9); assert.deepEqual(JSON.parse(o.res).errors, ['falha ao falar com o Google']);
  o = rodar1('Importar agenda: preparar conclusao', { entrada: [{}], nos: { 'Importar agenda: editar': [{ r: { imp: { draft_id: 11 } } }] } });
  assert.equal(o.draft_id, 11);
  assert.equal(rodar1('Importar agenda: preparar conclusao', { entrada: [{}] }).draft_id, 0);
});

// ---------- Docs ----------
test('Docs: expandir - limita a 10, normaliza tipo e limpa legenda', () => {
  const files = Array.from({ length: 12 }, function (_, i) { return { file_id: 'f' + i, tg_type: i === 0 ? 'photo' : (i === 1 ? 'video' : 'qualquer'), caption: i === 0 ? '<b>Rg</b> & cpf' : '' }; });
  const r = runCodeNode(WF, 'Docs: expandir', { entrada: [{ r: { files } }], nosAnteriores: { 'Normalizar update': [{ chat_id: 111 }] } }).map(function (i) { return i.json; });
  assert.equal(r.length, 10);
  assert.deepEqual([r[0].tg_type, r[1].tg_type, r[2].tg_type], ['photo', 'video', 'document']);
  assert.equal(r[0].caption, 'bRg/b  cpf'); assert.equal(r[9].idx, 9);
  assert.equal(runCodeNode(WF, 'Docs: expandir', { entrada: [{}], nosAnteriores: { 'Normalizar update': [{ chat_id: 1 }] } }).length, 0);
});

test('Docs: resposta final - espera todos os envios; conta falhas', () => {
  const nos = function (fotos, docs, total) {
    return { 'Normalizar update': [{ chat_id: 111 }], 'Docs: executar': [{ r: { text: 'Mandei.' } }],
      'Docs: expandir': Array.from({ length: total }, function () { return {}; }), 'Docs: enviar foto': fotos, 'Docs: enviar documento': docs };
  };
  assert.equal(runCodeNode(WF, 'Docs: resposta final', { nosAnteriores: nos([{ ok: 1 }], [], 2) }).length, 0); // ainda falta um envio
  assert.equal(rodar1('Docs: resposta final', { nos: nos([{ ok: 1 }], [{ ok: 1 }], 2) }).text, 'Mandei.');
  assert.equal(rodar1('Docs: resposta final', { nos: nos([{ error: 'x' }], [{ ok: 1 }], 2) }).text, 'Mandei. (1 arquivo nao pode ser enviado: o Telegram recusou.)');
  assert.match(rodar1('Docs: resposta final', { nos: nos([{ error: 1 }], [{ error: 2 }], 2) }).text, /\(2 arquivos nao puderam ser enviados/);
});

// ---------- Preparar PDF (async + binario) ----------
test('Preparar PDF: gera binario a partir de file_b64 (via stub de prepareBinaryData)', async () => {
  const out = await runCodeNodeAsync(WF, 'Preparar PDF', { nosAnteriores: { 'Montar pedido a IA': [{ file_b64: Buffer.from('%PDF-x').toString('base64'), file_name: 'doc.pdf' }] } });
  assert.equal(out[0].json.ok, true); assert.equal(out[0].binary.data.fileName, 'doc.pdf'); assert.equal(out[0].binary.data.mimeType, 'application/pdf');
  assert.equal(Buffer.from(out[0].binary.data.data, 'base64').toString(), '%PDF-x');
});
