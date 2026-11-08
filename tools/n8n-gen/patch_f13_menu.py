# ---------- Fase 13: menu reformulado (9 areas, "Ver mais", tela inicial com correcao) ----------
# Depende de db/036_menu_secretaria.sql (f_menu devolve kb 'menu' | 'menu_area' | 'menu_mais' e rid = numero da area 1..9).
# O que muda no workflow:
#   [Enviar com menu]       9 botoes na ordem nova (callbacks mn:lemb, tar, din, rem, proj, doc, pess, foto, aj)
#   [Enviar com menu area]  NOVO: Ver mais (mn:mais<rid>) e Voltar ao menu (mn:inicio)
#   [Enviar com menu mais]  NOVO: Voltar a area (mn:a<rid>) e Menu (mn:inicio)
#   [Resposta do comando]   texto de /menu igual ao 'inicio' do banco; /start sem a dica falsa
# Os dois nos novos sao folhas (sem saida) ligadas apenas a 'Qual teclado?': nenhum fan-in novo.
import re as _re

# 1) botoes do menu inicial
_btns = [('Lembretes e agenda', 'mn:lemb'), ('Tarefas e listas', 'mn:tar'),
         ('Dinheiro', 'mn:din'), ('Remédios', 'mn:rem'),
         ('Projetos', 'mn:proj'), ('Documentos', 'mn:doc'),
         ('Pessoas e memória', 'mn:pess'), ('Fotos, áudio e pesquisa', 'mn:foto'),
         ('Ajustes', 'mn:aj')]
_flat = [{"text": t, "additionalFields": {"callback_data": "=" + cb}} for t, cb in _btns]
byname['Enviar com menu']['parameters']['inlineKeyboard']['rows'] = [{"row": {"buttons": _flat[i:i + 2]}} for i in range(0, len(_flat), 2)]

# 2) teclados das areas (rid = numero da area)
add_kb('menu_area', [('Ver mais', 'mn:mais{rid}'), ('Voltar ao menu', 'mn:inicio')], row_size=2)
add_kb('menu_mais', [('Voltar à área', 'mn:a{rid}'), ('Menu', 'mn:inicio')], row_size=2)

# 3) texto de /menu = texto 'inicio' do banco (lido do proprio 036 para nao divergir)
import os as _os
_dbdir = '../../agente-telegram/db' if _os.path.isdir('../../agente-telegram/db') else '../../db'
_sql = open(_dbdir + '/036_menu_secretaria.sql', encoding='utf-8').read()
_ini = _re.search(r'\$m\$(.*?)\$m\$', _sql, _re.S).group(1)
assert "'" not in _ini and '\\' not in _ini and '`' not in _ini and '${' not in _ini
_js_lines = ",\n    ".join("'" + l + "'" for l in _ini.split('\n'))
rc = byname['Resposta do comando']['parameters']['jsCode']
_a = rc.index("} else if (cmd === '/menu' || cmd === '/ajuda' || cmd === '/help') {")
_b = rc.index("} else if (cmd === '/config') {")
rc = rc[:_a] + ("} else if (cmd === '/menu' || cmd === '/ajuda' || cmd === '/help') {\n"
                "  text = [\n    " + _js_lines + "].join(NL);\n"
                "  kb = 'menu';\n") + rc[_b:]
# 4) /start: tira a dica falsa
_old = "Uma coisa por mensagem funciona melhor. Toque em /menu"
assert _old in rc
rc = rc.replace(_old, "Pode mandar varios pedidos juntos. Toque em /menu")
byname['Resposta do comando']['parameters']['jsCode'] = rc
_refresh()
