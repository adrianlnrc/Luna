# ---------- Descoberta de funcoes: /menu com botoes por area, /ajuda curto, /start apontando o menu ----------
# Depende de db/022_menu.sql (f_menu, f_callback com prefixo mn, f_tip).

# 1) Teclado do menu (callback mn:<area>, tratado pelo banco)
add_kb('menu', [('Lembretes', 'mn:lembretes'), ('Agenda', 'mn:agenda'),
                ('Tarefas', 'mn:tarefas'), ('Remedios', 'mn:remedios'),
                ('Dinheiro', 'mn:dinheiro'), ('Contatos e locais', 'mn:pessoas'),
                ('Documentos', 'mn:docs'), ('Listas e notas', 'mn:listas'),
                ('Projetos', 'mn:projetos'), ('Resumos', 'mn:resumos'),
                ('Ajustes', 'mn:ajustes'), ('Voz, foto e PDF', 'mn:entrada')], row_size=2)

# 2) Comandos: /menu e /ajuda mostram o menu; /start aponta para ele
rc = byname['Resposta do comando']['parameters']['jsCode']
_a = rc.index("} else if (cmd === '/ajuda' || cmd === '/help') {")
_b = rc.index("} else if (cmd === '/config') {")
rc = rc[:_a] + ("} else if (cmd === '/menu' || cmd === '/ajuda' || cmd === '/help') {\n"
                "  text = 'O que eu faco' + NL + 'Toque numa area para ver o que da para pedir, com exemplos. Voce pode falar do jeito que fala no dia a dia, por texto ou audio.';\n"
                "  kb = 'menu';\n") + rc[_b:]
rc = rep(rc, "'Comandos: /config (suas preferencias), /contatos (contatos, grupos e locais) e /ajuda.', '',",
         "'Para ver tudo o que eu faco, com exemplos de cada area, toque em /menu. Outros comandos: /config (suas preferencias) e /contatos (contatos, grupos e locais).', '',")
byname['Resposta do comando']['parameters']['jsCode'] = rc

# 3) Regra de prompt: pedido de ajuda em linguagem natural aponta para o menu
mp = byname[NEW]['parameters']['jsCode']
mp = rep(mp, "  'FINANCAS categorias: ", """  'AJUDA: se o usuario perguntar o que voce faz, o que sabe fazer, como usar, pedir ajuda, menu ou exemplos, use intent=chat e reply curto: Toque em /menu para ver tudo o que eu faco, area por area, com exemplos.',
  'FINANCAS categorias: """)
byname[NEW]['parameters']['jsCode'] = mp
