'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { preparar, NL } = require('./helpers');

test('Preparar envio: texto simples vira html escapado e sem **', () => {
  const o = preparar({ text: 'Fica **combinado** <b> & ok' });
  assert.equal(o.text, 'Fica **combinado** <b> & ok');
  assert.equal(o.html, 'Fica combinado &lt;b&gt; &amp; ok');
  assert.equal(o.kb, 'none'); assert.equal(o.rid, 0); assert.equal(o.state, ''); assert.equal(o.chat_id, 111);
});

test('Preparar envio: texto vazio vira Ok. e texto longo e cortado em 3900', () => {
  assert.equal(preparar({}).text, 'Ok.');
  const longo = preparar({ text: 'a'.repeat(5000) }).text;
  assert.equal(longo.length, 3903); assert.ok(longo.endsWith('...'));
});

test('Preparar envio: varias acoes -> Feito: com bullets e botao Desfazer tudo', () => {
  const o = preparar({ text: 'Lembrete criado.' }, {
    ia: { intent: 'create_reminder' },
    multi: { multi_lines: ['Evento: dentista 09:00', 'Gasto: uber R$ 50'], multi_fails: [], multi_ask: [], batch_id: 42 },
  });
  assert.equal(o.text, ['Feito:', '- Lembrete criado.', '- Evento: dentista 09:00', '- Gasto: uber R$ 50'].join(NL));
  assert.equal(o.kb, 'multi_undo'); assert.equal(o.rid, 42);
});

test('Preparar envio: principal com pergunta nao entra nos bullets', () => {
  const o = preparar({ text: 'Que horas?' }, { ia: { intent: 'create_reminder' }, multi: { multi_lines: ['Gasto: uber'], batch_id: 5 } });
  assert.equal(o.text, ['Feito:', '- Gasto: uber', '', 'Que horas?'].join(NL));
  assert.equal(o.kb, 'multi_undo');
});

test('Preparar envio: falhas e perguntas pendentes geram estado clarify', () => {
  const o = preparar({ text: 'Ok.' }, { ia: { intent: 'create_event' }, multi: { multi_lines: ['Gasto: uber'], multi_fails: ['Nao consegui: leite'], multi_ask: ['a hora'], batch_id: 0 } });
  assert.match(o.text, /Nao consegui: leite/);
  assert.match(o.text, /Faltou saber a hora\. Me diz que eu faço\./);
  assert.equal(JSON.parse(o.state).kind, 'clarify');
  assert.equal(o.kb, 'none'); // batch_id 0: sem Desfazer
});

test('Preparar envio: nao sobrescreve state existente nem kb nao-none', () => {
  const o = preparar({ text: 'x', kb: 'undo', rid: 9, state: 'S' }, { ia: { intent: 'create_event' }, multi: { multi_lines: ['a'], multi_ask: ['b'], batch_id: 3 } });
  assert.equal(o.state, 'S'); assert.equal(o.kb, 'undo'); assert.equal(o.rid, 9);
});

test('Preparar envio: unsupported_note, social_event e extra_requests', () => {
  let o = preparar({ text: 'Criado.' }, { ia: { intent: 'create_event', unsupported_note: 'Nao reservo mesa.' } });
  assert.equal(o.text, 'Criado.' + NL + NL + 'Nao reservo mesa.');
  o = preparar({ text: 'Criado.' }, { ia: { intent: 'create_event', social_event: true } });
  assert.equal(o.text, 'Criado.' + NL + 'Quer chamar alguém?');
  o = preparar({ text: 'Criado.' }, { ia: { intent: 'chat', extra_requests: 'pagar o IPTU,' } });
  assert.equal(o.text, 'Criado.' + NL + NL + 'Também vi: pagar o IPTU. Me manda isso separado que eu faço.');
  o = preparar({ text: 'Criado.' }, { ia: { intent: 'chat', extra_requests: 'nenhum' } });
  assert.equal(o.text, 'Criado.');
});

test('Preparar envio: memoria gravada anexa Anotei:, e so-fato substitui o texto', () => {
  const mem = [{ ok: true, text: 'Anotei: sogra e Dona Marta' }, { ok: true, duplicate: true, text: 'x' }];
  let o = preparar({ text: 'Ok.' }, { ia: { intent: 'create_task' }, mem });
  assert.equal(o.text, 'Ok.' + NL + 'Anotei: sogra e Dona Marta');
  o = preparar({ text: 'Ok.' }, { ia: { intent: 'chat', reply: '' }, mem });
  assert.equal(o.text, 'Anotei: sogra e Dona Marta');
  o = preparar({ text: 'Ok.' }, { ia: { intent: 'chat', reply: '' }, mem: [{ duplicate: true }] });
  assert.equal(o.text, 'Já estava anotado.');
  o = preparar({ text: 'Ok.' }, { ia: { intent: 'memory_manage' }, mem });
  assert.equal(o.text, 'Ok.');
});
