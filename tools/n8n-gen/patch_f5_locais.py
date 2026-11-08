# ---------- Locais: pergunta de endereco quando o local nao e conhecido, e /locais ----------
# Depende de db/023_locais_pergunta.sql (place_pending, f_place_is_name, f_place_cb, f_command_data com 'locais').

# 1,2,4) teclado place_ask, caminho de local desconhecido em Interpretar resposta e regra ENDERECO DE LOCAL: intents/evento_locais.py
from intents import REGISTRY
REGISTRY.apply('create_event.locais', globals())

# 3) Resposta do comando: /locais e /start citando /locais
rc = byname['Resposta do comando']['parameters']['jsCode']
rc = rep(rc, "} else if (cmd === '/contatos') {",
         "} else if (cmd === '/locais') {\n  text = dados.locais || 'Nao consegui ler seus locais agora. Tente de novo.';\n} else if (cmd === '/contatos') {")
rc = rep(rc, "Outros comandos: /config (suas preferencias) e /contatos (contatos, grupos e locais).', '',",
         "Outros comandos: /config (suas preferencias), /contatos (contatos, grupos e locais) e /locais (so os locais salvos).', '',")
rc = rep(rc, "Eu uso o endereco e o grupo, pergunto so a hora e confirmo antes de enviar o convite.', '',",
         "Eu uso o endereco e o grupo, pergunto so a hora e confirmo antes de enviar o convite. Se o lugar nao estiver salvo, eu pergunto o endereco e salvo para a proxima vez.', '',")
byname['Resposta do comando']['parameters']['jsCode'] = rc
