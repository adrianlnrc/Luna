import { workflow, node, trigger, switchCase, splitInBatches, nextBatch, expr } from '@n8n/workflow-sdk';

const entrada = trigger({
  type: 'n8n-nodes-base.executeWorkflowTrigger', version: 1.1,
  config: { name: 'Receber pedido de projetos', position: [0, 400],
    parameters: { inputSource: 'workflowInputs', workflowInputs: { values: [{ name: 'owner', type: 'string' }, { name: 'ops', type: 'string' }] } } },
  output: [{ owner: 'adrian', ops: '[]' }]
});

const preparar = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Preparar operacoes', position: [224, 400], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "\nconst e = $input.first().json;\nlet ops = [];\ntry { ops = JSON.parse(String(e.ops || '[]')); } catch (x) { ops = []; }\nif (!Array.isArray(ops)) { ops = []; }\nconst owner = String(e.owner || '');\nconst out = ops.map(function (o, i) {\n  const conta = (owner === 'adrian' || owner === 'maria');\n  return { json: Object.assign({}, o, { seq: i, owner: owner, route: conta ? owner + '_' + String(o.op || '') : 'pular' }) };\n});\nif (!out.length) { out.push({ json: { op: 'noop', ref: 'noop', ver: 0, seq: 0, owner: owner, route: 'pular' } }); }\nreturn out;\n" } },
  output: [{ op: 'create', kind: 'project', ref: 'p:1', ver: 1, seq: 0, owner: 'adrian', route: 'adrian_create', title: 'Projeto', due: '2027-01-31', list: '@default' }]
});

const cada = splitInBatches({ version: 3, config: { name: 'Cada operacao', position: [448, 400], parameters: { batchSize: 1 } } });

const resolver = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Resolver pai', position: [672, 400], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "\nconst o = Object.assign({}, $input.first().json);\nlet pai = String(o.parent_gid || '');\nconst precisaPai = (o.op === 'create' && o.kind === 'task');\nif (precisaPai && !pai && o.parent_seq !== undefined && o.parent_seq !== null && Number(o.parent_seq) >= 0) {\n  try { pai = String($('Registrar resultado').all(0, Number(o.parent_seq))[0].json.gid || ''); } catch (x) { pai = ''; }\n}\no.parent_gid = pai;\no.due_iso = o.due ? String(o.due).slice(0, 10) + 'T00:00:00.000Z' : '';\nif (precisaPai && !pai) { o.route = 'pular'; o.skip_why = 'sem tarefa-pai no Google'; }\nreturn [{ json: o }];\n" } },
  output: [{ op: 'create', kind: 'project', ref: 'p:1', route: 'adrian_create', title: 'Projeto', due_iso: '2027-01-31T00:00:00.000Z', parent_gid: '' }]
});

const qual = switchCase({
  version: 3.4,
  config: { name: 'Qual conta e operacao?', position: [896, 400],
    parameters: { mode: 'rules', rules: { values: [
        { outputKey: 'adrian_create', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr('{{ $json.route }}'), operator: { type: 'string', operation: 'equals' }, rightValue: 'adrian_create' }], combinator: 'and' } },
        { outputKey: 'adrian_update', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr('{{ $json.route }}'), operator: { type: 'string', operation: 'equals' }, rightValue: 'adrian_update' }], combinator: 'and' } },
        { outputKey: 'adrian_delete', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr('{{ $json.route }}'), operator: { type: 'string', operation: 'equals' }, rightValue: 'adrian_delete' }], combinator: 'and' } },
        { outputKey: 'adrian_list', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr('{{ $json.route }}'), operator: { type: 'string', operation: 'equals' }, rightValue: 'adrian_list' }], combinator: 'and' } },
        { outputKey: 'maria_create', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr('{{ $json.route }}'), operator: { type: 'string', operation: 'equals' }, rightValue: 'maria_create' }], combinator: 'and' } },
        { outputKey: 'maria_update', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr('{{ $json.route }}'), operator: { type: 'string', operation: 'equals' }, rightValue: 'maria_update' }], combinator: 'and' } },
        { outputKey: 'maria_delete', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr('{{ $json.route }}'), operator: { type: 'string', operation: 'equals' }, rightValue: 'maria_delete' }], combinator: 'and' } },
        { outputKey: 'maria_list', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr('{{ $json.route }}'), operator: { type: 'string', operation: 'equals' }, rightValue: 'maria_list' }], combinator: 'and' } }
      ] }, options: { fallbackOutput: 'extra', renameFallbackOutput: 'pular' } } }
});

const g_adrian_create = node({
  type: 'n8n-nodes-base.googleTasks', version: 1,
  config: { name: "Criar no Google (Adrian)", position: [1344, 0], onError: 'continueRegularOutput', credentials: { googleTasksOAuth2Api: { id: 'DKxhC0O4U9SM1a9o', name: 'Google Tasks Adrian' } },
    parameters: { resource: 'task', operation: 'create', task: expr('{{ $json.list || "@default" }}'), title: expr('{{ $json.title }}'), additionalFields: { dueDate: expr('{{ $json.due_iso || undefined }}'), parent: expr('{{ $json.parent_gid || undefined }}') } } },
  output: [{ id: 'abc123', title: 'Projeto', status: 'needsAction' }]
});

const g_adrian_update = node({
  type: 'n8n-nodes-base.googleTasks', version: 1,
  config: { name: "Atualizar no Google (Adrian)", position: [1344, 160], onError: 'continueRegularOutput', credentials: { googleTasksOAuth2Api: { id: 'DKxhC0O4U9SM1a9o', name: 'Google Tasks Adrian' } },
    parameters: { resource: 'task', operation: 'update', task: expr('{{ $json.list || "@default" }}'), taskId: expr('{{ $json.gid }}'), updateFields: { title: expr('{{ $json.title }}'), dueDate: expr('{{ $json.due_iso || undefined }}'), status: expr('{{ $json.status || undefined }}') } } },
  output: [{ id: 'abc123', title: 'Projeto', status: 'completed' }]
});

const g_adrian_delete = node({
  type: 'n8n-nodes-base.googleTasks', version: 1,
  config: { name: "Apagar no Google (Adrian)", position: [1344, 320], onError: 'continueRegularOutput', credentials: { googleTasksOAuth2Api: { id: 'DKxhC0O4U9SM1a9o', name: 'Google Tasks Adrian' } },
    parameters: { resource: 'task', operation: 'delete', task: expr('{{ $json.list || "@default" }}'), taskId: expr('{{ $json.gid }}') } },
  output: [{ success: true }]
});

const g_adrian_list = node({
  type: 'n8n-nodes-base.googleTasks', version: 1,
  config: { name: "Ler concluidas no Google (Adrian)", position: [1344, 480], onError: 'continueRegularOutput', alwaysOutputData: true, credentials: { googleTasksOAuth2Api: { id: 'DKxhC0O4U9SM1a9o', name: 'Google Tasks Adrian' } },
    parameters: { resource: 'task', operation: 'getAll', task: '@default', returnAll: true, additionalFields: { showCompleted: true, showHidden: true, completedMin: expr('{{ $now.minus({ days: 14 }).toISO() }}') } } },
  output: [{ id: 'abc123', title: 'Tarefa', status: 'completed' }]
});

const g_maria_create = node({
  type: 'n8n-nodes-base.googleTasks', version: 1,
  config: { name: "Criar no Google (Maria Clara)", position: [1344, 640], onError: 'continueRegularOutput', credentials: { googleTasksOAuth2Api: { id: 'WRCKj8wdQ3ObvlSy', name: 'Google Tasks Maria Clara' } },
    parameters: { resource: 'task', operation: 'create', task: expr('{{ $json.list || "@default" }}'), title: expr('{{ $json.title }}'), additionalFields: { dueDate: expr('{{ $json.due_iso || undefined }}'), parent: expr('{{ $json.parent_gid || undefined }}') } } },
  output: [{ id: 'abc123', title: 'Projeto', status: 'needsAction' }]
});

const g_maria_update = node({
  type: 'n8n-nodes-base.googleTasks', version: 1,
  config: { name: "Atualizar no Google (Maria Clara)", position: [1344, 800], onError: 'continueRegularOutput', credentials: { googleTasksOAuth2Api: { id: 'WRCKj8wdQ3ObvlSy', name: 'Google Tasks Maria Clara' } },
    parameters: { resource: 'task', operation: 'update', task: expr('{{ $json.list || "@default" }}'), taskId: expr('{{ $json.gid }}'), updateFields: { title: expr('{{ $json.title }}'), dueDate: expr('{{ $json.due_iso || undefined }}'), status: expr('{{ $json.status || undefined }}') } } },
  output: [{ id: 'abc123', title: 'Projeto', status: 'completed' }]
});

const g_maria_delete = node({
  type: 'n8n-nodes-base.googleTasks', version: 1,
  config: { name: "Apagar no Google (Maria Clara)", position: [1344, 960], onError: 'continueRegularOutput', credentials: { googleTasksOAuth2Api: { id: 'WRCKj8wdQ3ObvlSy', name: 'Google Tasks Maria Clara' } },
    parameters: { resource: 'task', operation: 'delete', task: expr('{{ $json.list || "@default" }}'), taskId: expr('{{ $json.gid }}') } },
  output: [{ success: true }]
});

const g_maria_list = node({
  type: 'n8n-nodes-base.googleTasks', version: 1,
  config: { name: "Ler concluidas no Google (Maria Clara)", position: [1344, 1120], onError: 'continueRegularOutput', alwaysOutputData: true, credentials: { googleTasksOAuth2Api: { id: 'WRCKj8wdQ3ObvlSy', name: 'Google Tasks Maria Clara' } },
    parameters: { resource: 'task', operation: 'getAll', task: '@default', returnAll: true, additionalFields: { showCompleted: true, showHidden: true, completedMin: expr('{{ $now.minus({ days: 14 }).toISO() }}') } } },
  output: [{ id: 'abc123', title: 'Tarefa', status: 'completed' }]
});

const pular = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Pular operacao', position: [1344, 1300], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "\nconst o = $input.first().json;\nconst why = o.skip_why || (o.op === 'noop' ? '' : 'sem conta do Google ou operacao desconhecida');\nreturn [{ json: { skipped: true, error: why } }];\n" } },
  output: [{ skipped: true, error: '' }]
});

const registrar = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Registrar resultado', position: [1568, 600], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "\nconst o = $('Cada operacao').first().json;\nconst itens = $input.all().map(function (i) { return i.json || {}; });\nconst first = itens[0] || {};\nlet err = '';\nif (first.error) { err = (typeof first.error === 'string') ? first.error : String(first.error.message || JSON.stringify(first.error)); }\nconst base = { ref: o.ref || '', op: o.op || '', ver: o.ver || 0, seq: o.seq, ok: false, gid: '', done_ids: [], error: err.slice(0, 300) };\nif (first.skipped) { base.ok = (err === ''); return [{ json: base }]; }\nif (o.op === 'list') {\n  base.done_ids = itens.filter(function (t) { return t && t.id && t.status === 'completed'; }).map(function (t) { return t.id; });\n  base.ok = (err === '');\n} else if (o.op === 'create') {\n  base.gid = String(first.id || '');\n  base.ok = (err === '' && base.gid !== '');\n} else if (o.op === 'update') {\n  base.gid = String(o.gid || '');\n  base.ok = (err === '' && !!first.id);\n} else if (o.op === 'delete') {\n  base.gid = String(o.gid || '');\n  base.ok = (err === '' && first.success === true);\n}\nreturn [{ json: base }];\n" } },
  output: [{ ref: 'p:1', op: 'create', ver: 1, ok: true, gid: 'abc123', done_ids: [], error: '' }]
});

const final = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Resultado final', position: [672, 120], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "\nconst itens = $input.all().map(function (i) { return i.json; });\nreturn [{ json: { results: itens } }];\n" } },
  output: [{ results: [] }]
});

export default workflow('agente-projetos-google', 'Agente | Projetos Google')
  .add(entrada)
  .to(preparar)
  .to(cada
    .onDone(final)
    .onEachBatch(resolver.to(qual
      .onCase(0, g_adrian_create.to(registrar.to(nextBatch(cada))))
      .onCase(1, g_adrian_update.to(registrar))
      .onCase(2, g_adrian_delete.to(registrar))
      .onCase(3, g_adrian_list.to(registrar))
      .onCase(4, g_maria_create.to(registrar))
      .onCase(5, g_maria_update.to(registrar))
      .onCase(6, g_maria_delete.to(registrar))
      .onCase(7, g_maria_list.to(registrar))
      .onCase(8, pular.to(registrar)))));
