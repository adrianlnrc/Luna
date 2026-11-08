'use strict';
// Contrato: todos os nos Code do workflow compilam no executor e tem teste (ou motivo documentado).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { WF } = require('./helpers');
const { codeNodeNames, compileCodeNode, runCodeNodeAsync } = require('../../tools/n8n-gen/nodetest');
const { cobertos, NAO_TESTAVEIS } = require('./cobertura');

const NOMES = codeNodeNames(WF);

test('Contrato: o workflow tem nos Code com nomes unicos e jsCode nao vazio', () => {
  assert.ok(NOMES.length >= 55, 'esperava ao menos 55 nos Code, achei ' + NOMES.length);
  assert.equal(new Set(NOMES).size, NOMES.length);
  WF.nodes.filter(function (n) { return n.type === 'n8n-nodes-base.code'; }).forEach(function (n) {
    assert.ok(String(n.parameters.jsCode || '').trim().length > 0, n.name + ' sem jsCode');
    assert.ok(!n.parameters.mode || n.parameters.mode === 'runOnceForAllItems', n.name + ' usa modo nao suportado: ' + n.parameters.mode);
  });
});

NOMES.forEach(function (nome) {
  test('Contrato: compila no executor - ' + nome, () => { assert.doesNotThrow(function () { compileCodeNode(WF, nome); }); });
});

test('Contrato: com entrada vazia nenhum no Code lanca SyntaxError nem usa global nao emulado', async () => {
  for (const nome of NOMES) {
    try { await runCodeNodeAsync(WF, nome, { entrada: [{}], nosAnteriores: {} }); } catch (e) {
      // sem nos anteriores e esperado falhar ao ler dados ausentes (Node X hasn't been executed, TypeError); sintaxe/globais nunca
      assert.notEqual(e.name, 'SyntaxError', nome + ': ' + e.message);
      assert.ok(!/is not defined/.test(e.message), nome + ': global nao emulado: ' + e.message);
    }
  }
});

test('Contrato: todo no Code tem teste, ou motivo em NAO_TESTAVEIS e no README', () => {
  const cob = cobertos(NOMES);
  const readme = fs.readFileSync(path.join(__dirname, 'README.md'), 'utf8');
  const sem = NOMES.filter(function (n) { return !cob[n] && !NAO_TESTAVEIS[n]; });
  assert.deepEqual(sem, [], 'nos Code sem teste: ' + sem.join(', '));
  Object.keys(NAO_TESTAVEIS).forEach(function (n) { assert.ok(readme.includes(n), 'README deve explicar ' + n); assert.ok(NOMES.includes(n), 'NAO_TESTAVEIS cita no inexistente: ' + n); });
});
