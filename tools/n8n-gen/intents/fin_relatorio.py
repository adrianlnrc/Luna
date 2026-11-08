# Extensao da intent finance (M3, onda 2): relatorios das financas em CSV e Excel (fin_action=report).
# Depende de db/027_relatorios.sql e do sub-workflow "Agente | Relatorio".
from .core import Intent, Edit

RAW_RULES = """  'RELATORIO FINANCEIRO: pedido de relatorio, extrato, planilha ou exportar gastos e lancamentos em arquivo (me manda o relatorio do mes, extrato de outubro em Excel, exporta meus gastos do ano em csv, relatorio para o imposto de renda) = intent=finance, fin_action=report. report_format = csv se pedir csv, xlsx se pedir Excel ou planilha, pdf se pedir PDF, null se nao disse. Periodo: period=current (mes atual) ou previous (mes passado); mes citado = month YYYY-MM; ANO inteiro (os gastos do ano, de 2025) = month com 4 digitos (ex.: 2026); imposto de renda ou IR sem periodo = ano atual. Para imposto de renda preencha keywords=imposto de renda (o sistema filtra Saude e Educacao). Preencha reply com texto vazio. Diferenca: quanto gastei, resumo e total sao fin_action=summary (resposta na conversa); relatorio, extrato, planilha, exportar ou arquivo sao report.',
"""


def build():
    global nodes, byname
    RELATORIO_WF_ID = 'QrxbGEgdoP56QszP'
    nodes.append(ifnode('Tem relatorio?', "={{ ($json.r && $json.r.report) ? 'sim' : 'nao' }}", 'string', 'equals', 'sim', [4592, 3200]))
    _I = "$('Interpretar resposta').first().json."
    nodes.append(exec_wf('Chamar relatorio', RELATORIO_WF_ID, {
        "user_id": "={{ String(" + _I + "user_id) }}",
        "chat_id": "={{ String(" + _I + "chat_id) }}",
        "period": "={{ String($json.r.report.period || 'current') }}",
        "month": "={{ String($json.r.report.month || '') }}",
        "format": "={{ String($json.r.report.format || 'xlsx') }}",
        "keywords": "={{ String($json.r.report.keywords || '') }}"}, [4704, 3088]))
    byname = _refresh()
    conns['Executar financas'] = {'main': [[{'node': 'Tem relatorio?', 'type': 'main', 'index': 0}]]}
    conns['Tem relatorio?'] = {'main': [[{'node': 'Chamar relatorio', 'type': 'main', 'index': 0}],
                                        [{'node': 'Resposta das financas', 'type': 'main', 'index': 0}]]}
    conns['Chamar relatorio'] = {'main': [[{'node': 'Resposta das financas', 'type': 'main', 'index': 0}]]}
    byname = _refresh()


INTENT = Intent(
    name='finance.relatorio',
    extends='finance',
    raw_rules=RAW_RULES,
    edits=[
        Edit('Montar pedido a IA', 'jsCode', "'closing_set', 'owed',",
        "'closing_set', 'report', 'owed',"),
        Edit('Montar pedido a IA', 'jsCode', "keywords: NN('string'), budget_amount: NN('number'), closing_day: NN('integer'),",
        "keywords: NN('string'), budget_amount: NN('number'), closing_day: NN('integer'),\n  report_format: { type: ['string', 'null'], enum: ['csv', 'xlsx', 'pdf', null] },"),
        Edit('Interpretar resposta', 'jsCode', "month: out.month || '', alert_days: out.alert_days || null,",
        "month: out.month || '', alert_days: out.alert_days || null, report_format: out.report_format || '',")],
    build=build,
)
