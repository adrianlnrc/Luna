'use strict';
// Normalizar update, Checar duplicado, Resposta do comando, Montar historico, Restaurar interpretacao
const test = require('node:test');
const assert = require('node:assert/strict');
const { rodar, rodar1, NL, AGORA } = require('./helpers');

const norm = function (u) { return rodar1('Normalizar update', { entrada: [u] }); };
const msg = function (extra) { return { update_id: 1, message: Object.assign({ message_id: 10, chat: { id: 111 }, from: { id: 5 } }, extra) }; };

test('Normalizar update: texto, comando e reply_to_message', () => {
  let o = norm(msg({ text: 'oi' }));
  assert.equal(o.kind, 'text'); assert.equal(o.chat_id, 111); assert.equal(o.from_id, 5); assert.equal(o.update_id, 1);
  assert.equal(norm(msg({ text: '/menu' })).kind, 'command');
  o = norm(msg({ text: 'sim', reply_to_message: { text: 'x'.repeat(500) } }));
  assert.equal(o.reply_text.length, 300);
});

test('Normalizar update: voz, audio, foto (maior resolucao + legenda)', () => {
  assert.deepEqual([norm(msg({ voice: { file_id: 'v1' } })).kind, norm(msg({ voice: { file_id: 'v1' } })).file_id], ['voice', 'v1']);
  assert.equal(norm(msg({ audio: { file_id: 'a1' } })).kind, 'voice');
  const o = norm(msg({ photo: [{ file_id: 'p1', file_size: 1 }, { file_id: 'p2', file_size: 99 }], caption: 'recibo' }));
  assert.equal(o.kind, 'photo'); assert.equal(o.file_id, 'p2'); assert.equal(o.text, 'recibo'); assert.equal(o.file_size, 99); assert.equal(o.tg_type, 'photo');
});

test('Normalizar update: documento (pdf/imagem ate 15MB), arquivo, video e unsupported', () => {
  const doc = function (mime, size) { return norm(msg({ document: { file_id: 'd', mime_type: mime, file_size: size, file_name: 'a.x' } })); };
  assert.equal(doc('application/pdf', 1000).kind, 'document');
  assert.equal(doc('image/PNG', 1000).kind, 'document');
  assert.equal(doc('application/pdf', 16000000).kind, 'file');
  assert.equal(doc('application/zip', 1000).kind, 'file');
  assert.equal(doc('application/zip', 60000000).kind, 'unsupported');
  assert.equal(norm(msg({ video: { file_id: 'v', file_size: 1000 } })).kind, 'file');
  assert.equal(norm(msg({ video: { file_id: 'v', file_size: 60000000 } })).kind, 'unsupported');
});

test('Normalizar update: callback_query e update desconhecido', () => {
  const o = norm({ update_id: 3, callback_query: { id: 'c1', data: 'of:y', from: { id: 5 }, message: { message_id: 7, chat: { id: 111 } } } });
  assert.equal(o.kind, 'callback'); assert.equal(o.cb_data, 'of:y'); assert.equal(o.cb_id, 'c1'); assert.equal(o.chat_id, 111); assert.equal(o.message_id, 7);
  const x = norm({ update_id: 4, edited_message: {} });
  assert.equal(x.kind, 'other'); assert.equal(x.chat_id, 0);
});

test('Checar duplicado: contador > 1 marca duplicado e preserva o update', () => {
  const nos = { 'Normalizar update': [{ chat_id: 1, kind: 'text' }] };
  assert.equal(rodar1('Checar duplicado', { entrada: [{ incr: 1 }], nos }).duplicado, false);
  const o = rodar1('Checar duplicado', { entrada: [{ incr: 2 }], nos });
  assert.equal(o.duplicado, true); assert.equal(o.kind, 'text');
});

const cmd = function (texto, extra) {
  const nos = Object.assign({ 'Normalizar update': [{ chat_id: 111, text: texto, kind: 'command' }], 'Buscar usuario': [{ name: 'Adrian', onboarding_step: 'done' }] }, extra || {});
  return rodar1('Resposta do comando', { nos: nos });
};

test('Resposta do comando: /start (onboarding pendente pede horario do resumo) e /start concluido', () => {
  let o = rodar1('Resposta do comando', { nos: { 'Normalizar update': [{ chat_id: 111, text: '/start', kind: 'command' }], 'Buscar usuario': [{ name: 'Adrian', onboarding_step: 'name' }] } });
  assert.match(o.text, /^Oi, Adrian!/); assert.equal(o.kb, 'summary_time'); assert.match(o.text, /a que horas voce quer receber o resumo/);
  o = cmd('/start');
  assert.equal(o.kb, 'none'); assert.doesNotMatch(o.text, /resumo da manha\?/);
});

test('Resposta do comando: /menu, /ajuda, /help (com @bot e maiusculas) abrem o menu', () => {
  ['/menu', '/ajuda', '/help', '/Menu@MeuBot arg'].forEach(function (c) {
    const o = cmd(c); assert.equal(o.kb, 'menu'); assert.match(o.text, /O que eu faço/);
  });
});

test('Resposta do comando: /config com e sem preferencias de memoria', () => {
  let o = cmd('/config', { 'Comando: dados': [{ r: { config: 'Resumo as 8h' }, x: { mem_enabled: true, offer_save_enabled: false, suggest_enabled: true } }] });
  assert.ok(o.text.startsWith('Resumo as 8h' + NL + NL + 'Memória: ligada'));
  assert.match(o.text, /Perguntar se salvo: desligado/); assert.match(o.text, /Sugestões: ligadas/);
  o = cmd('/config', { 'Comando: dados': [{ r: {} }] });
  assert.match(o.text, /Nao consegui ler suas preferencias/);
  assert.match(cmd('/config').text, /Nao consegui ler suas preferencias/); // sem o no: try/catch
});

test('Resposta do comando: /locais /custo /contatos /memoria (dados e fallbacks) e desconhecido', () => {
  assert.equal(cmd('/locais', { 'Comando: dados': [{ r: { locais: 'Casa' } }] }).text, 'Casa');
  assert.equal(cmd('/locais', { 'Comando: dados': [{ r: {}, x: { text: 'Via x' } }] }).text, 'Via x');
  assert.equal(cmd('/custo', { 'Comando: dados': [{ r: { custo: 'R$ 2' } }] }).text, 'R$ 2');
  assert.match(cmd('/custo').text, /calcular o custo/);
  assert.equal(cmd('/contatos', { 'Comando: dados': [{ r: { contatos: 'Ana' } }] }).text, 'Ana');
  assert.equal(cmd('/memoria', { 'Comando: dados': [{ x: { text: 'Anotei X' } }] }).text, 'Anotei X');
  assert.match(cmd('/memoria').text, /ler sua memoria/);
  assert.equal(cmd('/xpto').text, 'Nao conheco esse comando. Use /ajuda.');
});

test('Resposta do comando: arquivo acima de 50MB (unsupported) tem prioridade', () => {
  const o = rodar1('Resposta do comando', { nos: { 'Normalizar update': [{ chat_id: 111, text: '', kind: 'unsupported' }], 'Buscar usuario': [{ name: 'A' }] } });
  assert.match(o.text, /passa de 50 MB/);
});

const hist = function (u, o) {
  const nos = { 'Preparar envio': [{ chat_id: 111, text: o.resposta || 'Pronto.' }], 'Normalizar update': [u] };
  if (o.hist) { nos['Ler historico da conversa'] = [{ hist: JSON.stringify(o.hist) }]; }
  if (o.ia) { nos['Interpretar resposta'] = [o.ia]; }
  return rodar1('Montar historico', { nos: nos });
};
const T = Date.parse(AGORA);

test('Montar historico: acrescenta par user/model e anota [agendado: ...]', () => {
  const o = hist({ kind: 'text', text: 'lembra de x as 9' }, { ia: { intent: 'create_reminder', due_iso: '2026-11-09T09:00:00.000-03:00', transcript: 'lembra de x as 9' } });
  const h = JSON.parse(o.hist);
  assert.equal(h.length, 2); assert.equal(h[0].r, 'user'); assert.equal(h[1].r, 'model');
  assert.equal(h[1].t, 'Pronto. [agendado: 2026-11-09 09:00]'); assert.equal(o.chat_id, 111);
});

test('Montar historico: prefixos de foto/arquivo; ignora erro do LLM, callback e textos vazios', () => {
  const t = function (u, ia) { return JSON.parse(hist(u, { ia: ia || { intent: 'chat' } }).hist); };
  assert.equal(t({ kind: 'photo', text: 'recibo' })[0].t, '[foto] recibo');
  assert.equal(t({ kind: 'document', text: 'x' })[0].t, '[arquivo] x');
  assert.equal(t({ kind: 'file', text: 'x', file_name: 'a.zip' })[0].t, '[arquivo a.zip] x');
  assert.equal(t({ kind: 'text', text: 'a' }, { llm_error: true }).length, 0);
  assert.equal(t({ kind: 'callback' }).length, 0);
  assert.equal(t({ kind: 'text', text: '' }).length, 0);
});

test('Montar historico: descarta mais de 6h, limita a 40 e corta textos', () => {
  const velho = { r: 'user', t: 'velho', ts: T - 7 * 3600 * 1000 };
  const novo = { r: 'user', t: 'novo', ts: T - 1000 };
  let h = JSON.parse(hist({ kind: 'callback' }, { hist: [velho, novo] }).hist);
  assert.deepEqual(h.map(function (x) { return x.t; }), ['novo']);
  const muitos = Array.from({ length: 50 }, function (_, i) { return { r: 'user', t: 'm' + i, ts: T - 1000 }; });
  h = JSON.parse(hist({ kind: 'text', text: 'y'.repeat(900) }, { hist: muitos, resposta: 'z'.repeat(900) }).hist);
  assert.equal(h.length, 40); assert.equal(h[39].t.length, 560); assert.equal(h[38].t.length, 600);
});

test('Restaurar interpretacao: devolve a saida de Interpretar resposta', () => {
  assert.deepEqual(rodar('Restaurar interpretacao', { nos: { 'Interpretar resposta': [{ intent: 'chat', a: 1 }] } }), [{ intent: 'chat', a: 1 }]);
});
