import { workflow, node, trigger, ifElse, switchCase, splitInBatches, nextBatch, expr } from '@n8n/workflow-sdk';

const trigEnvios = trigger({
  type: 'n8n-nodes-base.scheduleTrigger', version: 1.3,
  config: { name: 'A cada minuto - envios', position: [0, 288], parameters: { rule: { interval: [{ field: 'minutes', minutesInterval: 1 }] } } },
  output: [{}]
});

const pegarEnvios = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Pegar envios vencidos', position: [224, 288], credentials: { postgres: { id: '1xCdaqn8KYskDi8x', name: 'Postgres Agente' } }, parameters: { operation: 'executeQuery', query: 'SELECT agente.f_claim_due() AS r' } },
  output: [{ r: [] }]
});

const montarMensagens = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Montar mensagens', position: [448, 288], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "const esc = function (s) { return String(s).split('**').join('').split('&').join('&amp;').split('<').join('&lt;').split('>').join('&gt;'); };\nconst lista = $input.first().json.r || [];\nconst itens = lista.map(function (n) {\n  let text = '', kb = 'none';\n  if (n.type === 'reminder') { text = 'Lembrete: ' + n.title + ' (' + n.due + ')'; kb = 'reminder'; }\n  else if (n.type === 'repeat') { text = 'Ainda pendente: ' + n.title + ' (' + n.due + ')'; kb = 'reminder'; }\n  else if (n.type === 'pre_alert') { text = 'Daqui a ' + n.offset_minutes + ' min: ' + n.title + ' (' + n.due + ')'; }\n  else if (n.type === 'dose') { text = 'Hora de tomar: ' + n.item; kb = 'dose'; }\n  else if (n.type === 'supply') { text = 'Sua ' + n.item + ' acaba em ' + n.days_left + ' dia(s). Quer que eu lembre de comprar?'; kb = 'supply'; }\n  return { json: { chat_id: n.chat_id, text: esc(text), kb: kb, rid: n.reminder_id || 0, sid: n.supply_id || 0, did: n.dose_id || 0 } };\n});\nreturn itens;" } },
  output: [{ chat_id: 1, text: 'x', kb: 'none' }]
});

const qualBotao = switchCase({
  version: 3.4,
  config: {
    name: 'Qual botao?', position: [672, 256],
    parameters: {
      mode: 'rules',
      rules: { values: [
        { outputKey: 'lembrete', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr('{{ $json.kb }}'), operator: { type: 'string', operation: 'equals' }, rightValue: 'reminder' }], combinator: 'and' } },
        { outputKey: 'estoque', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr('{{ $json.kb }}'), operator: { type: 'string', operation: 'equals' }, rightValue: 'supply' }], combinator: 'and' } },
        { outputKey: 'hora de tomar', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr('{{ $json.kb }}'), operator: { type: 'string', operation: 'equals' }, rightValue: 'dose' }], combinator: 'and' } }
      ] },
      options: { fallbackOutput: 'extra', renameFallbackOutput: 'sem botoes' }
    }
  }
});

const enviarLembrete = node({
  type: 'n8n-nodes-base.telegram', version: 1.2,
  config: {
    name: 'Enviar lembrete com botoes', position: [896, 0], credentials: { telegramApi: { id: '9wbEyTedyS1LrOAj', name: 'Telegram Agente' } },
    parameters: {
      resource: 'message', operation: 'sendMessage', chatId: expr('{{ $json.chat_id }}'), text: expr('{{ $json.text }}'), replyMarkup: 'inlineKeyboard',
      inlineKeyboard: { rows: [{ row: { buttons: [
        { text: 'Feito', additionalFields: { callback_data: expr('done:{{ $json.rid }}') } },
        { text: 'Adiar 1h', additionalFields: { callback_data: expr('snz1h:{{ $json.rid }}') } },
        { text: 'Adiar amanha', additionalFields: { callback_data: expr('snzt:{{ $json.rid }}') } }
      ] } }] },
      additionalFields: { appendAttribution: false, parse_mode: 'HTML' }
    }
  },
  output: [{ ok: true }]
});

const enviarEstoque = node({
  type: 'n8n-nodes-base.telegram', version: 1.2,
  config: {
    name: 'Enviar aviso de estoque', position: [896, 192], credentials: { telegramApi: { id: '9wbEyTedyS1LrOAj', name: 'Telegram Agente' } },
    parameters: {
      resource: 'message', operation: 'sendMessage', chatId: expr('{{ $json.chat_id }}'), text: expr('{{ $json.text }}'), replyMarkup: 'inlineKeyboard',
      inlineKeyboard: { rows: [{ row: { buttons: [
        { text: 'Comprei', additionalFields: { callback_data: expr('bought:{{ $json.sid }}') } },
        { text: 'Lembrar amanha', additionalFields: { callback_data: expr('later:{{ $json.sid }}') } }
      ] } }] },
      additionalFields: { appendAttribution: false, parse_mode: 'HTML' }
    }
  },
  output: [{ ok: true }]
});

const enviarDose = node({
  type: 'n8n-nodes-base.telegram', version: 1.2,
  config: {
    name: 'Enviar hora de tomar', position: [896, 384], credentials: { telegramApi: { id: '9wbEyTedyS1LrOAj', name: 'Telegram Agente' } },
    parameters: {
      resource: 'message', operation: 'sendMessage', chatId: expr('{{ $json.chat_id }}'), text: expr('{{ $json.text }}'), replyMarkup: 'inlineKeyboard',
      inlineKeyboard: { rows: [{ row: { buttons: [
        { text: 'Tomei', additionalFields: { callback_data: expr('took:{{ $json.did }}') } },
        { text: 'Pular hoje', additionalFields: { callback_data: expr('skipd:{{ $json.did }}') } }
      ] } }] },
      additionalFields: { appendAttribution: false, parse_mode: 'HTML' }
    }
  },
  output: [{ ok: true }]
});

const enviarSimples = node({
  type: 'n8n-nodes-base.telegram', version: 1.2,
  config: {
    name: 'Enviar aviso simples', position: [896, 576], credentials: { telegramApi: { id: '9wbEyTedyS1LrOAj', name: 'Telegram Agente' } },
    parameters: { resource: 'message', operation: 'sendMessage', chatId: expr('{{ $json.chat_id }}'), text: expr('{{ $json.text }}'), additionalFields: { appendAttribution: false, parse_mode: 'HTML' } }
  },
  output: [{ ok: true }]
});

const trigResumo = trigger({
  type: 'n8n-nodes-base.scheduleTrigger', version: 1.3,
  config: { name: 'A cada minuto - resumo', position: [0, 992], parameters: { rule: { interval: [{ field: 'minutes', minutesInterval: 1 }] } } },
  output: [{}]
});

const quemRecebe = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Quem recebe resumo agora', position: [224, 992], credentials: { postgres: { id: '1xCdaqn8KYskDi8x', name: 'Postgres Agente' } }, parameters: { operation: 'executeQuery', query: 'SELECT agente.f_summary_candidates() AS r' } },
  output: [{ r: [] }]
});

const separarUsuarios = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Separar usuarios', position: [448, 992], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "const lista = $input.first().json.r || [];\nreturn lista.map(function (u) {\n  const hoje = DateTime.now().setZone(u.timezone).startOf('day');\n  const base = u.kind === 'evening' ? hoje.plus({ days: 1 }) : hoje;\n  return { json: Object.assign({}, u, { time_min: base.toISO(), time_max: base.plus({ days: 1 }).toISO(), label: base.toFormat('dd/MM'), hoje_label: hoje.toFormat('dd/MM'), hoje_iso: hoje.toFormat('yyyy-MM-dd') }) };\n});" } },
  output: [{ user_id: 1 }]
});

const fimResumo = node({
  type: 'n8n-nodes-base.noOp', version: 1,
  config: { name: 'Fim do resumo', position: [896, 816] },
  output: [{}]
});

const qualCalendario = switchCase({
  version: 3.4,
  config: {
    name: 'Qual calendario no resumo?', position: [896, 1008],
    parameters: {
      mode: 'rules',
      rules: { values: [
        { outputKey: 'adrian', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr("{{ $('Cada usuario').first().json.calendar_key }}"), operator: { type: 'string', operation: 'equals' }, rightValue: 'adrian' }], combinator: 'and' } },
        { outputKey: 'maria', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr("{{ $('Cada usuario').first().json.calendar_key }}"), operator: { type: 'string', operation: 'equals' }, rightValue: 'maria' }], combinator: 'and' } }
      ] },
      options: { fallbackOutput: 'extra', renameFallbackOutput: 'sem calendario' }
    }
  }
});

const agendaAdrianHoje = node({
  type: 'n8n-nodes-base.executeWorkflow', version: 1.3,
  config: {
    name: 'Agenda Adrian - eventos de hoje', position: [1120, 800],
    parameters: { source: 'database', mode: 'once', workflowId: { __rl: true, mode: 'id', value: 'bBJo78YVQ1cOMX09' },
      workflowInputs: { mappingMode: 'defineBelow', value: { action: 'list', timeMin: expr("{{ $('Cada usuario').first().json.time_min }}"), timeMax: expr("{{ $('Cada usuario').first().json.time_max }}") } } }
  },
  output: [{ ok: true, events: [] }]
});

const tarefasResumo = node({
  type: 'n8n-nodes-base.executeWorkflow', version: 1.3,
  config: {
    name: 'Tarefas do resumo', position: [1344, 1040],
    parameters: { source: 'database', mode: 'once', workflowId: { __rl: true, mode: 'id', value: 'dnVm8cfVhpqXGWmr' },
      workflowInputs: { mappingMode: 'defineBelow', value: { calendar_key: expr("{{ $('Cada usuario').first().json.calendar_key || '' }}"), action: 'list', title: '', due: '' } } }
  },
  output: [{ tasks: [] }]
});

const dadosResumo = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Dados do resumo', position: [1568, 1040], credentials: { postgres: { id: '1xCdaqn8KYskDi8x', name: 'Postgres Agente' } },
    parameters: { operation: 'executeQuery', query: 'SELECT agente.f_summary_data($1::bigint) AS r', options: { queryReplacement: expr("{{ [ $('Cada usuario').first().json.user_id ] }}") } } },
  output: [{ r: {} }]
});

const montarResumo = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Montar resumo', position: [1792, 1040], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "const esc = function (s) { return String(s).split('**').join('').split('&').join('&amp;').split('<').join('&lt;').split('>').join('&gt;'); };\nconst u = $('Cada usuario').first().json;\nconst d = $('Dados do resumo').first().json.r || {};\nlet tj = {};\ntry { tj = $('Tarefas do resumo').first().json || {}; } catch (e) { tj = {}; }\nconst NL = String.fromCharCode(10);\nconst brl = function (n) {\n  const p = Number(n).toFixed(2).split('.');\n  return 'R$ ' + p[0].replace(/([0-9])(?=([0-9]{3})+$)/g, '$1.') + ',' + p[1];\n};\nconst dm = function (iso) { return String(iso).slice(8, 10) + '/' + String(iso).slice(5, 7); };\nlet eventos = [];\nif (u.calendar_key === 'adrian') { try { eventos = $('Agenda Adrian - eventos de hoje').first().json.events || []; } catch (e) { eventos = []; } }\nif (u.calendar_key === 'maria') { try { eventos = $('Agenda Maria Clara - eventos de hoje').first().json.events || []; } catch (e) { eventos = []; } }\nconst linhasEv = eventos.map(function (e) {\n  const quando = e.all_day ? 'dia todo' : DateTime.fromISO(e.start, { zone: u.timezone }).toFormat('HH:mm');\n  return '- ' + quando + '  ' + e.title + (e.location ? ' (' + e.location + ')' : '');\n});\nconst lista = Array.isArray(tj.tasks) ? tj.tasks : [];\nconst base = DateTime.fromISO(u.hoje_iso, { zone: u.timezone });\nconst lim3 = base.plus({ days: 3 }).toFormat('yyyy-MM-dd');\nconst amanhaIso = base.plus({ days: 1 }).toFormat('yyyy-MM-dd');\nconst tarefasAbertas = [];\nlet semPrazo = 0;\nlista.forEach(function (t) {\n  if (t.due && t.due < u.hoje_iso) { tarefasAbertas.push('- ' + t.title + ' (ATRASADA, ' + dm(t.due) + ')'); }\n  else if (t.due && t.due === u.hoje_iso) { tarefasAbertas.push('- ' + t.title + ' (vence hoje)'); }\n  else if (t.due && t.due <= lim3) { tarefasAbertas.push('- ' + t.title + ' (vence ' + dm(t.due) + ')'); }\n  else if (!t.due) { semPrazo += 1; if (semPrazo <= 5) { tarefasAbertas.push('- ' + t.title); } }\n});\nconst contas = (d.bills || []).map(function (b) {\n  const quando = b.late ? 'ATRASADA desde ' + b.due : (b.today ? 'vence hoje' : (b.tomorrow ? 'vence amanha' : 'vence ' + b.due));\n  return { late: b.late, today: b.today, tomorrow: b.tomorrow, line: '- ' + b.description + ' ' + brl(b.amount) + ' ' + quando };\n});\nconst partes = [];\nif (u.kind === 'evening') {\n  partes.push('Boa noite, ' + u.name + '! Fechando o dia (' + u.hoje_label + '):');\n  const pend = [];\n  lista.forEach(function (t) {\n    if (t.due && t.due < u.hoje_iso) { pend.push('- Tarefa: ' + t.title + ' (ATRASADA, ' + dm(t.due) + ')'); }\n    else if (t.due && t.due === u.hoje_iso) { pend.push('- Tarefa: ' + t.title + ' (vence hoje)'); }\n  });\n  (d.overdue_today || []).forEach(function (r) { pend.push('- Lembrete das ' + r.time + ': ' + r.title); });\n  contas.forEach(function (c) { if (c.late || c.today) { pend.push(c.line); } });\n  partes.push(pend.length ? 'Pendências de hoje:' + NL + pend.join(NL) + NL + '(diga \"já paguei\" ou \"feito\" para dar baixa)' : 'Hoje ficou tudo em dia.');\n  partes.push('Amanhã (' + u.label + '):');\n  partes.push(linhasEv.length ? 'Compromissos:' + NL + linhasEv.join(NL) : 'Compromissos: nenhum.');\n  const tarefasAmanha = lista.filter(function (t) { return t.due === amanhaIso; }).map(function (t) { return '- ' + t.title; });\n  if (tarefasAmanha.length) { partes.push('Tarefas:' + NL + tarefasAmanha.join(NL)); }\n  const lembAmanha = (d.tomorrow_reminders || []).map(function (r) { return '- ' + r.time + '  ' + r.title; });\n  partes.push(lembAmanha.length ? 'Lembretes:' + NL + lembAmanha.join(NL) : 'Lembretes: nenhum.');\n  const contasAmanha = contas.filter(function (c) { return c.tomorrow; }).map(function (c) { return c.line; });\n  if (contasAmanha.length) { partes.push('Contas a pagar amanhã:' + NL + contasAmanha.join(NL)); }\n} else {\n  partes.push('Bom dia, ' + u.name + '! Seu dia (' + u.label + '):');\n  partes.push(linhasEv.length ? 'Compromissos:' + NL + linhasEv.join(NL) : 'Compromissos: nenhum.');\n  partes.push(tarefasAbertas.length ? 'Tarefas:' + NL + tarefasAbertas.join(NL) + (semPrazo > 5 ? NL + '- e mais ' + (semPrazo - 5) + ' sem prazo' : '') : 'Tarefas: nenhuma.');\n  const lembretes = (d.today_reminders || []).map(function (r) { return '- ' + r.time + '  ' + r.title; });\n  partes.push(lembretes.length ? 'Lembretes:' + NL + lembretes.join(NL) : 'Lembretes: nenhum.');\n  if (contas.length) { partes.push('Contas a pagar:' + NL + contas.map(function (c) { return c.line; }).join(NL) + NL + '  (diga \"já paguei\" quando quitar)'); }\n  const dinheiro = [];\n  if (d.yesterday_spent) { dinheiro.push('- Ontem você gastou ' + brl(d.yesterday_spent)); }\n  (d.budget_alerts || []).forEach(function (b) {\n    dinheiro.push(b.pct >= 100 ? '- ' + b.name + ' passou do orçamento (' + brl(b.spent) + ' de ' + brl(b.budget) + ')' : '- ' + b.name + ' em ' + b.pct + '% do orçamento (' + brl(b.spent) + ' de ' + brl(b.budget) + ')');\n  });\n  if (dinheiro.length) { partes.push('Dinheiro:' + NL + dinheiro.join(NL)); }\n  const estoque = (d.supplies || []).map(function (s) { return s.item + ' (restam ' + Math.round(Number(s.units_left)) + ')'; });\n  if (estoque.length) { partes.push('Hora de comprar: ' + estoque.join(', ') + ' (diga \"comprei\" quando comprar)'); }\n}\nif (d.extras_text) { partes.push(String(d.extras_text)); }\nreturn [{ json: { chat_id: u.chat_id, text: esc(partes.join(NL + NL)) } }];" } },
  output: [{ chat_id: 1, text: 'x' }]
});

const enviarResumo = node({
  type: 'n8n-nodes-base.telegram', version: 1.2,
  config: {
    name: 'Enviar resumo', position: [2016, 1232], credentials: { telegramApi: { id: '9wbEyTedyS1LrOAj', name: 'Telegram Agente' } },
    parameters: { resource: 'message', operation: 'sendMessage', chatId: expr('{{ $json.chat_id }}'), text: expr('{{ $json.text }}'), additionalFields: { appendAttribution: false, parse_mode: 'HTML' } }
  },
  output: [{ ok: true }]
});

const cadaUsuario = splitInBatches({ version: 3, config: { name: 'Cada usuario', position: [672, 992], parameters: { batchSize: 1 } } });

const agendaMariaHoje = node({
  type: 'n8n-nodes-base.executeWorkflow', version: 1.3,
  config: {
    name: 'Agenda Maria Clara - eventos de hoje', position: [1120, 992],
    parameters: { source: 'database', mode: 'once', workflowId: { __rl: true, mode: 'id', value: '6bXuicjujajBuXbd' },
      workflowInputs: { mappingMode: 'defineBelow', value: { action: 'list', timeMin: expr("{{ $('Cada usuario').first().json.time_min }}"), timeMax: expr("{{ $('Cada usuario').first().json.time_max }}") } } }
  },
  output: [{ ok: true, events: [] }]
});

const trigConvites = trigger({
  type: 'n8n-nodes-base.scheduleTrigger', version: 1.3,
  config: { name: 'A cada 15 min - convites', position: [0, 1700], parameters: { rule: { interval: [{ field: 'minutes', minutesInterval: 15 }] } } },
  output: [{}]
});

const convUsuarios = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Convites: usuarios', position: [224, 1700], credentials: { postgres: { id: '1xCdaqn8KYskDi8x', name: 'Postgres Agente' } },
    parameters: { operation: 'executeQuery', query: "SELECT id AS user_id, telegram_id, calendar_key FROM agente.users WHERE onboarding_step = 'done' AND coalesce(calendar_key, '') <> '' ORDER BY id" } },
  output: [{ user_id: 2, telegram_id: 1, calendar_key: 'adrian' }]
});

const convCadaUsuario = splitInBatches({ version: 3, config: { name: 'Convites: cada usuario', position: [448, 1700], parameters: { batchSize: 1 } } });

const convFim = node({
  type: 'n8n-nodes-base.noOp', version: 1,
  config: { name: 'Convites: fim', position: [672, 1560] },
  output: [{}]
});

const convQualCal = switchCase({
  version: 3.4,
  config: {
    name: 'Convites: qual calendario?', position: [672, 1760],
    parameters: {
      mode: 'rules',
      rules: { values: [
        { outputKey: 'adrian', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr("{{ $('Convites: cada usuario').first().json.calendar_key }}"), operator: { type: 'string', operation: 'equals' }, rightValue: 'adrian' }], combinator: 'and' } },
        { outputKey: 'maria', renameOutput: true, conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'strict' }, conditions: [{ leftValue: expr("{{ $('Convites: cada usuario').first().json.calendar_key }}"), operator: { type: 'string', operation: 'equals' }, rightValue: 'maria' }], combinator: 'and' } }
      ] },
      options: { fallbackOutput: 'extra', renameFallbackOutput: 'sem calendario' }
    }
  }
});

const convAgendaAdrian = node({
  type: 'n8n-nodes-base.executeWorkflow', version: 1.3,
  config: {
    name: 'Convites: agenda Adrian', position: [896, 1660], onError: 'continueRegularOutput',
    parameters: { source: 'database', mode: 'once', workflowId: { __rl: true, mode: 'id', value: 'bBJo78YVQ1cOMX09' },
      workflowInputs: { mappingMode: 'defineBelow', value: { action: 'list', timeMin: expr('{{ $now.toISO() }}'), timeMax: expr('{{ $now.plus({ days: 14 }).toISO() }}') } } }
  },
  output: [{ ok: true, events: [] }]
});

const convAgendaMaria = node({
  type: 'n8n-nodes-base.executeWorkflow', version: 1.3,
  config: {
    name: 'Convites: agenda Maria Clara', position: [896, 1860], onError: 'continueRegularOutput',
    parameters: { source: 'database', mode: 'once', workflowId: { __rl: true, mode: 'id', value: '6bXuicjujajBuXbd' },
      workflowInputs: { mappingMode: 'defineBelow', value: { action: 'list', timeMin: expr('{{ $now.toISO() }}'), timeMax: expr('{{ $now.plus({ days: 14 }).toISO() }}') } } }
  },
  output: [{ ok: true, events: [] }]
});

const convPreparar = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Convites: preparar', position: [1120, 1760], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "const u = $('Convites: cada usuario').first().json;\nconst r = $input.first().json || {};\nif (!r.ok || !Array.isArray(r.events)) { return [{ json: { skip: true } }]; }\nconst ev = r.events.map(function (e) {\n  return { id: e.id, title: e.title, start: e.start, end: e.end, all_day: e.all_day, location: e.location, attendees: e.attendees, recurring_id: e.recurring_id, self_status: e.self_status, organizer: e.organizer, organizer_self: e.organizer_self, meet_link: e.meet_link };\n});\nreturn [{ json: { skip: false, user_id: u.user_id, calendar_key: u.calendar_key, events_json: JSON.stringify(ev) } }];" } },
  output: [{ skip: false, user_id: 2, calendar_key: 'adrian', events_json: '[]' }]
});

const convSemDados = ifElse({
  version: 2.2,
  config: {
    name: 'Convites: sem dados?', position: [1344, 1760],
    parameters: { conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
      conditions: [{ leftValue: expr('{{ $json.skip }}'), operator: { type: 'boolean', operation: 'true', singleValue: true }, rightValue: '' }],
      combinator: 'and' } }
  }
});

const convAvisos = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Convites: gerar avisos', position: [1568, 1860], credentials: { postgres: { id: '1xCdaqn8KYskDi8x', name: 'Postgres Agente' } },
    parameters: { operation: 'executeQuery', query: 'SELECT agente.f_agenda_invites($1::bigint,$2::text,$3::jsonb) AS r', options: { queryReplacement: expr('{{ [ $json.user_id, $json.calendar_key, $json.events_json ] }}') } } },
  output: [{ r: [] }]
});

const convMontar = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Convites: montar mensagens', position: [1792, 1860], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: "const esc = function (s) { return String(s).split('**').join('').split('&').join('&amp;').split('<').join('&lt;').split('>').join('&gt;'); };\nconst r = $input.first().json.r;\nconst lista = Array.isArray(r) ? r : [];\nconst itens = lista.filter(function (m) { return m && m.chat_id && m.text; }).map(function (m) {\n  return { json: { skip: false, chat_id: m.chat_id, text: esc(m.text), rid: m.rid || 0 } };\n});\nreturn itens.length ? itens : [{ json: { skip: true } }];" } },
  output: [{ skip: false, chat_id: 1, text: 'x', rid: 1 }]
});

const convSemAviso = ifElse({
  version: 2.2,
  config: {
    name: 'Convites: sem aviso?', position: [2016, 1860],
    parameters: { conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
      conditions: [{ leftValue: expr('{{ $json.skip }}'), operator: { type: 'boolean', operation: 'true', singleValue: true }, rightValue: '' }],
      combinator: 'and' } }
  }
});

const convEnviar = node({
  type: 'n8n-nodes-base.telegram', version: 1.2,
  config: {
    name: 'Convites: enviar aviso', position: [2240, 1960], credentials: { telegramApi: { id: '9wbEyTedyS1LrOAj', name: 'Telegram Agente' } }, onError: 'continueRegularOutput',
    parameters: {
      resource: 'message', operation: 'sendMessage', chatId: expr('{{ $json.chat_id }}'), text: expr('{{ $json.text }}'), replyMarkup: 'inlineKeyboard',
      inlineKeyboard: { rows: [{ row: { buttons: [
        { text: 'Aceitar', additionalFields: { callback_data: expr('agrs:{{ $json.rid }}') } },
        { text: 'Recusar', additionalFields: { callback_data: expr('agrn:{{ $json.rid }}') } }
      ] } }] },
      additionalFields: { appendAttribution: false, parse_mode: 'HTML' }
    }
  },
  output: [{ ok: true }]
});

const WF_PROJETOS_GOOGLE = 'G5N2OpaT2v6Pczcl';

const projPlano = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Projetos: plano do dia', position: [1456, 1040], onError: 'continueRegularOutput', credentials: { postgres: { id: '1xCdaqn8KYskDi8x', name: 'Postgres Agente' } },
    parameters: { operation: 'executeQuery', query: 'SELECT agente.f_proj_gt_plan($1::bigint, \'{"list":true,"limit":40}\'::jsonb) AS gt',
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

const projGoogle = node({
  type: 'n8n-nodes-base.executeWorkflow', version: 1.3,
  config: { name: "Projetos: Google do dia", position: [1680, 960], onError: 'continueRegularOutput',
    parameters: { source: 'database', mode: 'once', workflowId: { __rl: true, mode: 'id', value: WF_PROJETOS_GOOGLE },
      workflowInputs: { mappingMode: 'defineBelow', value: { owner: expr("{{ $json.gt.owner }}"), ops: expr("{{ JSON.stringify($json.gt.ops) }}") } } } },
  output: [{ results: [] }]
});

const projAplicar = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Projetos: aplicar do dia', position: [1904, 960], onError: 'continueRegularOutput', credentials: { postgres: { id: '1xCdaqn8KYskDi8x', name: 'Postgres Agente' } },
    parameters: { operation: 'executeQuery', query: 'SELECT agente.f_proj_google_apply($1::bigint, $2::jsonb) AS r',
      options: { queryReplacement: expr("{{ [ $('Cada usuario').first().json.user_id, JSON.stringify($input.first().json) ] }}") } } },
  output: [{ r: { ok: 1, failed: 0, done: 0 } }]
});

export default workflow('rGQRFihojnaUZHdG', 'Agente | Disparador')
  .add(trigEnvios)
  .to(pegarEnvios)
  .to(montarMensagens)
  .to(qualBotao
    .onCase(0, enviarLembrete)
    .onCase(1, enviarEstoque)
    .onCase(2, enviarDose)
    .onCase(3, enviarSimples))
  .add(trigResumo)
  .to(quemRecebe)
  .to(separarUsuarios)
  .to(cadaUsuario
    .onDone(fimResumo)
    .onEachBatch(qualCalendario
      .onCase(0, agendaAdrianHoje.to(tarefasResumo.to(projPlano.to(projTem.onTrue(projGoogle.to(projAplicar.to(dadosResumo.to(montarResumo.to(enviarResumo.to(nextBatch(cadaUsuario))))))).onFalse(dadosResumo)))))
      .onCase(1, agendaMariaHoje.to(tarefasResumo))
      .onCase(2, tarefasResumo)))
  .add(trigConvites)
  .to(convUsuarios)
  .to(convCadaUsuario
    .onDone(convFim)
    .onEachBatch(convQualCal
      .onCase(0, convAgendaAdrian.to(convPreparar.to(convSemDados
        .onTrue(nextBatch(convCadaUsuario))
        .onFalse(convAvisos.to(convMontar.to(convSemAviso
          .onTrue(nextBatch(convCadaUsuario))
          .onFalse(convEnviar.to(nextBatch(convCadaUsuario))))))))
      )
      .onCase(1, convAgendaMaria.to(convPreparar))
      .onCase(2, nextBatch(convCadaUsuario))));
