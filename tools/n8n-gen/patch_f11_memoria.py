# ---------- F11 / Etapa 3 da secretaria natural: memoria unificada, oferta de salvar, sugestao diaria ----------
# Depende de db/035_memoria_unificada.sql (APLICADO em producao). Contrato: agente-telegram/db/035_contrato.md.
# Entra em gen.py DEPOIS de patch_f10_acoes.py e ANTES de patch_zz_compact.py.
#
# A Intencao memory_manage (enum, schema, regras MEMORIA/PESSOA OU LUGAR/GERIR MEMORIA, contexto do prompt, mem_json/offer_json/mm_json,
# linha "Anotei:", Buscar usuario, comandos /memoria e /config, nos 'Memoria: *' e rota) agora esta declarada em intents/memory_manage.py
# e injetada pelo registro. Aqui ficam so os ajustes que NAO sao de uma Intencao:
#   - reconcilia o rules.json AO VIVO (v60): regra 8 (complete_task) e regra TOM, que so existiam no Redis.
# (cadeia Pos-envio removida a pedido: oferta de salvar / sugestao do dia desligadas)
from intents import REGISTRY, once, safe_rule
_refresh()

mp = byname[NEW]['parameters']['jsCode']
mp = once(mp, "list_tasks nao precisa de campos.",
          'list_tasks nao precisa de campos. "ja paguei/ja fiz/ja resolvi X, pode riscar/tirar/marcar como feito" e complete_task (title = X), nao finance; finance so se o usuario falar de valor gasto ou registrar despesa.')
R_TOM = safe_rule("TOM do reply (quando voce escrever): portugues do Brasil informal de secretaria, frases curtas, no maximo 1 emoji, sem repetir o que o usuario disse. Nunca prometa o que nao foi gravado.")
mp = once(mp, "  'FINANCAS categorias: ", "  '" + R_TOM + "',\n  'FINANCAS categorias: ")
byname[NEW]['parameters']['jsCode'] = mp

REGISTRY.apply('memory_manage', globals())
byname = _refresh()
