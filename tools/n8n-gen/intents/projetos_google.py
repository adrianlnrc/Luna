# ---------- F8: espelho dos PROJETOS no Google Tarefas (banco = fonte de verdade; Google = espelho) ----------
# Roda DEPOIS de patch_projetos.py e ANTES de patch_zz_compact.py. Requer db/030_projetos_google.sql aplicado e o sub-workflow
# "Agente | Projetos Google" criado no n8n (tools/n8n-gen/subworkflows/projetos_google.sdk.js). O id do sub-workflow vem de
# PROJ_GOOGLE_WF_ID (variavel de ambiente) ou da constante abaixo.
# (movido para o registro: estagio 2 da Intencao project_manage; roda no mesmo ponto de gen.py que o antigo patch)
from .core import Intent


def build():
    global nodes, byname
    import os as _os
    _refresh()
    PROJ_GOOGLE_WF_ID = _os.environ.get('PROJ_GOOGLE_WF_ID', 'G5N2OpaT2v6Pczcl')
    if PROJ_GOOGLE_WF_ID.startswith('TROCAR'):
        print('AVISO patch_f8_projetos_google: PROJ_GOOGLE_WF_ID nao definido; o workflow sai com id de mentira', file=sys.stderr)

    _UID = "$('Buscar usuario').first().json.id"

    # --- 1) leitura: antes de "como esta o projeto", "meus projetos" e "o que esta atrasado", traz o que foi concluido no Google ---
    _acao = "(JSON.parse($('Interpretar resposta').first().json.proj_json || '{}')).action"
    _plano_leitura = pg_node("Projetos: plano de leitura", "SELECT agente.f_proj_gt_plan($1::bigint, $2::jsonb) AS gt",
        "={{ [ " + _UID + ", (['list', 'show', 'overdue'].indexOf(" + _acao + ") >= 0) ? '{\"list\":true,\"push\":false}' : '{\"list\":false,\"push\":false}' ] }}",
        [4032, 4288])
    _plano_leitura['onError'] = 'continueRegularOutput'

    def _tem_ops(name, pos):
        return {"name": name, "type": "n8n-nodes-base.if", "typeVersion": 2.2, "position": pos,
          "parameters": {"conditions": {"options": {"caseSensitive": True, "leftValue": "", "typeValidation": "loose"},
            "conditions": [{"leftValue": "={{ ($json.gt && $json.gt.ops) ? $json.gt.ops.length : 0 }}",
                            "operator": {"type": "number", "operation": "gt"}, "rightValue": 0}], "combinator": "and"}}}

    def _google(name, pos):
        n = exec_wf(name, PROJ_GOOGLE_WF_ID,
            {"owner": "={{ $json.gt.owner }}", "ops": "={{ JSON.stringify($json.gt.ops) }}"}, pos)
        n['onError'] = 'continueRegularOutput'
        return n

    def _aplicar(name, pos):
        n = pg_node(name, "SELECT agente.f_proj_google_apply($1::bigint, $2::jsonb) AS r",
            "={{ [ " + _UID + ", JSON.stringify($input.first().json) ] }}", pos)
        n['onError'] = 'continueRegularOutput'
        return n

    # --- 2) escrita: depois de executar (texto ou botao), envia ao Google o que ficou pendente ---
    _plano_envio = pg_node("Projetos: plano de envio", "SELECT agente.f_proj_gt_plan($1::bigint, $2::jsonb) AS gt",
        "={{ [ " + _UID + ", '{\"push\":true,\"limit\":40}' ] }}", [4704, 4288])
    _plano_envio['onError'] = 'continueRegularOutput'

    # --- 3) botao pj*: so botoes de projeto passam pelo envio ao Google ---
    _gate_botao = {"name": "Projetos: botao de projeto?", "type": "n8n-nodes-base.if", "typeVersion": 2.2, "position": [1124, 3600],
      "parameters": {"conditions": {"options": {"caseSensitive": True, "leftValue": "", "typeValidation": "loose"},
        "conditions": [{"leftValue": "={{ String($('Normalizar update').first().json.cb_data || '') }}",
                        "operator": {"type": "string", "operation": "startsWith"}, "rightValue": "pj"}], "combinator": "and"}}}

    nodes += [
      _plano_leitura,
      _tem_ops("Projetos: ler do Google?", [4256, 4288]),
      _google("Projetos: Google (leitura)", [4480, 4400]),
      _aplicar("Projetos: aplicar leitura", [4704, 4400]),
      _plano_envio,
      _tem_ops("Projetos: enviar ao Google?", [4928, 4288]),
      _google("Projetos: Google (envio)", [5152, 4400]),
      _aplicar("Projetos: aplicar envio", [5376, 4400]),
      _gate_botao,
    ]
    _refresh()

    # ligacoes: roteador -> plano de leitura -> (ler?) -> Executar -> plano de envio -> (enviar?) -> Resposta
    _rt = conns['Roteador de intencao']['main']
    _hits = [o for o in _rt if any(t['node'] == 'Projetos: Executar' for t in o)]
    assert len(_hits) == 1, 'rota de projetos nao achada'
    for t in _hits[0]:
        if t['node'] == 'Projetos: Executar': t['node'] = 'Projetos: plano de leitura'
    setc('Projetos: plano de leitura', ['Projetos: ler do Google?'])
    conns['Projetos: ler do Google?'] = {'main': [[{'node': 'Projetos: Google (leitura)', 'type': 'main', 'index': 0}], [{'node': 'Projetos: Executar', 'type': 'main', 'index': 0}]]}
    setc('Projetos: Google (leitura)', ['Projetos: aplicar leitura'])
    setc('Projetos: aplicar leitura', ['Projetos: Executar'])
    setc('Projetos: Executar', ['Projetos: plano de envio'])
    setc('Projetos: plano de envio', ['Projetos: enviar ao Google?'])
    conns['Projetos: enviar ao Google?'] = {'main': [[{'node': 'Projetos: Google (envio)', 'type': 'main', 'index': 0}], [{'node': 'Projetos: Resposta', 'type': 'main', 'index': 0}]]}
    setc('Projetos: Google (envio)', ['Projetos: aplicar envio'])
    setc('Projetos: aplicar envio', ['Projetos: Resposta'])
    # Projetos: Resposta -> Preparar envio ja existe (patch_projetos)

    # botoes: tudo que hoje chega em "Resposta do botao" passa antes pelo gate (pj* -> plano de envio; resto -> Resposta do botao)
    _n = 0
    for _src, _v in list(conns.items()):
        if _src == 'Projetos: botao de projeto?': continue
        for _o in _v.get('main', []):
            for _t in _o:
                if _t['node'] == 'Resposta do botao':
                    _t['node'] = 'Projetos: botao de projeto?'; _n += 1
    assert _n >= 1, 'entrada de Resposta do botao nao achada'
    conns['Projetos: botao de projeto?'] = {'main': [[{'node': 'Projetos: plano de envio', 'type': 'main', 'index': 0}], [{'node': 'Resposta do botao', 'type': 'main', 'index': 0}]]}

    # --- 4) Projetos: Resposta serve ao texto e ao botao (le o resultado de quem rodou) ---
    _rc = byname['Projetos: Resposta']['parameters']['jsCode']
    _rc = rep(_rc, "const a = $('Interpretar resposta').first().json;\nconst r = $input.first().json.r || {};\n",
      "let r = {};\ntry { r = $('Projetos: Executar').first().json.r || {}; } catch (e1) { r = {}; }\n"
      "if (!r.text) { try { r = $('Executar botao').first().json.r || {}; } catch (e2) { r = {}; } }\n"
      "const a = $('Normalizar update').first().json;\n")
    _rc = rep(_rc, "state: '' }", "state: r.state || '' }")
    byname['Projetos: Resposta']['parameters']['jsCode'] = _rc
    _refresh()


INTENT = Intent(name='project_manage.google', extends='project_manage', build=build)
