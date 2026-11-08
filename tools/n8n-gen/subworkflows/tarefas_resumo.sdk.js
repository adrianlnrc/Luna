import { workflow, node, trigger, switchCase, expr } from '@n8n/workflow-sdk';

// Agente | Tarefas do resumo: le as tarefas ABERTAS do Google Tarefas e devolve { tasks: [{id,title,due,parent,project}] }.
// Subtarefa (tem tarefa-mae na lista) vira { project: titulo da mae }; a tarefa-mae que tem subtarefas sai da lista (e um projeto, nao tarefa).
// Entrada: calendar_key (adrian|maria). Sem conta -> { not_connected: true, tasks: [] }.
const entrada = trigger({
  type: 'n8n-nodes-base.executeWorkflowTrigger', version: 1.1,
  config: { name: 'Receber pedido', position: [0, 300], parameters: { inputSource: 'workflowInputs', workflowInputs: { values: [{ name: 'calendar_key', type: 'string' }] } } },
  output: [{ calendar_key: 'adrian' }]
});

const qualConta = switchCase({
  version: 3.4,
  config: { name: 'Qual conta?', position: [224, 300],
    parameters: { mode: 'rules', rules: { values: [
      { outputKey: 'adrian', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr('{{ $json.calendar_key }}'), operator: { type: 'string', operation: 'equals' }, rightValue: 'adrian' }], combinator: 'and' } },
      { outputKey: 'maria', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr('{{ $json.calendar_key }}'), operator: { type: 'string', operation: 'equals' }, rightValue: 'maria' }], combinator: 'and' } }
    ] }, options: { fallbackOutput: 'extra', renameFallbackOutput: 'sem conta' } } }
});

const lerAdrian = node({
  type: 'n8n-nodes-base.googleTasks', version: 1,
  config: { name: 'Ler tarefas (Adrian)', position: [448, 200], alwaysOutputData: true, credentials: { googleTasksOAuth2Api: { id: 'DKxhC0O4U9SM1a9o', name: 'Google Tasks Adrian' } },
    parameters: { resource: 'task', operation: 'getAll', task: '@default', returnAll: true, additionalFields: { showCompleted: false } } },
  output: [{ id: 'a', title: 't', status: 'needsAction' }]
});

const lerMaria = node({
  type: 'n8n-nodes-base.googleTasks', version: 1,
  config: { name: 'Ler tarefas (Maria Clara)', position: [448, 400], alwaysOutputData: true, credentials: { googleTasksOAuth2Api: { id: 'WRCKj8wdQ3ObvlSy', name: 'Google Tasks Maria Clara' } },
    parameters: { resource: 'task', operation: 'getAll', task: '@default', returnAll: true, additionalFields: { showCompleted: false } } },
  output: [{ id: 'a', title: 't', status: 'needsAction' }]
});

const semConta = node({
  type: 'n8n-nodes-base.set', version: 3.4,
  config: { name: 'Sem conta de tarefas', position: [448, 600], parameters: { mode: 'manual', includeOtherFields: false, assignments: { assignments: [
    { id: 'n1', name: 'not_connected', value: true, type: 'boolean' }, { id: 'n2', name: 'tasks', value: '=[]', type: 'array' }] } } },
  output: [{ not_connected: true, tasks: [] }]
});

const montar = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Montar lista', position: [672, 300], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "const todas = $input.all().map(function (i) { return i.json; }).filter(function (t) { return t && t.id && t.title && t.status !== 'completed'; });\nconst porId = {};\ntodas.forEach(function (t) { porId[t.id] = t; });\nconst maes = {};\ntodas.forEach(function (t) { if (t.parent && porId[t.parent]) { maes[t.parent] = true; } });\nconst tasks = [];\ntodas.forEach(function (t) {\n  if (maes[t.id]) { return; }\n  const mae = (t.parent && porId[t.parent]) ? porId[t.parent] : null;\n  tasks.push({ id: t.id, title: t.title, due: t.due ? String(t.due).slice(0, 10) : '', parent: t.parent || '', project: mae ? mae.title : '' });\n});\nreturn [{ json: { not_connected: false, tasks: tasks } }];" } },
  output: [{ not_connected: false, tasks: [] }]
});

export default workflow('agente-tarefas-resumo', 'Agente | Tarefas do resumo')
  .add(entrada)
  .to(qualConta
    .onCase(0, lerAdrian.to(montar))
    .onCase(1, lerMaria.to(montar))
    .onCase(2, semConta));
