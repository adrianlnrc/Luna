# Intent finance (base): dinheiro, gastos, receitas, contas a pagar, parcelas, orcamento, categorias, consultas e dia de fechamento.
# Depende de db (agente.f_fin e correlatas). As extensoes ficam em outros modulos: prefs_fin (planejamento), extras (cartoes),
# fin_recibo (recibo), fin_relatorio (relatorio) e correcoes (fin_items). Os nos de tratamento estao no estagio 'finance.nos'.
from .core import Intent, Edit

HINT_OLD = "clarify (falta informacao essencial: pergunte em reply), chat ("
HINT_NEW = "finance (dinheiro: registrar gasto ou receita, conta a pagar, parcelas, gasto fixo mensal, orcamento, categorias, consultar gastos, comparar meses, quem me deve, dia de fechamento do mes), clarify (falta informacao essencial: pergunte em reply), chat ("
RULES_OLD = "  'set_preference: pref_lead_minutes (0 = nunca avisar antes), pref_summary_time (HH:MM), pref_supply_days.'\n];"
FIN_RULES = """  'set_preference: pref_lead_minutes (0 = nunca avisar antes), pref_summary_time (HH:MM), pref_supply_days.',
  'FINANCAS: dinheiro usa intent=finance e fin_action: add (registrar gasto ou receita: gastei, paguei X no mercado, comprei por, recebi, ganhei, entrou), pay (dar baixa em algo que estava PENDENTE: ja paguei o aluguel, esqueci de avisar que paguei, o Joao pagou), correct (corrigir o ULTIMO lancamento: valor, categoria ou descricao), remove (apagar um lancamento), summary (quanto gastei, resumo, gastos por categoria, saldo, o que tenho a pagar), compare (comparar com o mes anterior), top (maiores despesas), by_day (gastos por dia), budget_set (definir orcamento mensal de uma categoria), budget_status (quanto resta do orcamento), category_create (criar categoria, com palavras-chave), category_list (listar categorias), closing_set (dia em que fecha o mes financeiro), owed (quem me deve).',
  'FINANCAS campos: amount = valor em reais de UM lancamento, numero com ponto decimal (42.5). Em parcelas, amount e o valor de CADA parcela (se o usuario deu o total, divida) e installments e o numero de parcelas. title = descricao curta (mercado, aluguel, uber) ou nome do estabelecimento. date = data do gasto (hoje se nao citada) ou o VENCIMENTO quando paid=false. paid=false para conta A PAGAR ("vence dia 10", "vou pagar"), receita a receber ou quando alguem te deve; senao paid=true. fin_kind = expense (padrao) ou income (recebi, ganhei, me pagou, entrou). method (pix, debito, credito, dinheiro, boleto) so se citado. recurring_day = dia do mes (1 a 31) quando o gasto ou conta se repete todo mes ("aluguel 1500 todo dia 5"), com paid=false e date = proximo vencimento. person = nome de quem te deve ("o Joao me deve 50": fin_kind=income, paid=false, person=Joao, title=o motivo ou Emprestimo). period = current (mes financeiro atual, padrao), previous (mes anterior), today, yesterday ou week (ultimos 7 dias). keywords = palavras-chave separadas por virgula (category_create). budget_amount = valor do orcamento (budget_set). closing_day = dia 1 a 28 (closing_set). Em pay, title = nome da conta ou da pessoa (vazio se for a unica pendente ou a mais atrasada). Use so os campos que se aplicam e null nos outros.',
  'FINANCAS categorias: category = nome de uma categoria deste usuario; category_stated=true SOMENTE se o usuario disse a categoria. Categorias deste usuario: ' + (user.fin_cats || 'Alimentação, Mercado, Transporte, Moradia, Saúde, Lazer, Educação, Assinaturas, Compras, Outros') + '. Receitas: Recebimentos, Salário. NUNCA invente valor: se faltar o valor, use intent=clarify e pergunte. Foto de recibo, nota fiscal, cupom ou comprovante: intent=finance, fin_action=add, amount = TOTAL pago (so se estiver legivel com certeza; senao clarify), title = estabelecimento, date = data da nota em YYYY-MM-DD se legivel. Diferenca: "paguei 50 no mercado" e add; "ja paguei o aluguel" e pay.'
];"""
IMG_OLD = "Qualquer outra imagem: intent=chat, diga o que viu"
IMG_NEW = "Recibo, nota fiscal ou comprovante de pagamento: veja as regras de FINANCAS. Qualquer outra imagem: intent=chat, diga o que viu"
SCHEMA_OLD = "  pref_lead_minutes: NN('integer'), pref_summary_time: NN('string'), pref_supply_days: NN('integer')\n};"
SCHEMA_NEW = """  pref_lead_minutes: NN('integer'), pref_summary_time: NN('string'), pref_supply_days: NN('integer'),
  fin_action: { type: ['string', 'null'], enum: ['add', 'pay', 'correct', 'remove', 'summary', 'compare', 'top', 'by_day', 'budget_set', 'budget_status', 'category_create', 'category_list', 'closing_set', 'owed', null] },
  fin_kind: { type: ['string', 'null'], enum: ['expense', 'income', null] },
  amount: NN('number'), category: NN('string'), category_stated: NN('boolean'),
  method: { type: ['string', 'null'], enum: ['pix', 'debito', 'credito', 'dinheiro', 'boleto', null] },
  installments: NN('integer'), paid: NN('boolean'), recurring_day: NN('integer'), person: NN('string'),
  period: { type: ['string', 'null'], enum: ['current', 'previous', 'today', 'yesterday', 'week', null] },
  keywords: NN('string'), budget_amount: NN('number'), closing_day: NN('integer')
};"""
INTERPRET_FIN = """if (out.intent === 'finance') {
  out.fin_json = JSON.stringify({
    action: out.fin_action || '', kind: out.fin_kind || 'expense', amount: out.amount === undefined ? null : out.amount,
    title: out.title || '', category: out.category || '', category_stated: out.category_stated === true,
    method: out.method || '', installments: out.installments || 1, paid: out.paid === false ? false : true,
    date: (out.date && okDate.test(out.date)) ? out.date : '', recurring_day: out.recurring_day || null,
    person: out.person || '', period: out.period || 'current', keywords: out.keywords || '',
    budget_amount: out.budget_amount === undefined ? null : out.budget_amount, closing_day: out.closing_day || null,
    source: u.kind === 'photo' ? 'photo' : (ctx.via_audio ? 'audio' : 'text'), reply: out.reply || ''
  });
}
return [{ json: out }];"""
HELP_OLD0 = """    '6) Tarefas (Google Tasks): "anota na lista: ligar pro contador", "o que tenho nas tarefas?", "conclui a tarefa do contador".', '',"""
HELP_NEW0 = """    '6) Tarefas (Google Tasks): "anota na lista: ligar pro contador", "o que tenho nas tarefas?", "conclui a tarefa do contador".',
    '7) Dinheiro: "gastei 42 no mercado" (texto, audio ou foto do recibo), "aluguel 1500 todo dia 5", "tenis 600 em 3x", "quanto gastei esse mes?", "orcamento de mercado 800", "compara com o mes passado", "o Joao me deve 50".', '',"""
HELP_OLD1 = """    'Quando eu avisar um lembrete, use os botoes: Feito, Adiar 1h ou Adiar amanha. Na hora de tomar um remedio: Tomei ou Pular hoje.',"""
HELP_NEW1 = """    '- "gastei 42 no mercado" / "recebi 3000 do freela" / "tenis 600 em 3x" / "aluguel 1500 todo dia 5"',
    '- "quanto gastei esse mes?" / "gastos por categoria" / "compara com o mes passado" / "maiores despesas" / "o que tenho a pagar?"',
    '- "orcamento de mercado 800" / "quanto resta do orcamento de lazer?" / "cria a categoria Pet com racao e veterinario" / "minhas categorias"',
    '- "ja paguei o aluguel" / "o Joao me deve 50" / "quem me deve?" / "corrige para 50" / "isso e Lazer" / "fecha dia 10"',
    'Quando eu avisar um lembrete, use os botoes: Feito, Adiar 1h ou Adiar amanha. Na hora de tomar um remedio: Tomei ou Pular hoje. Em gastos, o botao Desfazer apaga o ultimo lancamento.',"""
HELP_OLD2 = """'- Aviso de estoque: ' + user.supply_alert_days + ' dias antes de acabar (remedio: 7 dias)', '',"""
HELP_NEW2 = """'- Aviso de estoque: ' + user.supply_alert_days + ' dias antes de acabar (remedio: 7 dias)', '- Fechamento do mes financeiro: dia ' + user.fin_closing_day, '',"""
HELP_OLD3 = """'"resumo as 8h", "sempre me avise 30 min antes", "avise o estoque com 7 dias".'"""
HELP_NEW3 = """'"resumo as 8h", "sempre me avise 30 min antes", "avise o estoque com 7 dias", "fecha dia 10" (mes financeiro), "minhas categorias", "orcamentos".'"""



def build_nos():
    global nodes, byname
    # ---------- FINANCAS: nos novos ----------
    def tgbtn(name,pos,buttons):
        return {"name":name,"type":"n8n-nodes-base.telegram","typeVersion":1.2,"position":pos,
          "parameters":{"resource":"message","operation":"sendMessage","chatId":"={{ $('Preparar envio').first().json.chat_id }}","text":"={{ $('Preparar envio').first().json.text }}",
            "replyMarkup":"inlineKeyboard","inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":t,"additionalFields":{"callback_data":"="+cb+"{{ $('Preparar envio').first().json.rid }}"}} for t,cb in buttons]}}]},
            "additionalFields":{"appendAttribution":False}}}
    nodes += [
     {"name":"Executar financas","type":"n8n-nodes-base.postgres","typeVersion":2.6,"position":[4480,3312],
      "parameters":{"operation":"executeQuery","query":"SELECT agente.f_fin($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":"={{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.fin_json ] }}"}}},
     {"name":"Resposta das financas","type":"n8n-nodes-base.code","typeVersion":2,"position":[4704,3312],
      "parameters":{"mode":"runOnceForAllItems","language":"javaScript","jsCode":"const a = $('Interpretar resposta').first().json;\nconst r = $input.first().json.r || {};\nreturn [{ json: { chat_id: a.chat_id, text: r.text || 'Nao consegui registrar agora. Tente de novo.', kb: r.kb || 'none', rid: r.rid || 0, state: '' } }];"}},
     tgbtn('Enviar com desfazer',[6272,2256],[('Desfazer','fundo:')]),
     tgbtn('Enviar com confirmar',[6272,2448],[('Confirmar','fok:'),('Cancelar','fno:')]),
     tgbtn('Enviar com apagar',[6272,2640],[('Sim, apagar','fdel:'),('Nao','fkeep:')]),
    ]
    byname={n['name']:n for n in nodes}
    # roteador: nova regra antes do fallback
    rt=byname['Roteador de intencao']['parameters']['rules']['values']
    rt.append({"outputKey":"financas","renameOutput":True,"conditions":{"options":{"caseSensitive":True,"leftValue":"","typeValidation":"strict"},"conditions":[{"leftValue":"={{ $json.intent }}","operator":{"type":"string","operation":"equals"},"rightValue":"finance"}],"combinator":"and"}})
    outs=conns['Roteador de intencao']['main']
    outs.insert(11,[{'node':'Executar financas','type':'main','index':0}])
    setc('Executar financas',['Resposta das financas'])
    setc('Resposta das financas',['Preparar envio'])
    # teclados
    kt=byname['Qual teclado?']['parameters']['rules']['values']
    for key in ('fin_undo','fin_confirm','fin_delete'):
        kt.append({"outputKey":key.replace('_',' '),"renameOutput":True,"conditions":{"options":{"caseSensitive":True,"leftValue":"","typeValidation":"strict"},"conditions":[{"leftValue":"={{ $('Preparar envio').first().json.kb }}","operator":{"type":"string","operation":"equals"},"rightValue":key}],"combinator":"and"}})
    ko=conns['Qual teclado?']['main']
    ko[3:3]=[[{'node':'Enviar com desfazer','type':'main','index':0}],[{'node':'Enviar com confirmar','type':'main','index':0}],[{'node':'Enviar com apagar','type':'main','index':0}]]


INTENT = Intent(
    name='finance',
    user_cols=['u.fin_closing_day', "(SELECT string_agg(c.name, ', ' ORDER BY c.name) FROM agente.fin_categories c WHERE c.user_id = u.id AND c.kind = 'expense') AS fin_cats"],
    edits=[
        Edit('Montar pedido a IA', 'jsCode', HINT_OLD, HINT_NEW),
        Edit('Montar pedido a IA', 'jsCode', RULES_OLD, FIN_RULES),
        Edit('Montar pedido a IA', 'jsCode', IMG_OLD, IMG_NEW),
        Edit('Montar pedido a IA', 'jsCode', SCHEMA_OLD, SCHEMA_NEW),
        # JSON do modulo: entra no fim de 'Interpretar resposta', antes do return final
        Edit('Interpretar resposta', 'jsCode', "return [{ json: out }];", INTERPRET_FIN),
        Edit('Resposta do comando', 'jsCode', HELP_OLD0, HELP_NEW0),
        Edit('Resposta do comando', 'jsCode', HELP_OLD1, HELP_NEW1),
        Edit('Resposta do comando', 'jsCode', HELP_OLD2, HELP_NEW2),
        Edit('Resposta do comando', 'jsCode', HELP_OLD3, HELP_NEW3),
    ],
)


INTENT_NOS = Intent(name='finance.nos', extends='finance', build=build_nos)
INTENTS = [INTENT, INTENT_NOS]
