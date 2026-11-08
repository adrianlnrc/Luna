# ---------- M5 (fase 5): pesquisa com fonte citada e aviso de custo sem bloqueio ----------
# Depende de db/029_pesquisa.sql (f_menu com a area 'pesquisa', ai_usage, ai_pricing, f_research_gate/f_research_log)
# e do sub-workflow "Agente | Pesquisa" (id abaixo, codigo em subworkflows/gen_pesquisa.py -> pesquisa.sdk.js).
# Entra em gen.py DEPOIS de patch_f6_correcoes.py (usa o campo html de 'Preparar envio') e ANTES de patch_zz_compact.py.
#
# ANCORAS ALTERADAS (todas via rep, uma ocorrencia):
#   [Montar pedido a IA] "'clarify', 'chat'] },"                      -> acrescenta o intent 'research' ao enum
#   [Montar pedido a IA] "new_name: NN('string')\n};"                 -> acrescenta research_query (nulavel) ao schema
#   [Montar pedido a IA] ", clarify (falta informacao essencial"      -> lista de INTENTS (regra estatica) ganha 'research'
#   [Montar pedido a IA] "  'FINANCAS categorias: "                    -> nova regra estatica PESQUISA (vai para rules.json)
#   [Montar pedido a IA] regra FORA DO ESCOPO (patch_f6): "pesquisar preco, indicar restaurante ou lugar, ... previsao do tempo"
#                        sai do fora-de-escopo (agora e pesquisa)
#   [Interpretar resposta] "if (out.intent === 'finance') {"          -> normaliza research_query (so a pergunta, max 500)
#   [Enviar com menu] teclado: reconstroi as linhas (2 por linha) com o botao 'Pesquisa' (mn:pesquisa) no fim
# MUDANCAS DE SCHEMA DA IA: intent += 'research'; novo campo research_query: ['string','null'].
# NOS NOVOS: 'Pesquisa: executar' (Execute Workflow), 'Pesquisa: resposta' (Code); nova saida 'pesquisa' no 'Roteador de intencao'.
_refresh()

# 1) Intencao research (registro: intents/research.py): enum, hint, research_query (nulavel), regra PESQUISA, normalizacao da
#    pergunta em 'Interpretar resposta', nos 'Pesquisa: executar/resposta' (sub-workflow -> resposta -> Preparar envio) e rota.
from intents import REGISTRY
REGISTRY.apply('research', globals())

# 2) Pesquisa sai do fora-de-escopo (regra do patch_f6)
mp = byname[NEW]['parameters']['jsCode']
mp = rep(mp, "reservar passagem ou hotel, pesquisar preco, indicar restaurante ou lugar, comprar ou pedir algo, previsao do tempo:",
         "reservar passagem ou hotel, comprar ou pedir algo:")
byname[NEW]['parameters']['jsCode'] = mp

# 5) Menu: botao Pesquisa (mn:pesquisa), refazendo as linhas de 2 em 2
_kb = byname['Enviar com menu']['parameters']['inlineKeyboard']['rows']
_flat = [b for row in _kb for b in row['row']['buttons']]
if not any(b['additionalFields']['callback_data'] == '=mn:pesquisa' for b in _flat):
    _flat.append({"text": "Pesquisa", "additionalFields": {"callback_data": "=mn:pesquisa"}})
byname['Enviar com menu']['parameters']['inlineKeyboard']['rows'] = [{"row": {"buttons": _flat[i:i + 2]}} for i in range(0, len(_flat), 2)]
_refresh()
