import { workflow, node, trigger, ifElse, splitInBatches, nextBatch, expr } from '@n8n/workflow-sdk';

const WF_PROJETOS_GOOGLE = 'G5N2OpaT2v6Pczcl';

const gatilho = trigger({
  type: 'n8n-nodes-base.manualTrigger', version: 1,
  config: { name: 'Backfill: gatilho manual', position: [0, 300] },
  output: [{}]
});

const usuarios = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Backfill: usuarios', position: [224, 300], credentials: { postgres: { id: '1xCdaqn8KYskDi8x', name: 'Postgres Agente' } },
    parameters: { operation: 'executeQuery', query: "SELECT (u->>'user_id')::bigint AS user_id, u->>'calendar_key' AS calendar_key FROM jsonb_array_elements(agente.f_proj_gt_users()) u" } },
  output: [{ user_id: 2, calendar_key: 'adrian' }]
});

const cada = splitInBatches({ version: 3, config: { name: 'Backfill: cada usuario', position: [448, 300], parameters: { batchSize: 1 } } });

const fim = node({ type: 'n8n-nodes-base.noOp', version: 1, config: { name: 'Backfill: fim', position: [672, 120] }, output: [{}] });

const plano = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Backfill: plano', position: [672, 360], credentials: { postgres: { id: '1xCdaqn8KYskDi8x', name: 'Postgres Agente' } },
    parameters: { operation: 'executeQuery', query: 'SELECT agente.f_proj_gt_plan($1::bigint, \'{"legacy":true,"limit":80}\'::jsonb) AS gt',
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

const google = node({
  type: 'n8n-nodes-base.executeWorkflow', version: 1.3,
  config: { name: "Backfill: Google", position: [1120, 300], onError: 'continueRegularOutput',
    parameters: { source: 'database', mode: 'once', workflowId: { __rl: true, mode: 'id', value: WF_PROJETOS_GOOGLE },
      workflowInputs: { mappingMode: 'defineBelow', value: { owner: expr("{{ $('Backfill: plano').first().json.gt.owner }}"), ops: expr("{{ JSON.stringify($('Backfill: plano').first().json.gt.ops) }}") } } } },
  output: [{ results: [] }]
});

const aplicar = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Backfill: aplicar', position: [1344, 300], credentials: { postgres: { id: '1xCdaqn8KYskDi8x', name: 'Postgres Agente' } },
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
