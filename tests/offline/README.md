# Testes offline dos nos Code

Rodam o JS dos nos `n8n-nodes-base.code` de `tools/n8n-gen/modified.json` (somente leitura) com o executor
`tools/n8n-gen/nodetest/` (ver o README de la). Sem rede, sem n8n, sem VPS.

```
node --test tests/offline
```

Data fixa dos testes: `2026-11-08T12:00:00-03:00` (domingo), fuso America/Sao_Paulo. Cada no e testado isolado com entradas
sinteticas (`helpers.js`); a mensagem de partida vem de `tests/natural/casos.json` quando ha caso equivalente.

## Cobertura (55 de 55 nos Code)

| Arquivo | Nos |
|---|---|
| `preparar-envio.test.js` | Preparar envio |
| `interpretar-resposta.test.js` | Interpretar resposta |
| `fluxo-telegram.test.js` | Normalizar update, Checar duplicado, Resposta do comando, Montar historico, Restaurar interpretacao |
| `respostas-simples.test.js` | Agenda: resposta da criacao / da gestao / do lembrete ligado / da acao, Agenda: sem calendario (acao), Extras: Resposta, Extras: Resposta das tarefas, Contatos: resposta, Docs: resposta, Listas: resposta, Projetos: Resposta, Correcao: resposta, Pesquisa: resposta, Importar agenda: resposta, Resposta do botao, Resposta do novo horario, Resposta das preferencias, Resposta do custo de IA, Resposta das financas, Resposta direta, Calendario nao conectado, Resposta do lembrete, Resposta do estoque novo, Resposta da compra, Resposta do ajuste, Resposta das tarefas, Resposta da dose, Resposta do horario de tomar, Resposta da agenda |
| `memoria-multi-lote.test.js` | Memoria: preparar, Memoria: resposta, Multi: preparar / expandir compromissos / expandir tarefas / sem calendario / concluir compromissos / concluir tarefas / consolidar, Lote: expandir exclusoes / sem calendario / concluir desfazer |
| `montar-pedido.test.js` | Montar pedido a IA (modelo, instrucoes, prompt, schema estrito, enum de intents), Importar agenda: montar pedido / normalizar / preparar conclusao, Docs: expandir, Docs: resposta final, Preparar PDF |
| `contrato.test.js` | todos: compilam no executor; nenhum depende de global nao emulado; todo no tem teste |

`contrato.test.js` falha se surgir um no Code novo sem teste (a deteccao esta em `cobertura.js`: o nome precisa ser alvo
de `rodar`/`runCodeNode`, linha da tabela `PADRAO` ou inicio de titulo de `test(...)`; aparecer so como "no anterior" nao conta).

Tambem ha dois testes de contrato sobre o prompt: o schema de `Montar pedido a IA` e o de `Importar agenda: montar pedido`
seguem o modo estrito da OpenAI (`required` == todas as chaves, `additionalProperties:false`, `null` declarado no enum), e
todo `intent` tratado no codigo de `Interpretar resposta` existe no enum do schema (exceto `invite_event` e `link_reminder`,
gerados pelo proprio codigo).

## Nao testaveis offline
Nenhum no Code ficou de fora. Ressalvas de fidelidade:
- **Preparar PDF**: usa `this.helpers.prepareBinaryData`, que no teste e um stub (base64 em memoria), entao so se verifica a
  montagem do binario (nome, mime, bytes), nao o armazenamento real do n8n.
- Nos nao Code (HTTP, Redis, Postgres, Telegram, Switch, IF, Execute Workflow, ex.: "Tipo de mensagem", "Lote: abrir") sao
  roteamento/I-O e nao tem JS proprio: ficam fora deste executor. Quem cobre o roteamento e `tests/natural/run.py` (n8n real).
- Os testes validam o JS dado o formato dos dados que os nos anteriores devolvem (assumido a partir do codigo); se um no de
  banco/API mudar o formato de `r`, estes testes nao percebem.
