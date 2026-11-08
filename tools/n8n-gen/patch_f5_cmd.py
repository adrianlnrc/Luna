# ---------- Fase 4b: locais salvos, /contatos, /config completo, /start e /ajuda ----------
# Depende de db/021_locais_comandos.sql (f_ai_places, f_ai_groups, f_command_data, f_places).

# 1-4) Intencao contact_manage, locais e grupos salvos (coluna places_txt/groups_txt, regras, schema, contact_json): intents/contatos_locais.py
from intents import REGISTRY
REGISTRY.apply('contact_manage.locais', globals())

# 5) Novo no: dados dos comandos (/config e /contatos) lidos do banco
nodes.append({"name": "Comando: dados", "type": "n8n-nodes-base.postgres", "typeVersion": 2.6, "position": [4480, 192],
              "onError": "continueRegularOutput", "alwaysOutputData": True,
              "parameters": {"operation": "executeQuery", "query": "SELECT agente.f_command_data($1::bigint) AS r",
                             "options": {"queryReplacement": "={{ [ $('Buscar usuario').first().json.id ] }}"}}})
_refresh()
conns['Tipo de mensagem']['main'][1] = [{'node': 'Comando: dados', 'type': 'main', 'index': 0}]
setc('Comando: dados', ['Resposta do comando'])

# 6) Resposta do comando: /start, /ajuda, /config e /contatos
rc = byname['Resposta do comando']['parameters']['jsCode']
rc = rep(rc, "const cmd = (u.text.split(' ')[0] || '').split('@')[0].toLowerCase();",
         "const cmd = (u.text.split(' ')[0] || '').split('@')[0].toLowerCase();\n"
         "let dados = {};\ntry { dados = $('Comando: dados').first().json.r || {}; } catch (e) { dados = {}; }")
# /config e /contatos vindos do banco
_a = rc.index("} else if (cmd === '/config') {")
_b = rc.index("} else {\n  text = 'Nao conheco esse comando.")
rc = rc[:_a] + ("} else if (cmd === '/config') {\n  text = dados.config || 'Nao consegui ler suas preferencias agora. Tente de novo.';\n"
                "} else if (cmd === '/contatos') {\n  text = dados.contatos || 'Nao consegui ler seus contatos agora. Tente de novo.';\n") + rc[_b:]
# /start
rc = rep(rc, "(mando o convite do Google Agenda, com link do Meet se pedir).', '',",
         "(mando o convite do Google Agenda, com link do Meet se pedir).', '',\n"
         "    'Compromisso com local e grupo salvos: salve uma vez (\"o local igreja e Rua das Flores, 120\" e \"cria o grupo familia com Ana e Bia\") e depois diga \"festa da igreja na sexta com a familia\". Eu uso o endereco e o grupo, pergunto so a hora e confirmo antes de enviar o convite.', '',")
rc = rep(rc, "'Comandos: /config (suas preferencias) e /ajuda.', '',",
         "'Comandos: /config (suas preferencias), /contatos (contatos, grupos e locais) e /ajuda.', '',")
# /ajuda
rc = rep(rc, "    '- \"lista de mercado: arroz, cafe e detergente\"",
         "    '- \"o local igreja e Rua das Flores, 120\" / \"meus locais\" / \"tira o local igreja\"',\n"
         "    '- \"festa da igreja na sexta com a familia\" (uso o local e o grupo salvos, pergunto so a hora e confirmo antes de enviar o convite)',\n"
         "    '- /contatos mostra contatos, grupos e locais; /config mostra suas preferencias',\n"
         "    '- \"lista de mercado: arroz, cafe e detergente\"")
byname['Resposta do comando']['parameters']['jsCode'] = rc
