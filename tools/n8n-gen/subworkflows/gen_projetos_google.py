import json, os, re, sys
# Gera 3 arquivos SDK (n8n) do espelho dos PROJETOS no Google Tarefas:
#   projetos_google.sdk.js        sub-workflow NOVO "Agente | Projetos Google" (cria/atualiza/apaga/le no Google Tarefas)
#   projetos_backfill.sdk.js      workflow NOVO "Agente | Projetos backfill" (gatilho manual; cria no Google o que ainda nao tem google_task_id)
#   disparador_projetos.sdk.js    Disparador COMPLETO (rGQRFihojnaUZHdG) = disparador.sdk.js + reconciliacao/reenvio antes do resumo
# O id do sub-workflow novo entra pela variavel de ambiente PROJ_GOOGLE_WF_ID (ou edite a constante abaixo).
# Sem segredos: so ids de credencial (iguais aos do sub-workflow "Agente | Tarefas").
HERE = os.path.dirname(os.path.abspath(__file__))
WF_ID = os.environ.get('PROJ_GOOGLE_WF_ID', 'TROCAR_PELO_ID_DO_SUBWORKFLOW_PROJETOS_GOOGLE')
if WF_ID.startswith('TROCAR'):
    print('AVISO: PROJ_GOOGLE_WF_ID nao definido; os arquivos saem com o id de mentira', WF_ID, file=sys.stderr)

PG = "credentials: { postgres: { id: '1xCdaqn8KYskDi8x', name: 'Postgres Agente' } }"
GT = {'adrian': "credentials: { googleTasksOAuth2Api: { id: 'DKxhC0O4U9SM1a9o', name: 'Google Tasks Adrian' } }",
      'maria': "credentials: { googleTasksOAuth2Api: { id: 'WRCKj8wdQ3ObvlSy', name: 'Google Tasks Maria Clara' } }"}

def js(s):
    s = str(s)
    assert '`' not in s and '${' not in s and '\\' not in s, 'perigo no codigo JS: ' + s[:60]
    return json.dumps(s, ensure_ascii=False)

# ---------------------------------------------------------------- codigo dos nos Code
PREPARAR = r"""
const e = $input.first().json;
let ops = [];
try { ops = JSON.parse(String(e.ops || '[]')); } catch (x) { ops = []; }
if (!Array.isArray(ops)) { ops = []; }
const owner = String(e.owner || '');
const out = ops.map(function (o, i) {
  const conta = (owner === 'adrian' || owner === 'maria');
  return { json: Object.assign({}, o, { seq: i, owner: owner, route: conta ? owner + '_' + String(o.op || '') : 'pular' }) };
});
if (!out.length) { out.push({ json: { op: 'noop', ref: 'noop', ver: 0, seq: 0, owner: owner, route: 'pular' } }); }
return out;
"""

RESOLVER = r"""
const o = Object.assign({}, $input.first().json);
let pai = String(o.parent_gid || '');
const precisaPai = (o.op === 'create' && o.kind === 'task');
if (precisaPai && !pai && o.parent_seq !== undefined && o.parent_seq !== null && Number(o.parent_seq) >= 0) {
  try { pai = String($('Registrar resultado').all(0, Number(o.parent_seq))[0].json.gid || ''); } catch (x) { pai = ''; }
}
o.parent_gid = pai;
o.due_iso = o.due ? String(o.due).slice(0, 10) + 'T00:00:00.000Z' : '';
if (precisaPai && !pai) { o.route = 'pular'; o.skip_why = 'sem tarefa-pai no Google'; }
return [{ json: o }];
"""

PULAR = r"""
const o = $input.first().json;
const why = o.skip_why || (o.op === 'noop' ? '' : 'sem conta do Google ou operacao desconhecida');
return [{ json: { skipped: true, error: why } }];
"""

REGISTRAR = r"""
const o = $('Cada operacao').first().json;
const itens = $input.all().map(function (i) { return i.json || {}; });
const first = itens[0] || {};
let err = '';
if (first.error) { err = (typeof first.error === 'string') ? first.error : String(first.error.message || JSON.stringify(first.error)); }
const base = { ref: o.ref || '', op: o.op || '', ver: o.ver || 0, seq: o.seq, ok: false, gid: '', done_ids: [], error: err.slice(0, 300) };
if (first.skipped) { base.ok = (err === ''); return [{ json: base }]; }
if (o.op === 'list') {
  base.done_ids = itens.filter(function (t) { return t && t.id && t.status === 'completed'; }).map(function (t) { return t.id; });
  base.ok = (err === '');
} else if (o.op === 'create') {
  base.gid = String(first.id || '');
  base.ok = (err === '' && base.gid !== '');
} else if (o.op === 'update') {
  base.gid = String(o.gid || '');
  base.ok = (err === '' && !!first.id);
} else if (o.op === 'delete') {
  base.gid = String(o.gid || '');
  base.ok = (err === '' && first.success === true);
}
return [{ json: base }];
"""

FINAL = r"""
const itens = $input.all().map(function (i) { return i.json; });
return [{ json: { results: itens } }];
"""

# ---------------------------------------------------------------- sub-workflow
def google_nodes():
    out = []; names = {}
    y = 0
    for conta, rotulo in (('adrian', 'Adrian'), ('maria', 'Maria Clara')):
        c = GT[conta]
        defs = [
         ('create', 'Criar no Google (%s)' % rotulo,
          "{ resource: 'task', operation: 'create', task: expr('{{ $json.list || \"@default\" }}'), title: expr('{{ $json.title }}'), additionalFields: { dueDate: expr('{{ $json.due_iso || undefined }}'), parent: expr('{{ $json.parent_gid || undefined }}') } }",
          "[{ id: 'abc123', title: 'Projeto', status: 'needsAction' }]", False),
         ('update', 'Atualizar no Google (%s)' % rotulo,
          "{ resource: 'task', operation: 'update', task: expr('{{ $json.list || \"@default\" }}'), taskId: expr('{{ $json.gid }}'), updateFields: { title: expr('{{ $json.title }}'), dueDate: expr('{{ $json.due_iso || undefined }}'), status: expr('{{ $json.status || undefined }}') } }",
          "[{ id: 'abc123', title: 'Projeto', status: 'completed' }]", False),
         ('delete', 'Apagar no Google (%s)' % rotulo,
          "{ resource: 'task', operation: 'delete', task: expr('{{ $json.list || \"@default\" }}'), taskId: expr('{{ $json.gid }}') }",
          "[{ success: true }]", False),
         ('list', 'Ler concluidas no Google (%s)' % rotulo,
          "{ resource: 'task', operation: 'getAll', task: '@default', returnAll: true, additionalFields: { showCompleted: true, showHidden: true, completedMin: expr('{{ $now.minus({ days: 14 }).toISO() }}') } }",
          "[{ id: 'abc123', title: 'Tarefa', status: 'completed' }]", True),
        ]
        for op, name, params, sample, always in defs:
            var = 'g_%s_%s' % (conta, op)
            extra = ", alwaysOutputData: true" if always else ""
            out.append("const %s = node({\n  type: 'n8n-nodes-base.googleTasks', version: 1,\n  config: { name: %s, position: [1344, %d], onError: 'continueRegularOutput'%s, %s,\n    parameters: %s },\n  output: %s\n});\n" % (var, js(name), y, extra, c, params, sample))
            names[(conta, op)] = var
            y += 160
    return '\n'.join(out), names

def switch_rules():
    rules = []
    for conta in ('adrian', 'maria'):
        for op in ('create', 'update', 'delete', 'list'):
            k = conta + '_' + op
            rules.append("{ outputKey: '%s', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr('{{ $json.route }}'), operator: { type: 'string', operation: 'equals' }, rightValue: '%s' }], combinator: 'and' } }" % (k, k))
    return ',\n        '.join(rules)

def subworkflow():
    g, nm = google_nodes()
    head = "import { workflow, node, trigger, switchCase, splitInBatches, nextBatch, expr } from '@n8n/workflow-sdk';\n"
    body = """
const entrada = trigger({
  type: 'n8n-nodes-base.executeWorkflowTrigger', version: 1.1,
  config: { name: 'Receber pedido de projetos', position: [0, 400],
    parameters: { inputSource: 'workflowInputs', workflowInputs: { values: [{ name: 'owner', type: 'string' }, { name: 'ops', type: 'string' }] } } },
  output: [{ owner: 'adrian', ops: '[]' }]
});

const preparar = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Preparar operacoes', position: [224, 400], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: %s } },
  output: [{ op: 'create', kind: 'project', ref: 'p:1', ver: 1, seq: 0, owner: 'adrian', route: 'adrian_create', title: 'Projeto', due: '2027-01-31', list: '@default' }]
});

const cada = splitInBatches({ version: 3, config: { name: 'Cada operacao', position: [448, 400], parameters: { batchSize: 1 } } });

const resolver = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Resolver pai', position: [672, 400], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: %s } },
  output: [{ op: 'create', kind: 'project', ref: 'p:1', route: 'adrian_create', title: 'Projeto', due_iso: '2027-01-31T00:00:00.000Z', parent_gid: '' }]
});

const qual = switchCase({
  version: 3.4,
  config: { name: 'Qual conta e operacao?', position: [896, 400],
    parameters: { mode: 'rules', rules: { values: [
        %s
      ] }, options: { fallbackOutput: 'extra', renameFallbackOutput: 'pular' } } }
});

%s
const pular = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Pular operacao', position: [1344, 1300], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: %s } },
  output: [{ skipped: true, error: '' }]
});

const registrar = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Registrar resultado', position: [1568, 600], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: %s } },
  output: [{ ref: 'p:1', op: 'create', ver: 1, ok: true, gid: 'abc123', done_ids: [], error: '' }]
});

const final = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Resultado final', position: [672, 120], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: %s } },
  output: [{ results: [] }]
});

export default workflow('agente-projetos-google', 'Agente | Projetos Google')
  .add(entrada)
  .to(preparar)
  .to(cada
    .onDone(final)
    .onEachBatch(resolver.to(qual
%s
      .onCase(8, pular.to(registrar)))));
""" % (js(PREPARAR), js(RESOLVER), switch_rules(), g, js(PULAR), js(REGISTRAR), js(FINAL), cases(nm))
    return head + body

def cases(nm):
    order = [('adrian', 'create'), ('adrian', 'update'), ('adrian', 'delete'), ('adrian', 'list'),
             ('maria', 'create'), ('maria', 'update'), ('maria', 'delete'), ('maria', 'list')]
    lines = []
    for i, k in enumerate(order):
        v = nm[k]
        if i == 0:
            lines.append("      .onCase(0, %s.to(registrar.to(nextBatch(cada))))" % v)
        else:
            lines.append("      .onCase(%d, %s.to(registrar))" % (i, v))
    return '\n'.join(lines)

# ---------------------------------------------------------------- backfill (workflow novo, gatilho manual)
def exec_node(var, name, pos, user_expr_plan):
    return """const %s = node({
  type: 'n8n-nodes-base.executeWorkflow', version: 1.3,
  config: { name: %s, position: %s, onError: 'continueRegularOutput',
    parameters: { source: 'database', mode: 'once', workflowId: { __rl: true, mode: 'id', value: WF_PROJETOS_GOOGLE },
      workflowInputs: { mappingMode: 'defineBelow', value: { owner: expr(%s), ops: expr(%s) } } } },
  output: [{ results: [] }]
});
""" % (var, js(name), pos, js("{{ " + user_expr_plan + ".gt.owner }}"), js("{{ JSON.stringify(" + user_expr_plan + ".gt.ops) }}"))

def backfill():
    head = "import { workflow, node, trigger, ifElse, splitInBatches, nextBatch, expr } from '@n8n/workflow-sdk';\n\nconst WF_PROJETOS_GOOGLE = '%s';\n" % WF_ID
    plan_ref = "$('Backfill: plano').first().json"
    body = """
const gatilho = trigger({
  type: 'n8n-nodes-base.manualTrigger', version: 1,
  config: { name: 'Backfill: gatilho manual', position: [0, 300] },
  output: [{}]
});

const usuarios = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Backfill: usuarios', position: [224, 300], %s,
    parameters: { operation: 'executeQuery', query: "SELECT (u->>'user_id')::bigint AS user_id, u->>'calendar_key' AS calendar_key FROM jsonb_array_elements(agente.f_proj_gt_users()) u" } },
  output: [{ user_id: 2, calendar_key: 'adrian' }]
});

const cada = splitInBatches({ version: 3, config: { name: 'Backfill: cada usuario', position: [448, 300], parameters: { batchSize: 1 } } });

const fim = node({ type: 'n8n-nodes-base.noOp', version: 1, config: { name: 'Backfill: fim', position: [672, 120] }, output: [{}] });

const plano = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Backfill: plano', position: [672, 360], %s,
    parameters: { operation: 'executeQuery', query: 'SELECT agente.f_proj_gt_plan($1::bigint, \\'{"legacy":true,"limit":80}\\'::jsonb) AS gt',
      options: { queryReplacement: expr("{{ [ $('Backfill: cada usuario').first().json.user_id ] }}") } } },
  output: [{ gt: { owner: 'adrian', ops: [] } }]
});

const temOps = ifElse({
  version: 2.2,
  config: { name: 'Backfill: ha operacoes?', position: [896, 360],
    parameters: { conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
      conditions: [{ leftValue: expr('{{ ($json.gt && $json.gt.ops) ? $json.gt.ops.length : 0 }}'), operator: { type: 'number', operation: 'gt' }, rightValue: 0 }],
      combinator: 'and' } } }
});

%s
const aplicar = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Backfill: aplicar', position: [1344, 300], %s,
    parameters: { operation: 'executeQuery', query: 'SELECT agente.f_proj_google_apply($1::bigint, $2::jsonb) AS r',
      options: { queryReplacement: expr("{{ [ $('Backfill: cada usuario').first().json.user_id, JSON.stringify($input.first().json) ] }}") } } },
  output: [{ r: { ok: 1, failed: 0, done: 0 } }]
});

export default workflow('agente-projetos-backfill', 'Agente | Projetos backfill')
  .add(gatilho)
  .to(usuarios)
  .to(cada
    .onDone(fim)
    .onEachBatch(plano.to(temOps
      .onTrue(google.to(aplicar.to(nextBatch(cada))))
      .onFalse(nextBatch(cada)))));
""" % (PG, PG, exec_node('google', 'Backfill: Google', '[1120, 300]', plan_ref), PG)
    return head + body

# ---------------------------------------------------------------- Disparador completo
def disparador(s=None):
    if s is None:
        s = open(os.path.join(HERE, 'disparador.sdk.js')).read()
    plan_ref = "$json"
    novos = """
const WF_PROJETOS_GOOGLE = '%s';

const projPlano = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Projetos: plano do dia', position: [1456, 1040], onError: 'continueRegularOutput', %s,
    parameters: { operation: 'executeQuery', query: 'SELECT agente.f_proj_gt_plan($1::bigint, \\'{"list":true,"limit":40}\\'::jsonb) AS gt',
      options: { queryReplacement: expr("{{ [ $('Cada usuario').first().json.user_id ] }}") } } },
  output: [{ gt: { owner: 'adrian', ops: [] } }]
});

const projTem = ifElse({
  version: 2.2,
  config: { name: 'Projetos: ha operacoes?', position: [1568, 1040],
    parameters: { conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
      conditions: [{ leftValue: expr('{{ ($json.gt && $json.gt.ops) ? $json.gt.ops.length : 0 }}'), operator: { type: 'number', operation: 'gt' }, rightValue: 0 }],
      combinator: 'and' } } }
});

%s
const projAplicar = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Projetos: aplicar do dia', position: [1904, 960], onError: 'continueRegularOutput', %s,
    parameters: { operation: 'executeQuery', query: 'SELECT agente.f_proj_google_apply($1::bigint, $2::jsonb) AS r',
      options: { queryReplacement: expr("{{ [ $('Cada usuario').first().json.user_id, JSON.stringify($input.first().json) ] }}") } } },
  output: [{ r: { ok: 1, failed: 0, done: 0 } }]
});
""" % (WF_ID, PG, exec_node('projGoogle', 'Projetos: Google do dia', '[1680, 960]', plan_ref), PG)
    antes = "export default workflow("
    assert s.count(antes) == 1
    s = s.replace(antes, novos.lstrip('\n') + '\n' + antes)
    old = "agendaAdrianHoje.to(tarefasResumo.to(dadosResumo.to(montarResumo.to(enviarResumo.to(nextBatch(cadaUsuario)))))))"
    new = ("agendaAdrianHoje.to(tarefasResumo.to(projPlano.to(projTem.onTrue(projGoogle.to(projAplicar.to(dadosResumo.to(montarResumo.to(enviarResumo.to(nextBatch(cadaUsuario))))))).onFalse(dadosResumo)))))")
    assert s.count(old) == 1, 'composicao do resumo mudou'
    s = s.replace(old, new)
    # posicao de 'Dados do resumo' e 'Montar resumo' / 'Enviar resumo' empurradas para a direita (so visual)
    return s

if __name__ == '__main__':
    out = os.environ.get('OUT_DIR', HERE)
    open(os.path.join(out, 'projetos_google.sdk.js'), 'w').write(subworkflow())
    open(os.path.join(out, 'projetos_backfill.sdk.js'), 'w').write(backfill())
    open(os.path.join(out, 'disparador_projetos.sdk.js'), 'w').write(disparador())
    print('ok')
