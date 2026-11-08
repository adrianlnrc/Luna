# Extensoes da Fase 2a: planejamento financeiro (limite, renda, metas) na intent finance e preferencias novas (apelido, emoji, fuso, resumos)
# na intent set_preference. Depende de db (agente.f_set_prefs, f_limit*, f_goal*, f_plan*).
from .core import Intent, Edit

R_PLAN = '  \'PLANEJAMENTO: budget_amount = valor do limite, da renda ou da meta (ou do deposito); title = nome da meta (goal_*; vazio se so existe uma); date = prazo da meta em YYYY-MM-DD ("ate dezembro" = dia 20 do mes citado se nao houver dia; goal_create e goal_edit); category = NOVO nome da meta (so em goal_edit quando renomear); keywords = manual quando a meta e so manual ("essa meta e so manual", "nao desconta automatico") ou auto para voltar ao automatico. Limite geral e diferente de orcamento de categoria: sem categoria citada, "limite" ou "no maximo X por mes" e limit_set. "Guardei X" e goal_deposit, nao add.\',\n'
R_PREF = '  \'PREFERENCIAS: set_preference com pref_nickname ("me chama de Re"), pref_no_emoji (true para parar de usar emoji, false para voltar), pref_timezone (nome IANA: "mudei pra Lisboa" = Europe/Lisbon), pref_evening (off, on ou HH:MM do resumo do fim do dia) e pref_morning (off ou on para o resumo da manha; para mudar o horario use pref_summary_time). "Para de mandar o resumo da manha" = pref_morning off. Use null nos campos que nao se aplicam.\',\n'


def build_prefs():
    global byname
    sp=byname['Salvar preferencias']['parameters']
    sp['query']="SELECT agente.f_set_prefs($1::bigint, $2::jsonb) AS r"
    sp['options']['queryReplacement']="={{ [ $('Interpretar resposta').first().json.user_id, JSON.stringify({ lead: $('Interpretar resposta').first().json.pref_lead_minutes, summary: $('Interpretar resposta').first().json.pref_morning === 'off' ? 'off' : ($('Interpretar resposta').first().json.pref_summary_time || ($('Interpretar resposta').first().json.pref_morning === 'on' ? 'on' : null)), supply_days: $('Interpretar resposta').first().json.pref_supply_days, nickname: $('Interpretar resposta').first().json.pref_nickname, no_emoji: $('Interpretar resposta').first().json.pref_no_emoji, timezone: $('Interpretar resposta').first().json.pref_timezone, evening: $('Interpretar resposta').first().json.pref_evening }) ] }}"
    byname['Resposta das preferencias']['parameters']['jsCode']="const a = $('Interpretar resposta').first().json;\nconst r = $input.first().json.r || {};\nreturn [{ json: { chat_id: a.chat_id, kb: 'none', rid: 0, state: '', text: r.text || 'Nao consegui salvar agora. Tente de novo.' } }];"


INTENTS = [
    Intent(name='finance.planejamento', extends='finance', raw_rules=R_PLAN,
           edits=[
               Edit('Montar pedido a IA', 'jsCode', "closing_set (dia em que fecha o mes financeiro), owed (quem me deve).",
            "closing_set (dia em que fecha o mes financeiro), owed (quem me deve), limit_set (limite geral de gasto do mes: quero gastar no maximo 3000), limit_status (quanto ainda posso gastar no mes), limit_clear (tirar o limite geral), income_set (minha renda e 5000), plan_status (meu planejamento, quanto sobra pra gastar, visao do mes), goal_create (meta de economia: juntar 800 ate dezembro pro presente), goal_deposit (guardei 100 pra meta), goal_withdraw (tirei 50 da meta), goal_status (minhas metas, como esta a meta), goal_edit (mudar valor, prazo, nome ou modo da meta), goal_remove (apagar a meta)."),
               Edit('Montar pedido a IA', 'jsCode', "'closing_set', 'owed', null] },",
            "'closing_set', 'owed', 'limit_set', 'limit_status', 'limit_clear', 'income_set', 'plan_status', 'goal_create', 'goal_deposit', 'goal_withdraw', 'goal_status', 'goal_edit', 'goal_remove', null] },")],
           ),
    Intent(name='set_preference.prefs', extends='set_preference', raw_rules=R_PREF,
           edits=[
               Edit('Montar pedido a IA', 'jsCode', "set_preference (mudar preferencias: aviso padrao antes, horario do resumo, dias de aviso do estoque)",
            "set_preference (mudar preferencias: aviso padrao antes, horario do resumo da manha ou do fim do dia, ligar ou desligar esses resumos, dias de aviso do estoque, apelido, parar de usar emoji, fuso horario)"),
               Edit('Montar pedido a IA', 'jsCode', "pref_supply_days: NN('integer'),",
            "pref_supply_days: NN('integer'), pref_nickname: NN('string'), pref_no_emoji: NN('boolean'), pref_timezone: NN('string'), pref_evening: NN('string'), pref_morning: NN('string'),")],
           build=build_prefs),
]
