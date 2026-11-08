'use strict';
// Determina quais nos Code tem teste: o nome aparece como alvo de execucao (rodar/runCodeNode), como
// linha da tabela PADRAO, ou no inicio do titulo de um test(). Aparecer apenas como "no anterior" nao conta.
const fs = require('node:fs');
const path = require('node:path');

const NAO_TESTAVEIS = {
  // 'Nome do no': 'motivo' (vazio hoje: todos os nos Code sao executaveis offline; Preparar PDF roda com stub de binario)
};

function esc(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }
function cobertos(nomes) {
  const texto = fs.readdirSync(__dirname).filter(function (f) { return f.endsWith('.test.js'); })
    .map(function (f) { return fs.readFileSync(path.join(__dirname, f), 'utf8'); }).join('\n');
  const res = {};
  nomes.forEach(function (n) {
    const q = "'" + esc(n);
    const re = new RegExp("(rodar1?|runCodeNode(Async)?)\\((WF, )?" + q + "'|\\['" + esc(n) + "', |test\\(" + q + "[:' ]");
    res[n] = re.test(texto);
  });
  return res;
}
module.exports = { cobertos, NAO_TESTAVEIS };
