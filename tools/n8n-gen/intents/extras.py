# Modulo "extras" (B): lembrete recorrente, cancelar lembrete, cartoes, consultas financeiras, misc_query.
# Cada estagio abaixo e aplicado em sequencia por patch_extras.py (a ordem das regras no prompt e a destes estagios).
#   create_reminder.repeat  : extensao da intent base create_reminder (repeticao)
#   cancel_reminder         : intent (regra CANCELAR LEMBRETE)
#   finance.cartoes         : extensao da intent base finance (cartoes e consultas)
#   misc_query              : intent + nos e rotas dos extras
#   finance.cartoes_kb      : teclado de confirmacao de apagar cartao
from .core import Intent, Edit

R_REPETE = "LEMBRETE QUE SE REPETE: em create_reminder, repeat_freq = daily, weekly ou monthly quando o usuario pede algo recorrente (todo dia, toda semana, toda sexta, todo mes, todo dia 20); null se nao repete. date = a PROXIMA ocorrencia (YYYY-MM-DD) e time = HH:MM exato (sem hora, use clarify). repeat_until (YYYY-MM-DD) se disser ate quando (ate dezembro = ultimo dia do mes) e repeat_count se disser por quantas vezes (por 4 semanas = 4). Exemplos: toda sexta me pergunta as pendencias as 17h = create_reminder, title Pendencias da semana?, repeat_freq weekly; me lembra todo dia 20h de fechar o caixa = create_reminder, repeat_freq daily; todo dia 5 me lembra do aluguel as 9h = monthly. Remedio ou suplemento diario continua sendo supply_schedule."
# (inclui a correcao pos-teste do antigo patch_fix1: compromisso e manage_event, nao cancel_reminder)
R_CANCELA = "CANCELAR LEMBRETE: so quando o usuario fala de LEMBRETE ou AVISO do bot. Cancelar, desmarcar ou apagar um COMPROMISSO, reuniao, consulta ou evento (mesmo sem a palavra agenda) e manage_event com ev_action=cancel, NUNCA cancel_reminder. intent=cancel_reminder com title = palavras principais do lembrete (cancela o lembrete da conta de luz = conta de luz; para de me lembrar das pendencias da sexta = pendencias; apaga o lembrete que se repete toda semana). Lembrete de remedio ou suplemento: supply_schedule com stop_reminder=true."
R_CARTOES = "CARTOES (intent=finance): card_create ou card_edit com card = nome do cartao (Itau), card_closing_day (dia que a fatura fecha), card_due_day (dia que vence), card_limit (limite) e alert_days (avisar N dias antes de vencer; so se pedir). Exemplos: cartao Itau fecha dia 10 vence dia 17 limite 5000 = card_create; muda o limite do Itau para 6000 = card_edit com card_limit; me avisa 5 dias antes da fatura do Nubank = card_edit com alert_days 5. card_remove = apagar cartao. card_list = meus cartoes. card_status = minha fatura ja fechou, quanto vai fechar a fatura, quanto tenho de limite no cartao, fatura aberta (card = nome se citado). Gasto no cartao: fin_action=add com card = nome do cartao e method=credito (almoco 141,60 no cartao do Itau). Gasto no credito sem cartao citado: add com method=credito e card null."
R_CONSULTAS = "CONSULTAS FINANCEIRAS: category_total (quanto foi de mercado em agosto: category = categoria, month = YYYY-MM do mes citado; sem mes = mes atual), method_total (quanto gastei no pix, no credito, no debito: method = pix, debito, credito, dinheiro ou boleto; month ou period se citado; sem method = resumo por forma de pagamento), left_to_close (quanto sobrou pra fechar o mes), committed (quanto ja comprometi de setembro: contas a pagar e parcelas daquele mes; month = YYYY-MM; sem mes = proximo mes). Em month use o ano atual; use o ano seguinte so se o mes citado ja passou e o usuario fala do futuro."
R_MISC = "PEQUENOS EXTRAS: intent=misc_query com query_kind = reminder_history (voce me avisou da conta de luz?: title = o assunto), calendar_link (me manda o link da minha agenda) ou tasks_closed (quantas tarefas fechei essa semana?)."

INTERPRET_REPETE = """if (out.intent === 'create_reminder') {
  out.repeat_json = JSON.stringify({
    freq: out.repeat_freq || '',
    until: (out.repeat_until && okDate.test(out.repeat_until)) ? out.repeat_until : '',
    count: (typeof out.repeat_count === 'number' && out.repeat_count > 0) ? out.repeat_count : ''
  });
}"""

INTERPRET_MISC = """if (out.intent === 'misc_query') {
  out.misc_json = JSON.stringify({ kind: out.query_kind || '', title: out.title || '' });
  out.closed_min = now.startOf('week').toUTC().toISO();
}"""


# campos do schema da IA (antes tinham ficado no patch_f2a.py)
SCHEMA_QUERY = """query_kind: { type: ['string', 'null'], enum: ['reminder_history', 'tasks_closed', 'calendar_link', null] },"""
SCHEMA_CARTOES = """card: NN('string'), card_closing_day: NN('integer'), card_due_day: NN('integer'), card_limit: NN('number'), month: NN('string'),"""


def build_repete():
    global byname
    byname = _refresh()
    cl = byname['Criar lembrete']['parameters']
    assert "f_create_reminder" in cl['query']
    cl['query'] = "SELECT agente.f_reminder_create_ex($1::bigint,$2::text,$3::timestamptz,$4::boolean,NULLIF($5::text,'')::int,$6::text,$7::jsonb) AS r"
    cl['options']['queryReplacement'] = rep(cl['options']['queryReplacement'], ".source ] }}", ".source, ($('Interpretar resposta').first().json.repeat_json || '{}') ] }}")
    rl = byname['Resposta do lembrete']['parameters']['jsCode']
    rl = rep(rl, "(a.shared ? ' (para voces dois)' : '') + '.';", "(a.shared ? ' (para voces dois)' : '') + '.' + (r.repeat_text ? ' Repete ' + r.repeat_text + '.' : '');")
    byname['Resposta do lembrete']['parameters']['jsCode'] = rl


def build_misc():
    global nodes, byname
    def _rule(field, val):
        return {"outputKey": val, "renameOutput": True, "conditions": {"options": {"caseSensitive": True, "leftValue": "", "typeValidation": "strict"},
                "conditions": [{"leftValue": field, "operator": {"type": "string", "operation": "equals"}, "rightValue": val}], "combinator": "and"}}
    IR = "$('Interpretar resposta').first().json."
    nodes += [
     {"name": "Extras: Qual consulta?", "type": "n8n-nodes-base.switch", "typeVersion": 3.4, "position": [4256, 3744],
      "parameters": {"mode": "rules", "rules": {"values": [_rule("={{ $json.query_kind }}", "tasks_closed")]},
                     "options": {"fallbackOutput": "extra", "renameFallbackOutput": "outras consultas"}}},
     exec_wf("Extras: Tarefas fechadas", "dnVm8cfVhpqXGWmr",
             {"calendar_key": "={{ " + IR + "calendar_key }}", "action": "closed", "title": "", "due": "={{ " + IR + "closed_min }}"}, [4480, 3600]),
     code_node("Extras: Resposta das tarefas", "const a = $('Interpretar resposta').first().json;\n"
       "const r = $input.first().json || {};\nconst NL = String.fromCharCode(10);\nlet text = '';\n"
       "if (r.not_connected) {\n  text = 'Suas tarefas do Google ainda nao estao conectadas ao agente.';\n"
       "} else if (!Array.isArray(r.closed)) {\n  text = 'Nao consegui consultar as tarefas concluidas agora. Tente de novo mais tarde.';\n"
       "} else if (r.closed.length === 0) {\n  text = 'Nenhuma tarefa concluida desde segunda-feira.';\n"
       "} else {\n  text = 'Voce concluiu ' + r.closed.length + ' tarefa' + (r.closed.length > 1 ? 's' : '') + ' desde segunda-feira:' + NL + r.closed.slice(0, 15).map(function (t) { return '- ' + t.title; }).join(NL);\n}\n"
       "return [{ json: { chat_id: a.chat_id, text: text, kb: 'none', rid: 0, state: '' } }];", [4704, 3600]),
     pg_node("Extras: Consulta", "SELECT agente.f_misc($1::bigint, $2::jsonb) AS r",
             "={{ [ " + IR + "user_id, " + IR + "misc_json ] }}", [4480, 3792]),
     pg_node("Extras: Cancelar lembrete", "SELECT agente.f_reminder_cancel($1::bigint, $2::text) AS r",
             "={{ [ " + IR + "user_id, " + IR + "title ] }}", [4480, 3984]),
     code_node("Extras: Resposta", "const a = $('Interpretar resposta').first().json;\nconst r = $input.first().json.r || {};\n"
       "return [{ json: { chat_id: a.chat_id, text: r.text || 'Nao consegui agora. Tente de novo.', kb: r.kb || 'none', rid: r.rid || 0, state: '' } }];", [4704, 3888]),
    ]
    _refresh()
    byname['Extras: Tarefas fechadas']['alwaysOutputData'] = True   # se o subworkflow ainda nao tiver a acao 'closed', responde com texto de erro em vez de silencio
    for _n in ("Extras: Consulta", "Extras: Cancelar lembrete"):
        byname[_n]['onError'] = 'continueRegularOutput'

    setc('Extras: Qual consulta?', ['Extras: Tarefas fechadas', 'Extras: Consulta'])
    setc('Extras: Tarefas fechadas', ['Extras: Resposta das tarefas'])
    setc('Extras: Resposta das tarefas', ['Preparar envio'])
    setc('Extras: Consulta', ['Extras: Resposta'])
    setc('Extras: Cancelar lembrete', ['Extras: Resposta'])
    setc('Extras: Resposta', ['Preparar envio'])


def build_kb():
    add_kb('ex_card_del', [('Sim, apagar', 'exdel:{rid}'), ('Nao', 'exkeep:{rid}')])
    _refresh()


INTENTS = [
    Intent(name='create_reminder.repeat', extends='create_reminder', rules=[R_REPETE], interpret_js=INTERPRET_REPETE, build=build_repete),
    Intent(name='cancel_reminder', enum_after='manage_event', rules=[R_CANCELA]),
    Intent(name='finance.cartoes', extends='finance', rules=[R_CARTOES, R_CONSULTAS],
           schema_parts=[(SCHEMA_CARTOES, " ", "pref_no_emoji: NN('boolean'),")],
           edits=[Edit('Montar pedido a IA', 'jsCode', "'goal_edit', 'goal_remove', null] },",
            "'goal_edit', 'goal_remove', 'card_create', 'card_edit', 'card_remove', 'card_list', 'card_status', 'category_total', 'method_total', 'left_to_close', 'committed', null] },"),
                  Edit('Interpretar resposta', 'jsCode', "budget_amount: out.budget_amount === undefined ? null : out.budget_amount, closing_day: out.closing_day || null,",
            "budget_amount: out.budget_amount === undefined ? null : out.budget_amount, closing_day: out.closing_day || null,\n    card: out.card || '', card_closing_day: out.card_closing_day || null, card_due_day: out.card_due_day || null, card_limit: out.card_limit === undefined ? null : out.card_limit, month: out.month || '',"),
                  Edit('Interpretar resposta', 'jsCode', "card_limit: out.card_limit === undefined ? null : out.card_limit, month: out.month || '',",
                       "card_limit: out.card_limit === undefined ? null : out.card_limit, month: out.month || '', alert_days: out.alert_days || null,")]),
    Intent(name='misc_query', enum_after='cancel_reminder', rules=[R_MISC],
           schema_parts=[(SCHEMA_QUERY, "\n  ", "card: NN('string'),")], interpret_js=INTERPRET_MISC, build=build_misc,
           route=('extras consulta', 'Extras: Qual consulta?'),
           routes=[('cancelar lembrete', 'cancel_reminder', 'Extras: Cancelar lembrete')]),
    Intent(name='finance.cartoes_kb', extends='finance', build=build_kb),
]
