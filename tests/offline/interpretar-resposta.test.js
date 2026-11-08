'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { interpretar, mensagem, respostaIA } = require('./helpers');

test('Interpretar resposta: intencao simples (create_event ag-01) mescla base e campos do modelo', () => {
  const o = interpretar({ intent: 'create_event', title: 'Consulta gastro', date: '2026-11-09', time: '17:40', reply: null }, { caso: 'ag-01' });
  assert.equal(o.intent, 'create_event');
  assert.equal(o.user_id, 7); assert.equal(o.chat_id, 111); assert.equal(o.tz, 'America/Sao_Paulo');
  assert.equal(o.source, 'text'); assert.equal(o.original_text, mensagem('ag-01'));
  assert.equal(o.due_iso, '2026-11-09T17:40:00.000-03:00');
  assert.equal(o.end_iso, '2026-11-09T18:40:00.000-03:00');
  assert.equal(o.due_label, 'seg. 09/11 as 17:40');
  assert.equal(o.reply, ''); // null vira string vazia
});

test('Interpretar resposta: tokens estimados quando a API nao devolve usage; reais quando devolve', () => {
  let o = interpretar({ intent: 'chat', reply: 'oi' }, { texto: 'oi' });
  assert.equal(o.ai_est, true); assert.ok(o.ai_tin >= 0 && o.ai_tout > 0);
  o = interpretar({ intent: 'chat', reply: 'oi' }, { texto: 'oi', usage: { input_tokens: 100, output_tokens: 20 } });
  assert.equal(o.ai_est, false); assert.equal(o.ai_tin, 100); assert.equal(o.ai_tout, 20);
});

test('Interpretar resposta: lembrete sem hora vira clarify; hora no passado tambem', () => {
  let o = interpretar({ intent: 'create_reminder', title: 'agua' }, { texto: 'me lembra de beber agua' });
  assert.equal(o.intent, 'clarify'); assert.match(o.reply, /Que horas/);
  o = interpretar({ intent: 'create_reminder', title: 'x', date: '2026-11-08', time: '09:00' }, { texto: 'x' });
  assert.equal(o.intent, 'clarify'); assert.match(o.reply, /ja passou/);
});

test('Interpretar resposta: "amanha as 10h" no texto completa data e hora quando o modelo omite', () => {
  const o = interpretar({ intent: 'create_reminder', title: 'ligar contador' }, { texto: 'me lembra de ligar pro contador amanhã às 10h' });
  assert.equal(o.intent, 'create_reminder');
  assert.equal(o.due_iso, '2026-11-09T10:00:00.000-03:00');
});

test('Interpretar resposta: lembrete sem data e hora futura de hoje fica hoje; hora passada vai para amanha', () => {
  let o = interpretar({ intent: 'create_reminder', title: 'x', time: '23:00' }, { texto: 'x' });
  assert.equal(o.due_iso, '2026-11-08T23:00:00.000-03:00');
  o = interpretar({ intent: 'create_reminder', title: 'x', time: '08:00' }, { texto: 'x' });
  assert.equal(o.due_iso, '2026-11-09T08:00:00.000-03:00');
});

test('Interpretar resposta: erro do modelo vira chat com mensagem amigavel', () => {
  let o = interpretar(null, { cru: { error: { message: 'You exceeded your current quota' } } });
  assert.equal(o.intent, 'chat'); assert.equal(o.llm_error, true); assert.match(o.reply, /limite de uso/);
  o = interpretar(null, { cru: { error: 'The model `gpt-x` does not exist' } });
  assert.match(o.reply, /gpt-x/);
  o = interpretar(null, { cru: { output: [] } });
  assert.match(o.reply, /problema para entender/);
});

test('Interpretar resposta: lista com tracos no texto forca list_manage (li-01 estilo)', () => {
  const texto = 'Mercado:\n- leite\n- pão\n- ovos';
  const o = interpretar({ intent: 'chat', reply: 'x' }, { texto: texto });
  assert.equal(o.intent, 'list_manage'); assert.equal(o.list_action, 'add');
  assert.deepEqual(o.list_items, ['leite', 'pão', 'ovos']);
  assert.equal(o.list_name, null);
  assert.deepEqual(JSON.parse(o.list_json).list_items, ['leite', 'pão', 'ovos']);
});

test('Interpretar resposta: list_manage do modelo gera list_json filtrando itens vazios', () => {
  const o = interpretar({ intent: 'list_manage', list_action: 'add', list_name: 'mercado', list_items: ['leite', ' ', 'pão'] }, { caso: 'li-01' });
  assert.deepEqual(JSON.parse(o.list_json).list_items, ['leite', 'pão']);
  assert.equal(JSON.parse(o.list_json).text, mensagem('li-01'));
});

test('Interpretar resposta: correct_recent monta corr_json normalizado', () => {
  const o = interpretar({ intent: 'correct_recent', recent_id: 12, title: 'Dentista', date: '2026-11-10', time: '9:30', note_text: 'trocar' }, { texto: 'na verdade e dia 10 as 9:30' });
  assert.equal(o.intent, 'correct_recent');
  assert.deepEqual(JSON.parse(o.corr_json), { recent_id: 12, title: 'Dentista', date: '2026-11-10', time: '09:30', note_text: 'trocar' });
});

test('Interpretar resposta: correct_recent descarta data invalida e recent_id nao numerico', () => {
  const o = interpretar({ intent: 'correct_recent', recent_id: 'x', date: '10/11' }, { texto: 'corrige' });
  const c = JSON.parse(o.corr_json);
  assert.equal(c.recent_id, null); assert.equal(c.date, '');
});

test('Interpretar resposta: memory_manage valido (me-09 offer_yes) gera mm_json e mem_json vazio', () => {
  const o = interpretar({ intent: 'memory_manage', mem_action: 'offer_yes', contact_email: 'maria@exemplo.com', location: 'Rua das Flores 100', mem_ref: null }, { caso: 'me-09' });
  assert.deepEqual(JSON.parse(o.mm_json), { action: 'offer_yes', ref: '', email: 'maria@exemplo.com', address: 'Rua das Flores 100' });
  assert.equal(o.mem_json, '[]');
});

test('Interpretar resposta: memory_manage sem acao reconhecida vira clarify', () => {
  const o = interpretar({ intent: 'memory_manage', mem_action: 'xyz' }, { caso: 'me-05' });
  assert.equal(o.intent, 'clarify'); assert.match(o.reply, /esqueça algo/);
  assert.equal(o.mm_json, undefined);
});

test('Interpretar resposta: mem_facts (me-01) limita a 2, tipo invalido vira fato, texto curto some', () => {
  const o = interpretar({ intent: 'chat', reply: 'ok', mem_facts: [
    { texto: 'Sogra: Dona Marta', tipo: 'relacao' }, { texto: 'abc', tipo: 'fato' }, { texto: 'Gosta de cafe', tipo: 'zzz' }, { texto: 'Terceiro fato', tipo: 'fato' },
  ], new_person: 'Marta', new_place: null }, { caso: 'me-01' });
  assert.deepEqual(JSON.parse(o.mem_json), [{ texto: 'Sogra: Dona Marta', tipo: 'relacao' }, { texto: 'Gosta de cafe', tipo: 'fato' }]);
  assert.deepEqual(JSON.parse(o.offer_json), { pessoa: 'Marta', rel: '', lugar: '' });
});

test('Interpretar resposta: convidado ou local desconhecido transforma create_event em invite_event', () => {
  let o = interpretar({ intent: 'create_event', title: 'Reuniao', date: '2026-11-10', time: '15:00', invitees: ['pedro@x.com'] }, { texto: 'reuniao com o Pedro' });
  assert.equal(o.intent, 'invite_event');
  assert.equal(JSON.parse(o.invite_json).invitees[0], 'pedro@x.com');
  o = interpretar({ intent: 'create_event', title: 'Jantar', date: '2026-11-10', time: '20:00', location: 'Fratello Uno' }, { texto: 'jantar' });
  assert.equal(o.intent, 'invite_event');
  o = interpretar({ intent: 'create_event', title: 'Jantar', date: '2026-11-10', time: '20:00', location: 'Fratello Uno' }, { texto: 'jantar', user: { places_txt: 'fratello uno = Rua A' } });
  assert.equal(o.intent, 'create_event');
});

test('Interpretar resposta: agenda_import sem foto vira chat orientando', () => {
  const o = interpretar({ intent: 'agenda_import' }, { texto: 'importa minha agenda' });
  assert.equal(o.intent, 'chat'); assert.match(o.reply, /foto da página/);
});

test('Interpretar resposta: finance (mu-04) monta fin_json com defaults', () => {
  const o = interpretar({ intent: 'finance', fin_action: 'add', amount: 20, title: 'almoco', fin_items: [{ amount: 5 }, { amount: 0 }] }, { caso: 'mu-04' });
  const f = JSON.parse(o.fin_json);
  assert.equal(f.amount, 20); assert.equal(f.kind, 'expense'); assert.equal(f.paid, true); assert.equal(f.installments, 1);
  assert.equal(f.items.length, 1); assert.equal(f.period, 'current');
});

test('Interpretar resposta: list_agenda calcula janela e rotulo', () => {
  const o = interpretar({ intent: 'list_agenda', range_start: '2026-11-09', range_end: '2026-11-11' }, { texto: 'agenda da semana' });
  assert.equal(o.range_label, '09/11 a 11/11');
  assert.equal(o.time_min, '2026-11-09T00:00:00.000-03:00'); assert.equal(o.time_max, '2026-11-12T00:00:00.000-03:00');
});

test('Interpretar resposta: estado snooze converte hora em provide_time com rid', () => {
  const o = interpretar({ intent: 'clarify', time: '16:00', date: '2026-11-08' }, { texto: 'as 16h', ctx: { state: { kind: 'snooze', reminder_id: 33 } } });
  assert.equal(o.intent, 'provide_time'); assert.equal(o.rid, 33);
  assert.equal(o.due_iso, '2026-11-08T16:00:00.000-03:00');
});

test('Interpretar resposta: saida estruturada ja como objeto (p.text objeto) tambem e aceita', () => {
  const cru = { output: [{ type: 'message', content: [{ text: { intent: 'chat', reply: 'oi' } }] }] };
  const o = interpretar(null, { cru: cru });
  assert.equal(o.intent, 'chat'); assert.equal(o.reply, 'oi');
});
