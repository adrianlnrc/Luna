# ---------- M4 (onda 2): custo de IA (/custo) e lembretes anuais ----------
# Depende de agente-telegram/db/028_custo_ia_anuais.sql (ai_usage, ai_pricing, f_ai_log, f_ai_cost_text, f_command_data com 'custo',
# repeat_rule 'yearly' em f_reminder_create_ex_base / f_reminder_advance, f_menu).
# FORA da lista do gen.py (o agente de integracao adiciona antes de patch_zz_compact.py, depois de patch_f6_correcoes.py).
#
# ANCORAS ALTERADAS (todas via rep(), texto exato do estado gerado depois de patch_f6_correcoes.py):
#   Montar pedido a IA (NEW):
#     - "'clarify', 'chat'] }," (enum de intent)           -> insere 'ai_cost' antes de 'clarify'
#     - "enum: ['daily', 'weekly', 'monthly', null]"        -> acrescenta 'yearly' em repeat_freq
#     - "  'FINANCAS categorias: "                           -> 2 regras estaticas novas antes dela (vao para rules.json)
#   Interpretar resposta:
#     - "original_text: u.text };"                           -> bloco que acrescenta ai_kind/ai_model/ai_tin/ai_tout/ai_est ao 'base'
#     - "const out = Object.assign({}, base, g);"            -> estimativa de tokens quando a OpenAI nao devolveu usage
#   Resposta do comando:
#     - "} else if (cmd === '/contatos') {"                  -> ramo /custo
#   Nos 'OpenAI interpreta texto|foto|PDF': parametro simplify passa a false (a OpenAI so devolve usage fora do modo simplificado).
#   Conexoes: Interpretar resposta -> Roteador de intencao vira Interpretar resposta -> Registrar uso de IA -> Restaurar interpretacao -> Roteador de intencao.
#   Roteador de intencao: nova regra 'custo ia' (intent ai_cost) via add_route.
# SCHEMA DA IA: so um valor novo no enum de intent ('ai_cost') e 'yearly' no enum de repeat_freq; nenhum campo novo.
# NOS NOVOS: Registrar uso de IA, Restaurar interpretacao, Consultar custo de IA, Resposta do custo de IA.
byname = _refresh()

# ===== 1) OpenAI devolve usage so com simplify=false (com true so vem o texto da mensagem) =====
_oa = [n for n in nodes if n['name'] in ('OpenAI interpreta texto', 'OpenAI interpreta foto', 'OpenAI interpreta PDF')]
assert len(_oa) == 3, len(_oa)
for _n in _oa:
    assert _n['parameters'].get('simplify') is True, _n['name']
    _n['parameters']['simplify'] = False

# ===== 2) Interpretar resposta: dados do consumo (real quando ha usage; estimado quando ha resposta mas nao ha usage) =====
ir = byname['Interpretar resposta']['parameters']['jsCode']
ir = rep(ir, "original_text: u.text };", """original_text: u.text };
{
  let tipoIA = 'texto';
  if (ctx.via_pdf === true) { tipoIA = 'pdf'; } else if (ctx.via_photo === true) { tipoIA = 'foto'; } else if (ctx.via_audio === true) { tipoIA = 'voz'; }
  base.ai_kind = tipoIA;
  base.ai_model = String(ctx.modelo || '');
  base.ai_tin = null; base.ai_tout = null; base.ai_est = false;
  if (r && r.usage && typeof r.usage.input_tokens === 'number') {
    base.ai_tin = r.usage.input_tokens;
    base.ai_tout = (typeof r.usage.output_tokens === 'number') ? r.usage.output_tokens : 0;
  }
}""")
ir = rep(ir, "const out = Object.assign({}, base, g);", """const out = Object.assign({}, base, g);
if (out.ai_tin === null) {
  out.ai_tin = Math.ceil((String(ctx.instrucoes || '').length + String(ctx.prompt || '').length + String(ctx.schema_json || '').length) / 4);
  out.ai_tout = Math.ceil(JSON.stringify(g).length / 4);
  out.ai_est = true;
}""")
assert '\\' not in ir and '`' not in ir
byname['Interpretar resposta']['parameters']['jsCode'] = ir

# ===== 3) Registro do consumo: Interpretar -> Registrar uso -> Restaurar -> Roteador =====
# (o gerador do SDK so aceita uma saida por no comum; o no 'Restaurar interpretacao' devolve o JSON original, entao o roteador le o mesmo $json de antes)
assert conns['Interpretar resposta']['main'] == [[{'node': 'Roteador de intencao', 'type': 'main', 'index': 0}]], conns['Interpretar resposta']
_ipos = byname['Interpretar resposta']['position']
_sem = "$json.ai_tin === null || $json.ai_tin === undefined ? '' : $json.ai_tin"
_semo = "$json.ai_tout === null || $json.ai_tout === undefined ? '' : $json.ai_tout"
_reg = pg_node('Registrar uso de IA',
               "SELECT agente.f_ai_log($1::bigint, $2::text, $3::text, NULLIF($4::text, '')::int, NULLIF($5::text, '')::int, $6::boolean) AS r",
               "={{ [ $json.user_id, $json.ai_kind || 'texto', $json.ai_model || '', " + _sem + ", " + _semo + ", $json.ai_est === true ] }}",
               [_ipos[0] + 224, _ipos[1] + 96])
_reg['onError'] = 'continueRegularOutput'
_reg['alwaysOutputData'] = True
nodes.append(_reg)
nodes.append(code_node('Restaurar interpretacao',
                       "return [{ json: $('Interpretar resposta').first().json }];",
                       [_ipos[0] + 448, _ipos[1]]))
_refresh()
setc('Interpretar resposta', ['Registrar uso de IA'])
setc('Registrar uso de IA', ['Restaurar interpretacao'])
setc('Restaurar interpretacao', ['Roteador de intencao'])

# ===== 5) Schema e regras de prompt =====
mp = byname[NEW]['parameters']['jsCode']
from intents import REGISTRY
REGISTRY.apply('ai_cost', globals())   # enum, regras CUSTO DE IA/LEMBRETE ANUAL, nos 'Consultar custo de IA' e rota
mp = byname[NEW]['parameters']['jsCode']
mp = rep(mp, "enum: ['daily', 'weekly', 'monthly', null]", "enum: ['daily', 'weekly', 'monthly', 'yearly', null]")
byname[NEW]['parameters']['jsCode'] = mp

# ===== 6) Comando /custo =====
rc = byname['Resposta do comando']['parameters']['jsCode']
rc = rep(rc, "} else if (cmd === '/contatos') {",
         "} else if (cmd === '/custo') {\n  text = dados.custo || 'Nao consegui calcular o custo agora. Tente de novo.';\n} else if (cmd === '/contatos') {")
byname['Resposta do comando']['parameters']['jsCode'] = rc
