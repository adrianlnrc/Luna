'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { runCodeNode, loadWorkflow } = require('../../tools/n8n-gen/nodetest');

const WF = loadWorkflow(); // le (somente leitura) tools/n8n-gen/modified.json
const CASOS = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'natural', 'casos.json'), 'utf8')).casos;
const NL = String.fromCharCode(10);

function mensagem(id) {
  const c = CASOS.find(function (x) { return x.id === id; });
  if (!c) { throw new Error('caso nao existe: ' + id); }
  return c.mensagem;
}

// 2026-11-08 12:00 em Sao Paulo (domingo)
const AGORA = '2026-11-08T12:00:00-03:00';

// Resposta no formato da API Responses da OpenAI, com a saida estruturada do modelo em g
function respostaIA(g, usage) {
  return { output: [{ type: 'message', content: [{ type: 'output_text', text: JSON.stringify(g) }] }], usage: usage };
}

// Executa 'Interpretar resposta' com contexto sintetico
function interpretar(g, o) {
  o = o || {};
  const texto = o.texto !== undefined ? o.texto : (o.caso ? mensagem(o.caso) : '');
  const nos = {
    'Normalizar update': [{ chat_id: 111, kind: o.kind || 'text', text: texto, file_id: o.file_id }],
    'Buscar usuario': [Object.assign({ id: 7, name: 'Adrian', timezone: 'America/Sao_Paulo', places_txt: '' }, o.user || {})],
    'Montar pedido a IA': [Object.assign({ modelo: 'gpt-x', texto_atual: texto, state: null }, o.ctx || {})],
  };
  if (o.hist) { nos['Ler historico da conversa'] = [{ hist: JSON.stringify(o.hist) }]; }
  const entrada = o.cru !== undefined ? o.cru : respostaIA(g, o.usage);
  const out = runCodeNode(WF, 'Interpretar resposta', { entrada: [entrada], nosAnteriores: nos, agora: AGORA });
  return JSON.parse(JSON.stringify(out[0].json)); // normaliza objetos do vm (outro realm)
}

// Executa 'Preparar envio'. ia = saida de Interpretar resposta; multi = saida de 'Multi: consolidar'
function preparar(r, o) {
  o = o || {};
  const nos = { 'Interpretar resposta': [o.ia || {}] };
  if (o.multi) { nos['Multi: consolidar'] = [o.multi]; }
  if (o.mem) { nos['Memoria: gravar'] = [{ mem: o.mem }]; }
  return runCodeNode(WF, 'Preparar envio', { entrada: [Object.assign({ chat_id: 111 }, r)], nosAnteriores: nos, agora: AGORA })[0].json;
}

// Executa qualquer no Code e devolve o json normalizado de cada item de saida
function rodar(nome, o) {
  o = o || {};
  const out = runCodeNode(WF, nome, { entrada: o.entrada, nosAnteriores: o.nos, agora: o.agora || AGORA });
  return JSON.parse(JSON.stringify(out.map(function (i) { return i.json; })));
}
function rodar1(nome, o) { return rodar(nome, o)[0]; }

module.exports = { rodar, rodar1, WF, CASOS, NL, mensagem, interpretar, preparar, respostaIA, AGORA, runCodeNode };
