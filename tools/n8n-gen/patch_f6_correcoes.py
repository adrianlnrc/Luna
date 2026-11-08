# ---------- Ciclo de correcoes (spec-ciclo-correcoes.md) ----------
# Depende de db/024_ciclo_correcoes.sql (f_fin com items, f_supply_manage, f_supply_cb, ask_total, duplicado, f_menu).
# Regras de prompt novas ficam aqui (o patch_zz_compact as move para rules.json).
byname = _refresh()

# ===== P1-a: parse mode HTML e escape em Preparar envio =====
# 'text' continua cru (vai para o historico); 'html' e o que o Telegram recebe.
byname['Preparar envio']['parameters']['jsCode'] = """const r = $input.first().json;
let text = String(r.text || 'Ok.');
if (text.length > 3900) { text = text.slice(0, 3900) + '...'; }
let extra = '';
try { extra = String($('Interpretar resposta').first().json.extra_requests || '').trim(); } catch (e) { extra = ''; }
while (extra.length && '.!, '.indexOf(extra.charAt(extra.length - 1)) >= 0) { extra = extra.slice(0, -1); }
if (extra.length > 2 && ['null', 'nenhum', 'nenhuma', 'nada', 'none'].indexOf(extra.toLowerCase()) < 0) {
  text = text + String.fromCharCode(10) + String.fromCharCode(10) + 'Também vi: ' + extra + '. Me manda isso separado que eu faço.';
}
const html = text.split('**').join('').split('&').join('&amp;').split('<').join('&lt;').split('>').join('&gt;');
return [{ json: { chat_id: r.chat_id, text: text, html: html, kb: r.kb || 'none', rid: r.rid || 0, state: r.state || '' } }];"""
for _n in nodes:
    if _n['type'] == 'n8n-nodes-base.telegram':
        _p = _n['parameters']
        if _p.get('operation') == 'sendMessage':
            assert _p['text'] == "={{ $('Preparar envio').first().json.text }}", _n['name']
            _p['text'] = "={{ $('Preparar envio').first().json.html }}"
            _p['additionalFields']['parse_mode'] = 'HTML'
        elif _p.get('operation') in ('sendPhoto', 'sendVideo', 'sendDocument'):
            _p['additionalFields']['parse_mode'] = 'HTML'
byname = _refresh()

# ===== Schema, regras e remedios (intents/correcoes.py): extra_requests, fin_items, supply_action, new_name; Resposta do lembrete/ajuste =====
from intents import REGISTRY
REGISTRY.apply('correcoes', globals())

# ===== /start curto e /menu com a dica =====
rc = byname['Resposta do comando']['parameters']['jsCode']
_a = rc.index("} else if (cmd === '/start') {")
_b = rc.index("} else if (cmd === '/menu' || cmd === '/ajuda' || cmd === '/help') {")
rc = rc[:_a] + """} else if (cmd === '/start') {
  const linhasStart = ['Oi, ' + user.name + '! Sou o seu assistente pessoal aqui no Telegram. Pode falar por texto ou audio.', '',
    'Alguns exemplos:',
    '- "me lembre amanha as 9h de passar no mercado"',
    '- "gastei 42 no mercado"',
    '- "reuniao sexta as 14h, me lembre 1h antes"',
    '- "me lembre de tomar losartana todo dia as 8h"',
    '- "lista de mercado: arroz, cafe e detergente"', '',
    'Uma coisa por mensagem funciona melhor. Toque em /menu para ver tudo, com exemplos de cada area.',
    '(Para entender suas mensagens eu uso a OpenAI.)'];
  if (user.onboarding_step !== 'done') {
    linhasStart.push('', 'Para comecar: a que horas voce quer receber o resumo da manha?');
    kb = 'summary_time';
  }
  text = linhasStart.join(NL);
""" + rc[_b:]
rc = rep(rc, "Voce pode falar do jeito que fala no dia a dia, por texto ou audio.';", "Voce pode falar do jeito que fala no dia a dia, por texto ou audio. Uma coisa por mensagem funciona melhor.';")
byname['Resposta do comando']['parameters']['jsCode'] = rc
byname = _refresh()
