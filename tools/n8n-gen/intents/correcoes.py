# Ciclo de correcoes (spec-ciclo-correcoes.md): extensoes transversais de intents base (finance, create_reminder, supply_*).
# Depende de db/024_ciclo_correcoes.sql (f_fin com items, f_supply_manage, f_supply_cb, ask_total, duplicado, f_menu).
# Schema: extra_requests, fin_items, supply_action, new_name. Regras: VARIOS PEDIDOS, VARIOS GASTOS, REMEDIO..., ANTECEDENCIA, ANOTA CURTO, FORA DO ESCOPO.
# O HTML de Preparar envio e o /start curto ficam em patch_f6_correcoes.py (nao sao uma Intencao).
from .core import Intent, Edit

RAW_RULES = """  'VARIOS PEDIDOS NA MESMA MENSAGEM: trate o pedido principal (o primeiro, ou o mais importante) normalmente e descreva em extra_requests, numa frase curta em portugues, o que a mensagem pedia ALEM do que voce tratou (ex.: anotar levar a maquete). So preencha extra_requests quando sobrou algo sem tratar; use null quando a mensagem tinha um pedido so. Nao use extra_requests para detalhes do proprio pedido (ex.: aviso antes, local).',
  'VARIOS GASTOS: quando a mensagem tiver mais de um gasto (gastei 120 na farmacia e 80 no mercado; 15 de cafe e 12 de busao), use intent=finance, fin_action=add e preencha fin_items com TODOS os gastos [{title, amount, category}] (category so se o usuario disse ou for obvia entre as categorias dele; senao null). Com um gasto so, fin_items=null e use title e amount como sempre.',
  'REMEDIO SEM NOME: se o usuario pedir lembrete ou cadastro de remedio, comprimido ou pilula SEM dizer o nome (me lembra do remedio as 22h), use intent=clarify e pergunte em reply: Qual o nome do remedio? Nunca cadastre item chamado remedio. A resposta seguinte (e sertralina, sertralina) completa o pedido: use supply_schedule com item e take_time. Vale o mesmo para vitamina e suplemento sem nome.',
  'REMEDIO RENOMEAR E APAGAR: se existe item generico (remedio) nos itens cadastrados e o usuario disser o nome e sertralina, e sertralina, se chama sertralina, muda o nome, use intent=supply_adjust com supply_action=rename, item = nome atual (remedio) e new_name = sertralina. Para apagar: apaga o remedio X, tira o remedio X, remove a vitamina X = intent=supply_adjust com supply_action=delete e item = X (o sistema pede confirmacao). Parar so o lembrete continua sendo supply_schedule com stop_reminder=true. Nos outros usos de supply_adjust deixe supply_action e new_name como null.',
  'ANTECEDENCIA NO PEDIDO: se a mensagem disser quanto tempo antes avisar, SEMPRE preencha lead_minutes, em lembrete ou compromisso: 1h antes ou uma hora antes = 60; meia hora antes = 30; 15 min antes = 15; duas horas antes = 120; um dia antes = 1440. Isso vale mesmo quando a mensagem tem outros pedidos.',
  'ANOTA CURTO: anota levar a maquete, anota ai levar o carregador, anota trazer o livro (frase curta de levar, trazer ou informacao, sem hora e sem pedir aviso) = note_manage save com note_text. NAO e compromisso nem lembrete, NAO procure compromisso anterior e nao peca data ou hora, mesmo que a conversa recente fale de uma reuniao. Acao a fazer (ligar, pagar, comprar) segue a regra de tarefas.',
  'FORA DO ESCOPO: reservar mesa ou restaurante, reservar passagem ou hotel, pesquisar preco, indicar restaurante ou lugar, comprar ou pedir algo, previsao do tempo: use intent=chat e reply de UMA frase: Isso eu ainda nao faco (reservar mesa). Se fizer sentido, acrescente o que voce faz: Posso te lembrar de ligar para reservar. NUNCA diga anotei, reservei ou vou fazer quando nada foi gravado, NUNCA faca perguntas antes de dizer que nao faz e NUNCA use create_event para isso.',
"""


def build():
    global byname
    byname['Resposta do lembrete']['parameters']['jsCode'] = """const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
let text = '';
let kb = 'none';
if (r.duplicate) {
  text = 'Já tinha esse lembrete: "' + a.title + '" - ' + a.due_label + '.';
} else {
  text = 'Lembrete criado: "' + a.title + '" - ' + a.due_label + (a.shared ? ' (para voces dois)' : '') + '.' + (r.repeat_text ? ' Repete ' + r.repeat_text + '.' : '');
  const lm = Number(a.lead_str || 0);
  if (lm > 0) {
    const lab = (lm >= 1440 && lm % 1440 === 0) ? (lm / 1440) + ' dia(s)' : ((lm >= 60 && lm % 60 === 0) ? (lm / 60) + 'h' : lm + ' min');
    text += ' Aviso ' + lab + ' antes.';
  }
  if (r.ask_lead) { text += String.fromCharCode(10) + 'Quer que eu te lembre antes? (Dica: diga "sempre me avise 30 min antes" e eu nao pergunto mais.)'; kb = 'lead'; }
}
return [{ json: { chat_id: a.chat_id, text: text, kb: kb, rid: r.reminder_id || 0, state: '' } }];"""

    # ===== Remedio: renomear, apagar (com confirmacao) e pergunta da cartela so quando faz sentido =====
    add_kb('sup_del', [('Sim, apagar', 'spdel:{rid}'), ('Nao', 'spkeep:{rid}')])
    byname = _refresh()
    aj = byname['Ajustar estoque']['parameters']
    aj['query'] = "SELECT agente.f_supply_manage($1::bigint,$2::text,NULLIF($3::text,'')::int,NULLIF($4::text,'')::int,NULLIF($5::text,''),NULLIF($6::text,'')) AS r"
    aj['options']['queryReplacement'] = ("={{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.item || '', "
        "$('Interpretar resposta').first().json.units_left === undefined ? '' : String($('Interpretar resposta').first().json.units_left), "
        "$('Interpretar resposta').first().json.pause_days === undefined ? '' : String($('Interpretar resposta').first().json.pause_days), "
        "$('Interpretar resposta').first().json.supply_action || '', $('Interpretar resposta').first().json.new_name || '' ] }}")
    byname['Resposta do ajuste']['parameters']['jsCode'] = """const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
let text = '';
let kb = 'none';
let rid = 0;
if (r.action === 'rename') {
  if (r.need_name) { text = 'Qual o novo nome do remedio?'; }
  else if (!r.found) { text = 'Nao achei um item para renomear. Se quiser cadastrar, diga: me lembre de tomar NOME todo dia as 8h.'; }
  else if (r.conflict) { text = 'Ja existe um item chamado ' + r.item + '. Quer apagar o outro?'; }
  else { text = 'Pronto: ' + r.old_item + ' agora se chama ' + r.item + (r.take_time ? ' (lembrete diario as ' + r.take_time + ' mantido)' : '') + '.'; }
} else if (r.action === 'delete') {
  if (!r.found) { text = 'Nao achei esse remedio. Me diga o nome, por exemplo: apaga o remedio sertralina.'; }
  else { text = 'Apagar ' + r.item + (r.take_time ? ' e o lembrete de tomar as ' + r.take_time : '') + '?'; kb = 'sup_del'; rid = r.sid || 0; }
} else {
  text = r.found ? 'Ajustado: ' + r.item + ' - restam ' + Math.round(Number(r.units_left)) + ', acaba em ' + r.runs_out_on + ' (aviso em ' + r.alert_on + ').' : 'Nao achei esse item. Me diga o nome, por exemplo: tenho 12 na cartela de losartana.';
}
return [{ json: { chat_id: a.chat_id, text: text, kb: kb, rid: rid, state: '' } }];"""
    rt = byname['Resposta do horario de tomar']['parameters']['jsCode']
    rt = rep(rt, "  if (r.needs_total) {\n    text += NL + 'Quantos comprimidos tem na cartela agora? (Pode mandar uma foto.) Assim eu aviso quando for comprar.';\n    state = JSON.stringify({ kind: 'clarify', original: a.transcript || a.original_text || '' });\n  } else {",
             "  if (r.needs_total && r.ask_total) {\n    text += NL + 'Quantos comprimidos tem na cartela agora? (Pode mandar uma foto.) Assim eu aviso quando for comprar.';\n    state = JSON.stringify({ kind: 'clarify', original: a.transcript || a.original_text || '' });\n  } else if (r.needs_total) {\n    text += '';\n  } else {")
    byname['Resposta do horario de tomar']['parameters']['jsCode'] = rt
    re_ = byname['Resposta do estoque novo']['parameters']['jsCode']
    re_ = rep(re_, "if (r.needs_total) {\n  text += NL + 'Quantos comprimidos tem na cartela agora? (Pode mandar uma foto.)';\n  state = JSON.stringify({ kind: 'clarify', original: a.transcript || a.original_text || '' });\n} else {",
              "if (r.needs_total && r.ask_total) {\n  text += NL + 'Quantos comprimidos tem na cartela agora? (Pode mandar uma foto.)';\n  state = JSON.stringify({ kind: 'clarify', original: a.transcript || a.original_text || '' });\n} else if (r.needs_total) {\n  text += '';\n} else {")
    byname['Resposta do estoque novo']['parameters']['jsCode'] = re_


INTENT = Intent(
    name='correcoes',
    extends='*',
    raw_rules=RAW_RULES,
    edits=[
        Edit('Montar pedido a IA', 'jsCode', "keywords: NN('string'), budget_amount: NN('number'), closing_day: NN('integer')\n};",
        """keywords: NN('string'), budget_amount: NN('number'), closing_day: NN('integer'),
  extra_requests: NN('string'),
  fin_items: { type: ['array', 'null'], items: { type: 'object', properties: { title: { type: 'string' }, amount: { type: 'number' }, category: { type: ['string', 'null'] } }, required: ['title', 'amount', 'category'], additionalProperties: false } },
  supply_action: { type: ['string', 'null'], enum: ['rename', 'delete', null] }, new_name: NN('string')
};"""),
        Edit('Montar pedido a IA', 'jsCode', "A mensagem atual provavelmente complementa; combine as duas.');",
        "Combine as duas SOMENTE se a mensagem atual for claramente a resposta a essa pergunta (so um horario, uma data, um nome, sim ou nao). Se a mensagem atual for um assunto novo ou outro pedido completo, trate como pedido novo e ignore o pedido pendente.');"),
        Edit('Interpretar resposta', 'jsCode', "month: out.month || '', alert_days: out.alert_days || null,",
        "month: out.month || '', alert_days: out.alert_days || null,\n    items: Array.isArray(out.fin_items) ? out.fin_items.filter(function (x) { return x && Number(x.amount) > 0; }) : [],")],
    build=build,
)
