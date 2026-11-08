'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { rodar, rodar1, NL, AGORA } = require('./helpers');

// ---------- Memoria ----------
const memPrep = function (upd, o) {
  o = o || {};
  const nos = { 'Normalizar update': [Object.assign({ chat_id: 111, kind: 'text' }, upd)], 'Buscar usuario': [{ id: 7 }] };
  if (o.state !== undefined) { nos['Ler estado da conversa'] = [{ state: o.state ? JSON.stringify(o.state) : '' }]; }
  if (o.mm) { nos['Interpretar resposta'] = [{ mm_json: JSON.stringify(o.mm) }]; }
  return rodar1('Memoria: preparar', { nos: nos });
};
const oferta = function (extra) { return Object.assign({ kind: 'offer', pessoa: 'Maria', lugar: 'Igreja', rel: 'amiga', ts: Date.parse(AGORA) - 60000 }, extra); };

test('Memoria: preparar - texto livre usa mm_json (forget/list/etc.)', () => {
  const o = memPrep({}, { mm: { action: 'forget', ref: 'sogra' } });
  assert.equal(o.action, 'forget'); assert.equal(o.ref, 'sogra'); assert.equal(o.user_id, 7); assert.equal(o.btn, false); assert.equal(o.expired, false);
});

test('Memoria: preparar - botao of:y/of:n com oferta recente carrega pessoa/lugar/rel', () => {
  let o = memPrep({ kind: 'callback', cb_data: 'of:y' }, { state: oferta() });
  assert.deepEqual([o.action, o.btn, o.expired, o.pessoa, o.lugar, o.rel], ['offer_yes', true, false, 'Maria', 'Igreja', 'amiga']);
  o = memPrep({ kind: 'callback', cb_data: 'of:n' }, { state: oferta() });
  assert.equal(o.action, 'offer_no');
});

test('Memoria: preparar - oferta com mais de 15 min expira e vira none', () => {
  const o = memPrep({ kind: 'callback', cb_data: 'of:y' }, { state: oferta({ ts: Date.parse(AGORA) - 16 * 60000 }) });
  assert.equal(o.expired, true); assert.equal(o.action, 'none');
  assert.equal(memPrep({ kind: 'callback', cb_data: 'of:y' }, { state: '' }).expired, true); // sem estado
});

test('Memoria: preparar - "nao" depois de ja ter salvo (accepted) nao faz nada', () => {
  assert.equal(memPrep({ kind: 'callback', cb_data: 'of:n' }, { state: oferta({ accepted: true }) }).action, 'none');
});

test('Memoria: preparar - estado ilegivel/JSON invalido nao quebra', () => {
  const nos = { 'Normalizar update': [{ chat_id: 1, kind: 'text' }], 'Buscar usuario': [{ id: 1 }], 'Ler estado da conversa': [{ state: '{ruim' }], 'Interpretar resposta': [{ mm_json: '{ruim' }] };
  assert.equal(rodar1('Memoria: preparar', { nos }).action, '');
});

const memResp = function (p, r) {
  return rodar1('Memoria: resposta', { entrada: [{ r: r }], nos: { 'Memoria: preparar': [Object.assign({ chat_id: 111, action: 'forget', btn: false, expired: false, pessoa: '', lugar: '', rel: '' }, p)] }, agora: AGORA });
};

test('Memoria: resposta - expirada, none, falha e texto normal', () => {
  assert.match(memResp({ expired: true }, null).text, /já passou/);
  assert.equal(memResp({ action: 'none' }, null).text, 'Ok, deixo assim.');
  assert.match(memResp({}, null).text, /Não consegui agora/);
  assert.equal(memResp({}, { text: 'Esqueci.' }).text, 'Esqueci.');
});

test('Memoria: resposta - offer_yes sem e-mail/endereco guarda estado accepted; com tudo nao', () => {
  let o = memResp({ action: 'offer_yes', pessoa: 'Maria', lugar: 'Igreja', rel: 'amiga' }, { ok: true, text: 'Salvei.', person: { email: '' }, place: { address: '' } });
  assert.equal(o.text, 'Salvei. Se quiser, me manda o e-mail e o endereço que eu completo.');
  const st = JSON.parse(o.state);
  assert.deepEqual([st.kind, st.accepted, st.pessoa, st.lugar], ['offer', true, 'Maria', 'Igreja']);
  o = memResp({ action: 'offer_yes' }, { ok: true, text: 'Salvei.', person: { email: 'a@b.c' }, place: { address: 'Rua 1' } });
  assert.equal(o.state, ''); assert.equal(o.text, 'Salvei.');
});

test('Memoria: resposta - botao limpa o estado com kind none', () => {
  assert.deepEqual(JSON.parse(memResp({ btn: true, action: 'offer_no' }, { text: 'Ok.' }).state), { kind: 'none' });
});

// ---------- Multi ----------
const multiPrep = function (a, batch) {
  const A = Object.assign({ chat_id: 111, tz: 'America/Sao_Paulo', user_id: 7, calendar_key: 'adrian' }, a);
  return rodar1('Multi: preparar', { entrada: [{ batch: batch === undefined ? 12 : batch }], nos: { 'Interpretar resposta': [A] }, agora: AGORA });
};

test('Multi: preparar - classifica lista, nota, tomei, gasto, tarefa, lembrete e compromisso', () => {
  const o = multiPrep({ more_actions: [
    { kind: 'lista', title: 'x', items: ['leite', ' ', 'pao'], list_name: 'mercado' },
    { kind: 'nota', title: 'ideia' },
    { kind: 'gasto', title: 'uber', amount: 50 },
    { kind: 'tarefa', title: 'ligar', date: '2026-11-12' },
    { kind: 'lembrete', title: 'agua', time: '10:00', date: '2026-11-09', lead_minutes: 15 },
    { kind: 'compromisso', title: 'dentista', time: '9:00', date: '2026-11-10', duration_minutes: 30, location: 'Clinica' },
  ] });
  assert.equal(o.batch_id, 12);
  assert.deepEqual(o.multi_db.map(function (x) { return x.kind; }), ['list', 'note', 'expense', 'reminder']);
  assert.deepEqual(o.multi_db[0].items, ['leite', 'pao']); assert.equal(o.multi_db[0].title, 'leite, pao');
  assert.equal(o.multi_db[3].due_iso, '2026-11-09T10:00:00.000-03:00'); assert.equal(o.multi_db[3].lead, '15');
  assert.deepEqual(o.multi_tk, [{ title: 'ligar', due: '2026-11-12', calendar_key: 'adrian' }]);
  assert.equal(o.multi_ev[0].due_iso, '2026-11-10T09:00:00.000-03:00'); assert.equal(o.multi_ev[0].end_iso, '2026-11-10T09:30:00.000-03:00');
  assert.equal(o.multi_ev[0].location, 'Clinica'); assert.equal(o.multi_ask.length, 0); assert.equal(o.multi_n, 6);
});

test('Multi: preparar - tomei vira supply', () => {
  assert.deepEqual(multiPrep({ more_actions: [{ kind: 'tomei', title: 'vitamina' }] }).multi_db, [{ kind: 'supply', title: 'vitamina' }]);
});

test('Multi: preparar - falta valor/hora/data valida vira pergunta; ignora lixo e limita a 6', () => {
  const o = multiPrep({ more_actions: [
    { kind: 'gasto', title: 'uber' }, { kind: 'lembrete', title: 'x' }, { kind: 'compromisso', title: 'y', time: '08:00', date: '2026-11-01' },
    null, 'texto', { kind: 'nota', title: '' }, { kind: 'nota', title: 'extra-7' },
  ] });
  assert.deepEqual(o.multi_ask, ['o valor de "uber"', 'a hora de "x"', 'a data de "y"']);
  assert.equal(o.multi_n, 3);
});

test('Multi: preparar - lembrete sem data: hoje se ainda nao passou, senao amanha', () => {
  const o = multiPrep({ more_actions: [{ kind: 'lembrete', title: 'a', time: '23:00' }, { kind: 'lembrete', title: 'b', time: '08:00' }] });
  assert.equal(o.multi_db[0].due_iso, '2026-11-08T23:00:00.000-03:00'); assert.equal(o.multi_db[1].due_iso, '2026-11-09T08:00:00.000-03:00');
});

test('Multi: preparar - batch invalido vira 0 e o contexto da interpretacao e preservado', () => {
  const o = multiPrep({ intent: 'create_event', more_actions: [] }, 'x');
  assert.equal(o.batch_id, 0); assert.equal(o.intent, 'create_event'); assert.equal(o.multi_n, 0);
});

test('Multi: expandir compromissos / tarefas viram itens; sem calendario marca erro', () => {
  const nos = { 'Multi: preparar': [{ multi_ev: [{ title: 'a' }, { title: 'b' }], multi_tk: [{ title: 't' }] }] };
  assert.deepEqual(rodar('Multi: expandir compromissos', { nos }), [{ title: 'a' }, { title: 'b' }]);
  assert.deepEqual(rodar('Multi: expandir tarefas', { nos }), [{ title: 't' }]);
  assert.deepEqual(rodar('Multi: expandir tarefas', { nos: { 'Multi: preparar': [{}] } }), []);
  assert.deepEqual(rodar('Multi: sem calendario', { entrada: [{}, {}] }), [{ ok: false, error: 'agenda nao conectada' }, { ok: false, error: 'agenda nao conectada' }]);
});

test('Multi: concluir compromissos - combina pedido e resultado, trata resposta ruim', () => {
  const nos = { 'Multi: expandir compromissos': [{ title: 'a', due_iso: 'D1', end_iso: 'E1' }, { title: 'b', due_iso: 'D2', end_iso: 'E2', location: 'L' }, { title: 'c', due_iso: 'D3', end_iso: 'E3' }], 'Multi: preparar': [{ user_id: 7 }] };
  const o = rodar1('Multi: concluir compromissos', { entrada: [{ ok: true, id: 'g1' }, { error: { message: 'boom' } }], nos });
  const it = JSON.parse(o.items_json);
  assert.equal(o.user_id, 7); assert.equal(it.length, 3);
  assert.deepEqual(it[0].result, { ok: true, id: 'g1' }); assert.equal(it[0].req.title, 'a'); assert.equal(it[0].req.meet, 'false');
  assert.deepEqual(it[1].result, { ok: false, error: 'boom' }); assert.equal(it[1].req.location, 'L');
  assert.deepEqual(it[2].result, { ok: false, error: 'sem resposta' });
});

test('Multi: concluir tarefas - junta pedido e retorno por posicao', () => {
  const nos = { 'Multi: expandir tarefas': [{ title: 't', due: '2026-11-12', calendar_key: 'k' }, { title: 'u' }], 'Multi: preparar': [{ user_id: 7 }] };
  const it = JSON.parse(rodar1('Multi: concluir tarefas', { entrada: [{ id: 1 }], nos }).items_json);
  assert.deepEqual(it[0], { title: 't', due: '2026-11-12', calendar_key: 'k', result: { id: 1 } });
  assert.deepEqual(it[1], { title: 'u', due: '', calendar_key: '', result: {} });
});

test('Multi: consolidar - junta lines/fails dos tres nos de banco, ignorando os ausentes', () => {
  const nos = { 'Multi: preparar': [{ intent: 'x', batch_id: 3 }], 'Multi: banco': [{ r: { lines: ['a', 'b'], fails: ['f1'] } }], 'Multi: tarefas no banco': [{ r: { lines: ['t'] } }] };
  const o = rodar1('Multi: consolidar', { nos });
  assert.deepEqual(o.multi_lines, ['a', 'b', 't']); assert.deepEqual(o.multi_fails, ['f1']); assert.equal(o.batch_id, 3);
  const v = rodar1('Multi: consolidar', { nos: { 'Multi: preparar': [{}] } });
  assert.deepEqual([v.multi_lines, v.multi_fails], [[], []]);
});

// ---------- Lote (Desfazer tudo) ----------
test('Lote: expandir exclusoes lista os calendarios; sem calendario marca erro', () => {
  const nos = { 'Executar botao': [{ r: { cals: [{ title: 'a', id: 1 }, { title: 'b', id: 2 }] } }] };
  assert.deepEqual(rodar('Lote: expandir exclusoes', { nos }), [{ title: 'a', id: 1 }, { title: 'b', id: 2 }]);
  assert.deepEqual(rodar('Lote: expandir exclusoes', { nos: { 'Executar botao': [{}] } }), []);
  assert.deepEqual(rodar('Lote: sem calendario', { entrada: [{}] }), [{ ok: false, error: 'agenda nao conectada' }]);
});

test('Lote: concluir desfazer - lista compromissos que o Google nao apagou', () => {
  const nos = { 'Normalizar update': [{ chat_id: 111 }], 'Executar botao': [{ r: { text: 'Desfeito 3 itens.', cals: [{ title: 'Dentista' }, { title: 'Reuniao' }, {}] } }] };
  const o = rodar1('Lote: concluir desfazer', { entrada: [{ ok: true }, { ok: false }], nos });
  assert.equal(o.text, ['Desfeito 3 itens.', '', 'Não consegui apagar estes compromissos do Google (apague na agenda se quiser):', '- Reuniao', '- compromisso'].join(NL));
  const s = rodar1('Lote: concluir desfazer', { entrada: [{ ok: true }], nos: { 'Normalizar update': [{ chat_id: 1 }], 'Executar botao': [{ r: { cals: [{ title: 'a' }] } }] } });
  assert.equal(s.text, 'Desfeito.'); assert.equal(s.kb, 'none');
});
