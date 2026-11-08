# ---------- M3 (onda 2): relatorios das financas em CSV e Excel ----------
# Depende de db/027_relatorios.sql (f_report_data, f_report_action, f_fin embrulhado: fin_action=report
# devolve {text, report:{period,month,format,keywords}}) e do sub-workflow "Agente | Relatorio" (id abaixo).
# Ancoras alteradas (todas com rep, devem ser unicas):
#   - Montar pedido a IA: "'closing_set', 'owed'," (enum fin_action), "keywords: NN('string'), budget_amount: NN('number'), closing_day: NN('integer'),"
#     (campo report_format) e "  'FINANCAS categorias: " (regra de prompt estatica; vai para rules.json pelo patch_zz_compact)
#   - Interpretar resposta: "month: out.month || '', alert_days: out.alert_days || null," (report_format no fin_json)
#   - conns['Executar financas'] (agora segue para o IF 'Tem relatorio?')
# Nos novos: 'Tem relatorio?' (IF) e 'Chamar relatorio' (Execute Workflow). A saida do sub-workflow ({r:{text,kb,rid}})
# volta para 'Resposta das financas', que ja le $input.first().json.r.
from intents import REGISTRY
REGISTRY.apply('finance.relatorio', globals())
