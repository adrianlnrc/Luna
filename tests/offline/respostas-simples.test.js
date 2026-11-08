'use strict';
// Nos "Resposta ..." que apenas formatam {chat_id,text,kb,rid,state} a partir do retorno do banco/API.
const test = require('node:test');
const assert = require('node:assert/strict');
const { rodar1, NL } = require('./helpers');

const IA = { 'Interpretar resposta': [{ chat_id: 111, title: 'Dentista', due_label: 'seg. 09/11 as 09:00', transcript: 'orig', original_text: 'orig' }] };
const UPD = { 'Normalizar update': [{ chat_id: 222 }] };
const base = function (o) { return Object.assign({ chat_id: 111, kb: 'none', rid: 0, state: '' }, o); };

// [no, fonte dos nos anteriores, texto padrao quando r vazio, chat esperado]
const PADRAO = [
  ['Agenda: resposta da criacao', IA, 'Nao consegui registrar o compromisso agora. Tente de novo.'],
  ['Agenda: resposta da gestao', IA, 'Nao consegui mexer na agenda agora. Tente de novo.'],
  ['Agenda: resposta do lembrete ligado', IA, 'Nao consegui ligar o lembrete agora. Tente de novo.'],
  ['Agenda: resposta da acao', UPD, 'Nao consegui concluir agora. Confira sua agenda.', 222],
  ['Extras: Resposta', IA, 'Nao consegui agora. Tente de novo.'],
  ['Contatos: resposta', IA, 'Nao consegui agora. Tente de novo.'],
  ['Docs: resposta', UPD, 'Nao consegui agora. Tente de novo.', 222],
  ['Listas: resposta', IA, 'Nao consegui agora. Tente de novo.'],
  ['Correcao: resposta', IA, 'Nao consegui corrigir agora. Tente de novo.'],
  ['Resposta das financas', IA, 'Nao consegui registrar agora. Tente de novo.'],
  ['Importar agenda: resposta', UPD, 'Ok.', 222],
  ['Resposta do botao', UPD, 'Ok.', 222],
];
PADRAO.forEach(function (c) {
  const [nome, nos, padrao, chat] = c;
  test(nome + ': r vazio usa texto padrao; r completo repassa text/kb/rid', () => {
    assert.deepEqual(rodar1(nome, { entrada: [{}], nos: nos }), base({ chat_id: chat || 111, text: padrao }));
    const o = rodar1(nome, { entrada: [{ r: { text: 'feito', kb: 'undo', rid: 5, state: 'S' } }], nos: nos });
    assert.equal(o.text, 'feito'); assert.equal(o.kb, 'undo'); assert.equal(o.rid, 5); assert.equal(o.chat_id, chat || 111);
  });
});

test('Projetos: Resposta le Projetos: Executar, cai para Executar botao, e usa padrao', () => {
  const nos = function (a, b) { const n = { 'Normalizar update': [{ chat_id: 9 }] }; if (a) { n['Projetos: Executar'] = [a]; } if (b) { n['Executar botao'] = [b]; } return n; };
  assert.equal(rodar1('Projetos: Resposta', { nos: nos({ r: { text: 'A', kb: 'k', rid: 2, state: 's' } }, { r: { text: 'B' } }) }).text, 'A');
  assert.equal(rodar1('Projetos: Resposta', { nos: nos({ r: {} }, { r: { text: 'B' } }) }).text, 'B');
  const o = rodar1('Projetos: Resposta', { nos: nos(null, null) });
  assert.equal(o.text, 'Nao consegui mexer nos projetos agora. Tente de novo.'); assert.equal(o.chat_id, 9);
});

test('Resposta do custo de IA: usa r.r ou padrao', () => {
  assert.equal(rodar1('Resposta do custo de IA', { entrada: [{ r: 'Custo: R$ 1' }], nos: IA }).text, 'Custo: R$ 1');
  assert.equal(rodar1('Resposta do custo de IA', { entrada: [{}], nos: IA }).text, 'Nao consegui calcular o custo agora. Tente de novo.');
});

test('Pesquisa: resposta usa text ou aviso', () => {
  assert.equal(rodar1('Pesquisa: resposta', { entrada: [{ text: 'achei' }], nos: IA }).text, 'achei');
  assert.match(rodar1('Pesquisa: resposta', { entrada: [{}], nos: IA }).text, /Não consegui pesquisar/);
});

test('Resposta direta: clarify guarda estado; chat nao; sem reply usa fallback', () => {
  const nos = function (a) { return { 'Interpretar resposta': [Object.assign({ chat_id: 111 }, a)], 'Normalizar update': [{ text: 'msg' }] }; };
  let o = rodar1('Resposta direta', { nos: nos({ intent: 'clarify', reply: 'Que dia?', transcript: 'reuniao' }) });
  assert.equal(o.text, 'Que dia?'); assert.deepEqual(JSON.parse(o.state), { kind: 'clarify', original: 'reuniao' });
  o = rodar1('Resposta direta', { nos: nos({ intent: 'clarify' }) });
  assert.deepEqual(JSON.parse(o.state), { kind: 'clarify', original: 'msg' }); assert.match(o.text, /Nao entendi/);
  o = rodar1('Resposta direta', { nos: nos({ intent: 'chat', reply: 'oi' }) });
  assert.equal(o.state, '');
});

test('Calendario nao conectado e Agenda: sem calendario (acao)', () => {
  assert.match(rodar1('Calendario nao conectado', { nos: IA }).text, /Google Calendar ainda nao esta conectado/);
  const o = rodar1('Agenda: sem calendario (acao)', { nos: UPD });
  assert.equal(o.chat_id, 222); assert.match(o.text, /Nao encontrei o calendario/);
});

test('Resposta do lembrete: criado, repeticao, aviso antes (min/h/dias), ask_lead e duplicado', () => {
  const run = function (r, a) { return rodar1('Resposta do lembrete', { entrada: [{ r: r }], nos: { 'Interpretar resposta': [Object.assign({ chat_id: 111, title: 'Agua', due_label: 'seg. 09/11 as 09:00' }, a)] } }); };
  assert.equal(run({ reminder_id: 8 }, {}).text, 'Lembrete criado: "Agua" - seg. 09/11 as 09:00.');
  assert.equal(run({ reminder_id: 8 }, {}).rid, 8);
  assert.match(run({ repeat_text: 'todo dia' }, { shared: true }).text, /\(para voces dois\)\. Repete todo dia\./);
  assert.match(run({}, { lead_str: '30' }).text, /Aviso 30 min antes\./);
  assert.match(run({}, { lead_str: '120' }).text, /Aviso 2h antes\./);
  assert.match(run({}, { lead_str: '2880' }).text, /Aviso 2 dia\(s\) antes\./);
  const q = run({ ask_lead: true }, {});
  assert.equal(q.kb, 'lead'); assert.match(q.text, /Quer que eu te lembre antes\?/);
  assert.equal(run({ duplicate: true }, {}).text, 'Já tinha esse lembrete: "Agua" - seg. 09/11 as 09:00.');
});

test('Resposta do estoque novo: com total, sem total (pergunta + estado), needs_total sem pergunta', () => {
  const run = function (r) { return rodar1('Resposta do estoque novo', { entrada: [{ r: r }], nos: IA }); };
  let o = run({ item: 'Losartana', kind: 'remedio', take_time: '08:00', units_left: 29.6, runs_out_on: '2026-12-07', alert_on: '2026-12-01' });
  assert.equal(o.text, ['Anotado: Losartana (remedio).', 'Lembro de tomar todo dia as 08:00 e repito a cada 10 minutos ate voce tocar Tomei.', 'Restam 30 e acaba em 2026-12-07. O aviso de compra entra no resumo da manha a partir de 2026-12-01.'].join(NL));
  o = run({ item: 'Vitamina', units_left: 10, runs_out_on: 'x', alert_on: 'y' });
  assert.match(o.text, /Quer lembrete na hora de tomar\? Diga: me lembre de tomar Vitamina as 8h\./);
  o = run({ item: 'Losartana', needs_total: true, ask_total: true });
  assert.match(o.text, /Quantos comprimidos/); assert.deepEqual(JSON.parse(o.state), { kind: 'clarify', original: 'orig' });
  o = run({ item: 'Losartana', needs_total: true });
  assert.equal(o.text, 'Anotado: Losartana.'); assert.equal(o.state, '');
});

test('Resposta da compra: achou e nao achou', () => {
  const run = function (r) { return rodar1('Resposta da compra', { entrada: [{ r: r }], nos: IA }).text; };
  assert.equal(run({ found: true, item: 'Losartana', units_total: 30 }), 'Anotado! Recomecei a contagem de Losartana: 30 unidades. Paro de avisar da compra.');
  assert.equal(run({ found: true, item: 'Losartana' }), 'Anotado! Recomecei a contagem de Losartana. Paro de avisar da compra.');
  assert.match(run({ found: false }), /Nao achei esse item/);
});

test('Resposta do ajuste: rename, delete (botao sup_del) e ajuste de unidades', () => {
  const run = function (r) { return rodar1('Resposta do ajuste', { entrada: [{ r: r }], nos: IA }); };
  assert.equal(run({ action: 'rename', need_name: true }).text, 'Qual o novo nome do remedio?');
  assert.match(run({ action: 'rename', found: false }).text, /Nao achei um item para renomear/);
  assert.match(run({ action: 'rename', found: true, conflict: true, item: 'B' }).text, /Ja existe um item chamado B/);
  assert.equal(run({ action: 'rename', found: true, old_item: 'A', item: 'B', take_time: '08:00' }).text, 'Pronto: A agora se chama B (lembrete diario as 08:00 mantido).');
  let o = run({ action: 'delete', found: true, item: 'Sertralina', take_time: '09:00', sid: 4 });
  assert.equal(o.kb, 'sup_del'); assert.equal(o.rid, 4); assert.equal(o.text, 'Apagar Sertralina e o lembrete de tomar as 09:00?');
  assert.match(run({ action: 'delete', found: false }).text, /Nao achei esse remedio/);
  assert.equal(run({ found: true, item: 'X', units_left: 11.6, runs_out_on: 'd', alert_on: 'a' }).text, 'Ajustado: X - restam 12, acaba em d (aviso em a).');
  assert.match(run({ found: false }).text, /tenho 12 na cartela/);
});

test('Resposta das tarefas: nao conectado, criar (com prazo), listar, nao achada, concluida', () => {
  const run = function (r, a) { return rodar1('Resposta das tarefas', { entrada: [r], nos: { 'Interpretar resposta': [Object.assign({ chat_id: 111, title: 'Pagar IPTU' }, a)] } }).text; };
  assert.match(run({ not_connected: true }, {}), /tarefas do Google ainda nao estao conectadas/);
  assert.equal(run({}, { intent: 'create_task', task_due: '2026-11-13' }), 'Anotei na sua lista de tarefas: "Pagar IPTU" (prazo 13/11).');
  assert.equal(run({ title: 'Pagar o IPTU' }, { intent: 'create_task', task_due: '' }), 'Anotei na sua lista de tarefas: "Pagar o IPTU".');
  assert.equal(run({ tasks: [{ title: 'A', due: '2026-11-10' }, { title: 'B' }] }, { intent: 'list_tasks' }), ['Suas tarefas pendentes:', '- A (prazo 10/11)', '- B'].join(NL));
  assert.equal(run({ tasks: [] }, { intent: 'list_tasks' }), 'Voce nao tem tarefas pendentes.');
  assert.match(run({ not_found: true }, { intent: 'complete_task' }), /Nao achei uma tarefa pendente parecida com "Pagar IPTU"/);
  assert.equal(run({ title: 'Pagar IPTU' }, { intent: 'complete_task' }), 'Tarefa concluida: Pagar IPTU.');
});

test('Extras: Resposta das tarefas: lista de concluidas', () => {
  const run = function (r) { return rodar1('Extras: Resposta das tarefas', { entrada: [r], nos: IA }).text; };
  assert.match(run({ not_connected: true }), /nao estao conectadas/);
  assert.match(run({}), /Nao consegui consultar/);
  assert.equal(run({ closed: [] }), 'Nenhuma tarefa concluida desde segunda-feira.');
  assert.equal(run({ closed: [{ title: 'A' }] }), 'Voce concluiu 1 tarefa desde segunda-feira:' + NL + '- A');
  const muitas = Array.from({ length: 20 }, function (_, i) { return { title: 'T' + i }; });
  const t = run({ closed: muitas });
  assert.match(t, /^Voce concluiu 20 tarefas/); assert.equal(t.split(NL).length, 16); // titulo + 15
});

test('Resposta da dose: nao achou, sem acompanhamento, sem total, com total', () => {
  const run = function (r) { return rodar1('Resposta da dose', { entrada: [{ r: r }], nos: IA }).text; };
  assert.match(run({ found: false }), /Nao achei esse item/);
  assert.match(run({ found: true, tracking: false, item: 'X' }), /X ainda nao tem lembrete de tomar/);
  assert.match(run({ found: true, tracking: true, item: 'X', units_left: null }), /Quantos comprimidos/);
  assert.equal(run({ found: true, tracking: true, item: 'X', units_left: 9.4, runs_out_on: 'd' }), 'Anotado: tomou X. Restam 9 (acaba em d).');
});

test('Resposta do horario de tomar: parar, definir, pedir total', () => {
  const run = function (r) { return rodar1('Resposta do horario de tomar', { entrada: [{ r: r }], nos: IA }); };
  assert.match(run({ found: false }).text, /Nao achei esse item para parar/);
  assert.equal(run({ found: true, cleared: true, item: 'X' }).text, 'Parei os lembretes de tomar X. A contagem volta a seguir por dias.');
  let o = run({ found: true, item: 'X', kind: 'remedio', take_time: '08:00', units_left: 5, runs_out_on: 'd' });
  assert.match(o.text, /^Anotado: X \(remedio\)\. Lembro de tomar todo dia as 08:00/); assert.match(o.text, /Restam 5 e acaba em d\.$/);
  o = run({ found: true, item: 'X', take_time: '08:00', needs_total: true, ask_total: true });
  assert.equal(JSON.parse(o.state).kind, 'clarify');
});

test('Resposta da agenda: compromissos, lembretes, estoque e vazios; cai para a agenda da Maria', () => {
  const nos = function (ev, evMaria) {
    const n = { 'Interpretar resposta': [{ chat_id: 111, tz: 'America/Sao_Paulo', range_label: '09/11' }] };
    if (ev) { n['Agenda Adrian - listar'] = [{ events: ev }]; }
    if (evMaria) { n['Agenda Maria Clara - listar'] = [{ events: evMaria }]; }
    return n;
  };
  const r = { reminders: [{ due: '09/11 08:00', title: 'Agua' }], supplies: [{ item: 'Losartana', units_left: 3.4, runs_out_on: '12/11' }] };
  const o = rodar1('Resposta da agenda', { entrada: [{ r: r }], nos: nos([{ start: '2026-11-09T17:40:00-03:00', title: 'Consulta', location: 'Clinica' }, { all_day: true, title: 'Feriado' }]) });
  assert.equal(o.text, ['Sua agenda (09/11):', ['Compromissos:', '- 09/11 17:40  Consulta (Clinica)', '- dia todo  Feriado'].join(NL), ['Lembretes:', '- 09/11 08:00  Agua'].join(NL),
    ['Hora de comprar (diga "comprei" quando comprar):', '- Losartana: restam 3, acaba em 12/11'].join(NL)].join(NL + NL));
  const v = rodar1('Resposta da agenda', { entrada: [{}], nos: nos([], [{ start: '2026-11-10T09:00:00-03:00', title: 'Maria' }]) });
  assert.match(v.text, /- 10\/11 09:00  Maria/); assert.match(v.text, /Lembretes: nenhum\./);
  assert.match(rodar1('Resposta da agenda', { entrada: [{}], nos: nos() }).text, /Compromissos: nenhum\./);
});

test('Resposta do novo horario: repassa text e kb (rid sempre 0); padrao Ok.', () => {
  assert.deepEqual(rodar1('Resposta do novo horario', { entrada: [{}], nos: IA }), base({ text: 'Ok.' }));
  const o = rodar1('Resposta do novo horario', { entrada: [{ r: { text: 't', kb: 'lead', rid: 9 } }], nos: IA });
  assert.equal(o.kb, 'lead'); assert.equal(o.rid, 0);
});

test('Resposta das preferencias: so texto (kb none, rid 0)', () => {
  assert.equal(rodar1('Resposta das preferencias', { entrada: [{}], nos: IA }).text, 'Nao consegui salvar agora. Tente de novo.');
  const o = rodar1('Resposta das preferencias', { entrada: [{ r: { text: 'Salvo', kb: 'x', rid: 3 } }], nos: IA });
  assert.deepEqual(o, base({ text: 'Salvo' }));
});
