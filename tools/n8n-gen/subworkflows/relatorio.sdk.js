import { workflow, node, trigger, ifElse, expr } from '@n8n/workflow-sdk';

const entrada = trigger({
  type: 'n8n-nodes-base.executeWorkflowTrigger', version: 1.1,
  config: {
    name: 'Receber pedido de relatorio', position: [0, 300],
    parameters: { inputSource: 'workflowInputs', workflowInputs: { values: [
      { name: 'user_id', type: 'string' }, { name: 'chat_id', type: 'string' }, { name: 'period', type: 'string' },
      { name: 'month', type: 'string' }, { name: 'format', type: 'string' }, { name: 'keywords', type: 'string' }
    ] } }
  },
  output: [{ user_id: '55', chat_id: '999000413', period: 'current', month: '', format: 'xlsx', keywords: '' }]
});

const buscar = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: {
    name: 'Buscar dados do relatorio', position: [224, 300],
    parameters: {
      operation: 'executeQuery',
      query: "SELECT agente.f_report_data($1::bigint, jsonb_build_object('period', $2::text, 'month', $3::text, 'keywords', $4::text)) AS r",
      options: { queryReplacement: expr('{{ [ $json.user_id, $json.period || "current", $json.month || "", $json.keywords || "" ] }}') }
    },
    credentials: { postgres: { id: '1xCdaqn8KYskDi8x', name: 'Postgres Agente' } }
  },
  output: [{ r: { count: 1, label: 'mes atual', filename: 'financas', caption: 'x', lines: [] } }]
});

const temDados = ifElse({
  version: 2.2,
  config: {
    name: 'Tem lancamentos?', position: [448, 300],
    parameters: { conditions: {
      options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
      conditions: [{ leftValue: expr('{{ $json.r.count }}'), operator: { type: 'number', operation: 'gt' }, rightValue: 0 }],
      combinator: 'and' } }
  }
});

const semDados = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Resposta sem dados', position: [672, 480],
    parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "const r = $input.first().json.r || {};\nconst ir = r.ir === true;\nconst t = ir ? 'Não achei gastos de Saúde ou Educação pagos nesse período.' : 'Não achei lançamentos nesse período' + (r.label ? ' (' + r.label + ')' : '') + '.';\nreturn [{ json: { r: { text: t, kb: 'none', rid: 0 } } }];" }
  },
  output: [{ r: { text: 'Não achei lançamentos nesse período.', kb: 'none', rid: 0 } }]
});

const montar = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Montar linhas', position: [672, 200],
    parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "const r = $('Buscar dados do relatorio').first().json.r;\nconst fmt = String($('Receber pedido de relatorio').first().json.format || 'xlsx').toLowerCase();\nconst cols = ['Data', 'Descrição', 'Categoria', 'Forma de pagamento', 'Cartão', 'Parcela', 'Valor', 'Situação', 'Tipo'];\nconst lines = r.lines || [];\nconst out = [];\nfor (let i = 0; i < lines.length; i++) {\n  const l = lines[i];\n  const o = {};\n  for (let j = 0; j < cols.length; j++) {\n    let v = l[cols[j]];\n    if (v === undefined || v === null) { v = ''; }\n    if (cols[j] === 'Valor' && v !== '') {\n      v = Number(v);\n      if (fmt === 'csv') { v = v.toFixed(2).replace('.', ','); }\n    } else if (typeof v === 'string' && /^[=+@-]/.test(v)) {\n      v = String.fromCharCode(39) + v;\n    }\n    o[cols[j]] = v;\n  }\n  out.push({ json: o });\n}\nreturn out;" }
  },
  output: [{ Data: '01/11/2026', Valor: 10 }]
});

const ehCsv = ifElse({
  version: 2.2,
  config: {
    name: 'Formato CSV?', position: [896, 200],
    parameters: { conditions: {
      options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' },
      conditions: [{ leftValue: expr("{{ $('Receber pedido de relatorio').first().json.format }}"), operator: { type: 'string', operation: 'equals' }, rightValue: 'csv' }],
      combinator: 'and' } }
  }
});

const gerarCsv = node({
  type: 'n8n-nodes-base.convertToFile', version: 1.1,
  config: {
    name: 'Gerar CSV', position: [1120, 100],
    parameters: { operation: 'csv', binaryPropertyName: 'data', options: {
      delimiter: ';', headerRow: true, addBOM: true, encoding: 'utf8', dataIsBase64: false,
      fileName: expr("{{ $('Buscar dados do relatorio').first().json.r.filename }}.csv") } }
  },
  output: [{}]
});

const gerarXlsx = node({
  type: 'n8n-nodes-base.convertToFile', version: 1.1,
  config: {
    name: 'Gerar XLSX', position: [1120, 300],
    parameters: { operation: 'xlsx', binaryPropertyName: 'data', options: {
      sheetName: 'Financas', headerRow: true,
      fileName: expr("{{ $('Buscar dados do relatorio').first().json.r.filename }}.xlsx") } }
  },
  output: [{}]
});

const conferir = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Conferir arquivo', position: [1344, 200],
    parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "const item = $input.first();\nconst buf = await this.helpers.getBinaryDataBuffer(0, 'data');\nconst zip = buf.length > 1 && buf[0] === 80 && buf[1] === 75;\nconst head = zip ? '' : buf.slice(0, 600).toString('utf8');\nreturn [{ json: { size: buf.length, zip: zip, head: head, file_name: item.binary.data.fileName }, binary: item.binary }];" }
  },
  output: [{ size: 100, zip: true, head: '', file_name: 'x.xlsx' }]
});

const enviar = node({
  type: 'n8n-nodes-base.telegram', version: 1.2, onError: 'continueRegularOutput',
  config: {
    name: 'Enviar relatorio', position: [1568, 200],
    parameters: {
      resource: 'message', operation: 'sendDocument',
      chatId: expr("{{ $('Receber pedido de relatorio').first().json.chat_id }}"),
      binaryData: true, binaryPropertyName: 'data',
      additionalFields: { caption: expr("{{ $('Buscar dados do relatorio').first().json.r.caption }}") }
    },
    credentials: { telegramApi: { id: '9wbEyTedyS1LrOAj', name: 'Telegram Agente' } }
  },
  output: [{ ok: true }]
});

const resposta = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: {
    name: 'Resposta do relatorio', position: [1792, 200],
    parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "const e = $input.first().json || {};\nconst c = $('Conferir arquivo').first().json;\nconst fmt = String($('Receber pedido de relatorio').first().json.format || 'xlsx').toUpperCase();\nconst kb = Math.max(1, Math.round(Number(c.size || 0) / 1024));\nlet t = 'Pronto, mandei o relatório em ' + fmt + ' (' + kb + ' KB).';\nif (e.error) { t = 'Gerei o relatório, mas não consegui enviar o arquivo agora. Tente de novo em instantes.'; }\nreturn [{ json: { r: { text: t, kb: 'none', rid: 0 }, size: c.size, head: c.head, file_name: c.file_name, send_error: e.error ? String(e.error.message || e.error) : '' } }];" }
  },
  output: [{ r: { text: 'ok', kb: 'none', rid: 0 } }]
});

export default workflow('relatorio-financas', 'Agente | Relatorio')
  .add(entrada)
  .to(buscar.to(temDados
    .onTrue(montar.to(ehCsv.onTrue(gerarCsv.to(conferir.to(enviar.to(resposta)))).onFalse(gerarXlsx.to(conferir))))
    .onFalse(semDados)));
