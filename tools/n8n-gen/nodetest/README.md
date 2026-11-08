# nodetest: executor local dos nos Code do n8n

Roda o `parameters.jsCode` de um no `n8n-nodes-base.code` (modo "Run Once for All Items") em `vm`, sem rede e sem dependencias.
Por padrao le `tools/n8n-gen/modified.json` (somente leitura).

```js
const { runCodeNode } = require('./tools/n8n-gen/nodetest');
const saida = runCodeNode(null /* ou workflow ja carregado / objeto */, 'Preparar envio', {
  entrada: [{ chat_id: 1, text: 'oi' }],                    // $input (objetos viram {json})
  nosAnteriores: { 'Interpretar resposta': [{ intent: 'chat' }] },  // $('Nome')
  agora: '2026-11-08T12:00:00-03:00',                        // congela Date.now()/new Date()/DateTime.now()
  timeoutMs: 2000,
});                                                           // -> [{ json: ... }]
```

Rodar os testes: `node --test tests/offline`

## Emula
- `$input.first()/last()/all()/item`, `$json`, `$('Nome').first()/last()/all()/item` (no nao informado em `nosAnteriores` lanca erro como o n8n; o codigo costuma proteger com try/catch), `$items()`, `$node['Nome'].json`, `$env`, `$now`, `$today`.
- `DateTime` (subconjunto proprio de Luxon via Intl, com fuso): `now`, `fromISO`, `setZone`, `setLocale('pt-BR')`, `plus/minus` (days, weeks, months, years, hours, minutes, seconds), `startOf` (day/week/month/hour/minute; semana comeca na segunda), `toISO`, `toUTC`, `toMillis`, `isValid`, comparacao `<`/`>`, `toFormat` com `yyyy MM dd HH mm ss ccc cccc` e literais entre aspas simples.
- `this.helpers.prepareBinaryData` (stub simples), `console` mudo, `Buffer`. `runCodeNodeAsync` aceita `await` no codigo (use para "Preparar PDF"); `runCodeNode` e sincrono. `compileCodeNode` so compila e `codeNodeNames` lista os nos Code.
- Retorno validado como array de items.

## Nao emula
- Nos que nao sao Code (HTTP, Redis, Postgres, Telegram, IF/Switch, Execute Workflow) e o fluxo entre nos: cada no e testado isolado com entradas sinteticas.
- Luxon completo (outros tokens de formato, `diff`, `set`, locales alem do Intl do Node), `$helpers.httpRequest`, `$getWorkflowStaticData`, `$execution`, `$workflow`, `$vars`, modo "Run Once for Each Item", `require` de modulos, binarios reais (o stub devolve base64).
- Idiossincrasias do sandbox do n8n (task runner): o codigo roda no `vm` do Node local, com `Date`, `JSON`, `RegExp` etc. proprios do contexto. Objetos retornados vem de outro realm; normalize com `JSON.parse(JSON.stringify(x))` antes de `deepStrictEqual`.
