# ---------- FASE 2a: limite, metas, planejamento, preferencias ----------
byname={n['name']:n for n in nodes}
bu=byname['Buscar usuario']['parameters']
bu['query']=rep(bu['query']," FROM agente.users u WHERE",", u.nickname, u.no_emoji FROM agente.users u WHERE")
mp=byname[NEW]['parameters']['jsCode']
mp=rep(mp,"assistente pessoal de ' + user.name + ' no Telegram","assistente pessoal de ' + (user.nickname || user.name) + ' no Telegram")
mp=rep(mp,"'Sempre preencha transcript","(user.no_emoji ? 'NUNCA use emoji em reply.' : 'Emoji so quando combinar, poucos.'),\n  'Sempre preencha transcript")
byname[NEW]['parameters']['jsCode']=mp
# Planejamento financeiro (finance) e preferencias novas (set_preference): intents/prefs_fin.py
from intents import REGISTRY
REGISTRY.apply('finance.planejamento', globals())
REGISTRY.apply('set_preference.prefs', globals())
