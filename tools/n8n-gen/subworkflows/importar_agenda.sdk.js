import { workflow, node, trigger, ifElse, expr } from '@n8n/workflow-sdk';

// Agente | Importar agenda: cria em lote os compromissos (Google Agenda) e as tarefas (Google Tarefas) de um rascunho confirmado.
// Entradas (todas string): draft_id, calendar_key (adrian|maria), eventos (JSON [{summary,start,end,no_reminders}]), tarefas (JSON [{title,due}]).
// Saida (1 item): { draft_id, events_ok, events_fail, tasks_ok, tasks_fail, errors[] }. Nunca derruba a execucao (onError continua).
// Usa os sub-workflows existentes: Agenda Adrian bBJo78YVQ1cOMX09, Agenda Maria Clara 6bXuicjujajBuXbd, Tarefas dnVm8cfVhpqXGWmr.
const AGENDA_ADRIAN = 'bBJo78YVQ1cOMX09';
const AGENDA_MARIA = '6bXuicjujajBuXbd';
const TAREFAS = 'dnVm8cfVhpqXGWmr';

const entrada = trigger({
  type: 'n8n-nodes-base.executeWorkflowTrigger', version: 1.1,
  config: { name: 'Receber importacao', position: [0, 300], parameters: { inputSource: 'workflowInputs', workflowInputs: { values: [
    { name: 'draft_id', type: 'string' }, { name: 'calendar_key', type: 'string' }, { name: 'eventos', type: 'string' }, { name: 'tarefas', type: 'string' }
  ] } } },
  output: [{ draft_id: '1', calendar_key: 'adrian', eventos: '[]', tarefas: '[]' }]
});

const separarEventos = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Separar eventos', position: [224, 300], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "\nconst e = $input.first().json;\nlet lista = [];\ntry { lista = JSON.parse(e.eventos || '[]'); } catch (err) { lista = []; }\nconst cal = String(e.calendar_key || '');\nif (!lista.length) { return [{ json: { skip: true, sem_cal: false, calendar_key: cal } }]; }\nif (cal !== 'adrian' && cal !== 'maria') { return [{ json: { skip: true, sem_cal: true, calendar_key: cal } }]; }\nreturn lista.map(function (x) {\n  return { json: { skip: false, sem_cal: false, calendar_key: cal, action: 'create', summary: String(x.summary || ''), start: String(x.start || ''), end: String(x.end || ''),\n    location: '', attendees: '', event_id: '', send_updates: 'none', force: 'true', meet: 'false', repeat_freq: '', repeat_until: '', repeat_count: '', response: '', no_reminders: (x.no_reminders === true ? 'true' : 'false') } };\n});\n" } },
  output: [{ skip: false, calendar_key: 'adrian', action: 'create' }]
});

const temEventos = ifElse({
  version: 2.2,
  config: { name: 'Tem eventos?', position: [448, 300],
    parameters: { conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
      conditions: [{ leftValue: expr('{{ $json.skip }}'), operator: { type: 'boolean', operation: 'false', singleValue: true }, rightValue: '' }],
      combinator: 'and' } } }
});

const ehMaria = ifElse({
  version: 2.2,
  config: { name: 'Agenda da Maria?', position: [672, 200],
    parameters: { conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' },
      conditions: [{ leftValue: expr('{{ $json.calendar_key }}'), operator: { type: 'string', operation: 'equals' }, rightValue: 'maria' }],
      combinator: 'and' } } }
});

const EV_VALUES = {
  action: expr('{{ $json.action }}'), summary: expr('{{ $json.summary }}'), start: expr('{{ $json.start }}'), end: expr('{{ $json.end }}'),
  location: '', attendees: '', event_id: '', send_updates: 'none', force: 'true', meet: 'false', repeat_freq: '', repeat_until: '', repeat_count: '', response: '', no_reminders: expr('{{ $json.no_reminders }}')
};

const criarMaria = node({
  type: 'n8n-nodes-base.executeWorkflow', version: 1.3,
  config: { name: 'Criar na agenda da Maria', position: [896, 100], onError: 'continueRegularOutput',
    parameters: { source: 'database', mode: 'each', workflowId: { __rl: true, mode: 'id', value: AGENDA_MARIA },
      workflowInputs: { mappingMode: 'defineBelow', value: EV_VALUES } } },
  output: [{ ok: true, event_id: 'abc' }]
});

const criarAdrian = node({
  type: 'n8n-nodes-base.executeWorkflow', version: 1.3,
  config: { name: 'Criar na agenda do Adrian', position: [896, 300], onError: 'continueRegularOutput',
    parameters: { source: 'database', mode: 'each', workflowId: { __rl: true, mode: 'id', value: AGENDA_ADRIAN },
      workflowInputs: { mappingMode: 'defineBelow', value: EV_VALUES } } },
  output: [{ ok: true, event_id: 'abc' }]
});

const juntarEventos = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Juntar eventos', position: [1120, 300], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "\nconst itens = $input.all().map(function (i) { return i.json || {}; });\nlet ok = 0;\nlet fail = 0;\nconst errors = [];\nitens.forEach(function (j) {\n  if (j.skip) {\n    if (j.sem_cal) { fail += 1; errors.push('evento: calendario nao conectado'); }\n    return;\n  }\n  if (j.ok === true && j.event_id) { ok += 1; }\n  else { fail += 1; errors.push('evento: ' + String(j.error || 'falha ao criar').slice(0, 100)); }\n});\nreturn [{ json: { ok: ok, fail: fail, errors: errors } }];\n" } },
  output: [{ ok: 1, fail: 0, errors: [] }]
});

const separarTarefas = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Separar tarefas', position: [1344, 300], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "\nconst e = $('Receber importacao').first().json;\nlet lista = [];\ntry { lista = JSON.parse(e.tarefas || '[]'); } catch (err) { lista = []; }\nconst cal = String(e.calendar_key || '');\nif (!lista.length || (cal !== 'adrian' && cal !== 'maria')) { return [{ json: { skip: true, sem_cal: lista.length > 0 } }]; }\nreturn lista.map(function (x) {\n  return { json: { skip: false, sem_cal: false, calendar_key: cal, action: 'add', title: String(x.title || ''), due: String(x.due || '') } };\n});\n" } },
  output: [{ skip: false, calendar_key: 'adrian', action: 'add', title: 't', due: '2026-11-03' }]
});

const temTarefas = ifElse({
  version: 2.2,
  config: { name: 'Tem tarefas?', position: [1568, 300],
    parameters: { conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
      conditions: [{ leftValue: expr('{{ $json.skip }}'), operator: { type: 'boolean', operation: 'false', singleValue: true }, rightValue: '' }],
      combinator: 'and' } } }
});

const criarTarefas = node({
  type: 'n8n-nodes-base.executeWorkflow', version: 1.3,
  config: { name: 'Criar tarefas no Google', position: [1792, 200], onError: 'continueRegularOutput',
    parameters: { source: 'database', mode: 'each', workflowId: { __rl: true, mode: 'id', value: TAREFAS },
      workflowInputs: { mappingMode: 'defineBelow', value: {
        calendar_key: expr('{{ $json.calendar_key }}'), action: expr('{{ $json.action }}'), title: expr('{{ $json.title }}'), due: expr('{{ $json.due }}') } } } },
  output: [{ id: 'abc', title: 't' }]
});

const resultado = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Resultado', position: [2016, 300], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "\nconst e = $('Receber importacao').first().json;\nconst ev = $('Juntar eventos').first().json;\nconst itens = $input.all().map(function (i) { return i.json || {}; });\nlet ok = 0;\nlet fail = 0;\nconst errors = (ev.errors || []).slice();\nitens.forEach(function (j) {\n  if (j.skip) {\n    if (j.sem_cal) { fail += 1; errors.push('tarefa: conta de tarefas nao conectada'); }\n    return;\n  }\n  if (j.id) { ok += 1; }\n  else {\n    fail += 1;\n    let motivo = 'falha ao criar';\n    if (j.not_connected) { motivo = 'conta de tarefas nao conectada'; }\n    else if (j.error) { motivo = (typeof j.error === 'string') ? j.error : (j.error.message || 'falha ao criar'); }\n    errors.push('tarefa: ' + String(motivo).slice(0, 100));\n  }\n});\nreturn [{ json: { draft_id: e.draft_id, events_ok: ev.ok || 0, events_fail: ev.fail || 0, tasks_ok: ok, tasks_fail: fail, errors: errors.slice(0, 10) } }];\n" } },
  output: [{ draft_id: '1', events_ok: 1, events_fail: 0, tasks_ok: 1, tasks_fail: 0, errors: [] }]
});

export default workflow('agente-importar-agenda', 'Agente | Importar agenda')
  .add(entrada)
  .to(separarEventos)
  .to(temEventos
    .onTrue(ehMaria
      .onTrue(criarMaria.to(juntarEventos))
      .onFalse(criarAdrian.to(juntarEventos)))
    .onFalse(juntarEventos))
  .add(juntarEventos)
  .to(separarTarefas)
  .to(temTarefas
    .onTrue(criarTarefas.to(resultado))
    .onFalse(resultado));
