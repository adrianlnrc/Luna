'use strict';
// Executor local dos nos Code do workflow n8n (modo "Run Once for All Items"). Sem dependencias.
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const { DateTime } = require('./datetime');

const DEFAULT_WORKFLOW = path.join(__dirname, '..', 'modified.json');
const cache = new Map();

function loadWorkflow(file) {
  const f = file || DEFAULT_WORKFLOW;
  if (!cache.has(f)) { cache.set(f, JSON.parse(fs.readFileSync(f, 'utf8'))); }
  return cache.get(f);
}
function normItems(arr) {
  return (arr || []).map(function (it) { return (it && typeof it === 'object' && 'json' in it) ? it : { json: it }; });
}
function findNode(wf, name) {
  const n = wf.nodes.find(function (x) { return x.name === name; });
  if (!n) { throw new Error('No nao existe no workflow: ' + name); }
  return n;
}

// runCodeNode(workflow|caminho|null, 'Nome do no', { entrada, nosAnteriores, agora, timeoutMs, env, ctx })
// retorna os items de saida ({json: ...}[]). Entradas podem ser objetos simples (viram {json}).
function prepare(workflow, nodeName, opts, isAsync) {
  opts = opts || {};
  const wf = (workflow && workflow.nodes) ? workflow : loadWorkflow(workflow);
  const node = findNode(wf, nodeName);
  if (node.type !== 'n8n-nodes-base.code') { throw new Error('No nao e Code: ' + nodeName); }
  const code = node.parameters.jsCode;
  const input = normItems(opts.entrada);
  const prev = {};
  Object.keys(opts.nosAnteriores || {}).forEach(function (k) { prev[k] = normItems(opts.nosAnteriores[k]); });
  const fixedNow = opts.agora !== undefined ? new Date(opts.agora).getTime() : null;
  const realDate = Date;

  function ref(name) {
    if (!(name in prev)) { throw new Error("Node '" + name + "' hasn't been executed (nao fornecido em nosAnteriores)"); }
    const items = prev[name];
    return {
      first: function () { return items[0]; },
      last: function () { return items[items.length - 1]; },
      all: function () { return items.slice(); },
      item: items[0],
      isExecuted: true,
    };
  }
  const inputApi = { first: function () { return input[0]; }, last: function () { return input[input.length - 1]; }, all: function () { return input.slice(); }, item: input[0] };

  // Date congelado (new Date() e Date.now()) quando opts.agora e informado
  let SandDate = realDate;
  if (fixedNow !== null) {
    SandDate = class extends realDate {
      constructor(...a) { if (a.length === 0) { super(fixedNow); } else { super(...a); } }
      static now() { return fixedNow; }
    };
  }
  const sandbox = {
    $input: inputApi, $json: input[0] ? input[0].json : {}, $: ref,
    $items: function (name) { return name ? ref(name).all() : input.slice(); },
    $node: new Proxy({}, { get: function (_, k) { return { json: ref(String(k)).first().json }; } }),
    $env: opts.env || {}, $itemIndex: 0, $runIndex: 0,
    $now: DateTime.now(), $today: DateTime.now().startOf('day'),
    DateTime: DateTime, Date: SandDate, Buffer: Buffer,
    console: { log: function () {}, warn: function () {}, error: function () {} },
  };
  const helpers = {
    prepareBinaryData: async function (buf, fileName, mime) { return { data: Buffer.from(buf).toString('base64'), fileName: fileName, mimeType: mime }; },
  };
  const origNow = DateTime.now;
  const exec = function () {
    if (fixedNow !== null) { DateTime.now = function () { return new DateTime(fixedNow, 'UTC'); }; }
    sandbox.$now = DateTime.now(); sandbox.$today = sandbox.$now.startOf('day');
    const ctx = vm.createContext(sandbox);
    const fn = vm.runInContext('(' + (isAsync ? 'async ' : '') + 'function(){' + code + '\n})', ctx, { filename: nodeName, timeout: opts.timeoutMs || 2000 });
    return fn.call(Object.assign({ helpers: helpers }, opts.ctx || {}));
  };
  return { exec: exec, restore: function () { DateTime.now = origNow; } };
}
function runCodeNode(workflow, nodeName, opts) {
  const p = prepare(workflow, nodeName, opts, false);
  try { return finish(p.exec()); } finally { p.restore(); }
}
// Versao assincrona: aceita await no codigo (como o n8n); retorna Promise de items.
async function runCodeNodeAsync(workflow, nodeName, opts) {
  const p = prepare(workflow, nodeName, opts, true);
  try { return finish(await p.exec()); } finally { p.restore(); }
}
// Apenas compila (erro de sintaxe lanca). Usado no teste de contrato.
function compileCodeNode(workflow, nodeName) {
  const wf = (workflow && workflow.nodes) ? workflow : loadWorkflow(workflow);
  const node = findNode(wf, nodeName);
  return new vm.Script('(async function(){' + node.parameters.jsCode + '\n})', { filename: nodeName });
}
function codeNodeNames(workflow) {
  const wf = (workflow && workflow.nodes) ? workflow : loadWorkflow(workflow);
  return wf.nodes.filter(function (n) { return n.type === 'n8n-nodes-base.code'; }).map(function (n) { return n.name; });
}
function finish(out) {
  if (!Array.isArray(out)) { throw new Error('O no Code deve retornar um array de items'); }
  return out;
}
module.exports = { runCodeNode, runCodeNodeAsync, compileCodeNode, codeNodeNames, loadWorkflow, DateTime, DEFAULT_WORKFLOW };
