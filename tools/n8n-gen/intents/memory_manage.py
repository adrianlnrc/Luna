# Intencao memory_manage (F11 / etapa 3 da secretaria natural): memoria unificada, oferta de salvar, comandos /memoria e /config.
# Depende de db/035_memoria_unificada.sql (APLICADO em producao). Contrato: agente-telegram/db/035_contrato.md.
# (cadeia Pos-envio removida a pedido: oferta de salvar / sugestao do dia desligadas)
# A regra TOM e a reconciliacao do rules.json ao vivo (nao sao desta intent) ficam em patch_f11_memoria.py.
from .core import Intent, Edit, Set

_ONERR = {"onError": "continueRegularOutput"}

# --- schema (campos proprios desta intent) ---
SCHEMA = """mem_facts: { type: ['array', 'null'], items: { type: 'object', properties: { texto: { type: 'string' }, tipo: { type: 'string', enum: ['habito', 'preferencia', 'fato', 'relacao'] } },
required: ['texto', 'tipo'], additionalProperties: false } },
new_person: NN('string'), new_person_rel: NN('string'), new_place: NN('string'),
mem_action: { type: ['string', 'null'], enum: ['forget', 'list', 'switch_on', 'switch_off', 'offer_yes', 'offer_no', null] }, mem_ref: NN('string')"""

# --- regras novas (curtas) ---
R_MEM = (
    "MEMORIA: o bloco MEMORIA (antes da mensagem atual) traz fatos que voce ja sabe do usuario; use-os para entender nomes e contexto e NAO os repita. "
    "mem_facts (ate 2) so quando a mensagem revela um fato DURADOURO e novo sobre o usuario ou sua vida: parentesco (Dona Marta e minha sogra), habito, preferencia, saude, alergia, rotina. "
    "Cada um: texto = frase curta e clara (Dona Marta e a sogra do usuario), tipo = habito, preferencia, fato ou relacao. Sensivel pode. "
    "NUNCA compromisso pontual, gasto, tarefa, lembrete, nem o que ja esta em MEMORIA. Se a mensagem so informa o fato, use intent=chat com reply vazio (o sistema avisa Anotei). Sem fato novo, mem_facts=null.")
R_OFERTA = (
    "PESSOA OU LUGAR CITADO: em create_reminder, create_event ou create_task que cita uma PESSOA pelo nome (Maria Luisa; nunca o proprio usuario) ou um LUGAR pelo nome "
    "(igreja, clinica, escola; nunca endereco, cidade nem local ja em LOCAIS SALVOS), ponha new_person (e new_person_rel se disse o parentesco) e new_place; o sistema ve se ja e conhecido e oferece salvar. Senao null.")
R_GERIR = (
    "GERIR MEMORIA: intent=memory_manage com mem_action. forget = esquece isso, esquece que X, apaga da memoria (mem_ref = trecho ou #id; vazio = o ultimo anotado; so fatos da memoria, nao compromissos nem lembretes). "
    "list = o que voce sabe de mim, minha memoria (mem_ref = pessoas, lugares, habito, preferencia, fato ou relacao; vazio = tudo). "
    "switch_off ou switch_on com mem_ref = memoria, sugestoes ou oferta: para de perguntar se salvo = switch_off oferta; sem sugestoes = switch_off sugestoes; nao guarde nada, desliga a memoria = switch_off memoria; o contrario liga (switch_on). "
    "Com OFERTA PENDENTE no contexto: sim, salva, pode = offer_yes (contact_email e location com o e-mail e o endereco que ele der); nao, deixa = offer_no. Se a mensagem nao responde a oferta, ignore-a.")

# --- prompt: memoria + oferta/sugestao pendente (variavel, antes da mensagem atual) ---
PROMPT_CTX = """if (user.mem_txt) { prompt += user.mem_txt + NL + NL; }
if (state && state.kind === 'offer' && Number(state.ts) > 0 && (agoraMs - Number(state.ts)) < 900000) {
prompt += 'OFERTA PENDENTE (voce perguntou se salva' + (state.pessoa ? ' a pessoa ' + state.pessoa : '') + (state.lugar ? ' e o lugar ' + state.lugar : '') + (state.accepted ? '; ja salvo, so falta o e-mail ou endereco' : '') + '). Se a mensagem responde a isso, use memory_manage (offer_yes ou offer_no).' + NL + NL;
}
if (state && state.kind === 'suggest' && Number(state.ts) > 0 && (agoraMs - Number(state.ts)) < 3600000) {
prompt += 'SUGESTAO PENDENTE (voce acabou de perguntar): ' + String(state.text || '') + ' dados=' + JSON.stringify(state.data || {}) + '. Se aceitar (sim, pode): conta = finance com fin_action=add, title, amount e recurring_day dos dados; lembrete = create_reminder com o title dos dados e repeat_freq=weekly (sem hora, clarify). Se recusar, responda curto e nao insista.' + NL + NL;
}"""

# --- Interpretar resposta: mem_json, offer_json, mm_json ---
INTERPRET = """const cl11 = function (s, n) { return String(s === undefined || s === null ? '' : s).split(String.fromCharCode(10)).join(' ').trim().slice(0, n); };
{
const tipos11 = ['habito', 'preferencia', 'fato', 'relacao'];
const mf11 = [];
(Array.isArray(out.mem_facts) ? out.mem_facts : []).forEach(function (x) {
if (!x || mf11.length >= 2) { return; }
const t11 = cl11(x.texto, 200);
if (t11.length < 4) { return; }
mf11.push({ texto: t11, tipo: tipos11.indexOf(x.tipo) >= 0 ? x.tipo : 'fato' });
});
out.mem_json = out.intent === 'memory_manage' ? '[]' : JSON.stringify(mf11);
out.offer_json = JSON.stringify({ pessoa: cl11(out.new_person, 60), rel: cl11(out.new_person_rel, 40), lugar: cl11(out.new_place, 60) });
}
if (out.intent === 'memory_manage') {
const acts11 = ['forget', 'list', 'switch_on', 'switch_off', 'offer_yes', 'offer_no'];
if (acts11.indexOf(out.mem_action) < 0) {
out.intent = 'clarify'; out.reply = out.reply || 'Quer que eu esqueça algo, mostre o que anotei ou ligue ou desligue algum recurso?';
} else {
out.mm_json = JSON.stringify({ action: out.mem_action, ref: cl11(out.mem_ref, 120), email: cl11(out.contact_email, 120), address: cl11(out.location, 200) });
}
}"""

# --- Preparar envio: linha "Anotei: ..." (uma so) no fim da resposta ---
SEND = """let mem11 = null;
try { mem11 = $('Memoria: gravar').first().json.mem; } catch (e) { mem11 = null; }
if (Array.isArray(mem11) && mem11.length && ia.intent !== 'memory_manage') {
const anot11 = []; let dup11 = 0;
mem11.forEach(function (m) {
if (m && m.ok === true && m.duplicate !== true && m.text) { anot11.push(String(m.text).replace('Anotei: ', '')); }
else if (m && m.duplicate === true) { dup11++; }
});
const soFato = ia.intent === 'chat' && !String(ia.reply || '').trim();
if (anot11.length) { text = soFato ? 'Anotei: ' + anot11.join('; ') : text + NL + 'Anotei: ' + anot11.join('; '); }
else if (soFato) { text = dup11 ? 'Já estava anotado.' : 'Ok.'; }
}"""

# --- gerir memoria e responder a oferta (texto via IA e botoes of:y / of:n) ---
PREP = r"""const u = $('Normalizar update').first().json;
const user = $('Buscar usuario').first().json;
let st = null;
try { const raw = $('Ler estado da conversa').first().json.state; st = raw ? JSON.parse(raw) : null; } catch (e) { st = null; }
const fresh = !!(st && st.kind === 'offer' && Number(st.ts) > 0 && (Date.now() - Number(st.ts)) < 900000);
const btn = u.kind === 'callback';
let action = ''; let ref = ''; let email = ''; let address = '';
if (btn) { action = u.cb_data === 'of:y' ? 'offer_yes' : 'offer_no'; }
else {
let mm = {};
try { mm = JSON.parse($('Interpretar resposta').first().json.mm_json || '{}'); } catch (e) { mm = {}; }
action = mm.action || ''; ref = mm.ref || ''; email = mm.email || ''; address = mm.address || '';
}
const isOffer = action === 'offer_yes' || action === 'offer_no';
let expired = false;
if (isOffer && !fresh) { expired = true; action = 'none'; }
if (action === 'offer_no' && st && st.accepted === true) { action = 'none'; }
return [{ json: { user_id: user.id, chat_id: u.chat_id, btn: btn, action: action, expired: expired, ref: ref,
pessoa: (st && st.pessoa) ? String(st.pessoa) : '', lugar: (st && st.lugar) ? String(st.lugar) : '', rel: (st && st.rel) ? String(st.rel) : '',
email: email, address: address } }];"""
_MP11 = "$('Memoria: preparar').first().json."
EXEC_Q = ("SELECT CASE $2::text "
          "WHEN 'forget' THEN agente.f_mem_forget($1::bigint, $3::text) "
          "WHEN 'list' THEN agente.f_mem_list($1::bigint, $3::text) "
          "WHEN 'switch_on' THEN agente.f_mem_set_switch($1::bigint, $3::text, true) "
          "WHEN 'switch_off' THEN agente.f_mem_set_switch($1::bigint, $3::text, false) "
          "WHEN 'offer_yes' THEN agente.f_offer_accept($1::bigint, $4::text, $5::text, $6::text, $7::text, $8::text) "
          "WHEN 'offer_no' THEN agente.f_offer_decline($1::bigint, $4::text, $6::text) "
          "END AS r")
RESP = r"""const p = $('Memoria: preparar').first().json;
const r = $input.first().json.r || null;
let text = ''; let state = '';
if (p.expired) { text = 'Essa pergunta já passou. Se quiser salvar, me diz de novo.'; }
else if (p.action === 'none') { text = 'Ok, deixo assim.'; }
else if (!r) { text = 'Não consegui agora. Tente de novo.'; }
else { text = String(r.text || 'Ok.'); }
if (p.action === 'offer_yes' && r && r.ok === true) {
const falta = [];
if (r.person && !r.person.email) { falta.push('o e-mail'); }
if (r.place && !r.place.address) { falta.push('o endereço'); }
if (falta.length) {
text += ' Se quiser, me manda ' + falta.join(' e ') + ' que eu completo.';
state = JSON.stringify({ kind: 'offer', pessoa: p.pessoa, lugar: p.lugar, rel: p.rel, accepted: true, ts: Date.now() });
}
}
if (!state && p.btn) { state = JSON.stringify({ kind: 'none' }); }
return [{ json: { chat_id: p.chat_id, text: text, kb: 'none', rid: 0, state: state } }];"""


def build():
    # roda com as globais do gen.py: constantes deste modulo entram por import
    global nodes
    from intents.memory_manage import PREP, RESP, EXEC_Q, _MP11, _ONERR
    _IA = "$('Interpretar resposta').first().json."
    # grava os fatos (mem_facts) logo depois de abrir o lote: uma consulta, f_mem_add para cada fato
    nodes.append(pg_node('Memoria: gravar',
        "SELECT $1::bigint AS batch, (SELECT jsonb_agg(agente.f_mem_add($2::bigint, x->>'texto', coalesce(x->>'tipo', 'fato'), 'ia')) FROM jsonb_array_elements($3::jsonb) x) AS mem",
        "={{ [ $json.batch, " + _IA + "user_id, " + _IA + "mem_json || '[]' ] }}", [2325, 5400]))
    nodes[-1].update(_ONERR)
    _refresh()
    setc('Lote: abrir', ['Memoria: gravar'])
    setc('Memoria: gravar', ['Multi: preparar'])
    nodes += [
        code_node('Memoria: preparar', PREP, [3000, 6200]),
        pg_node('Memoria: executar', EXEC_Q,
                "={{ [ " + _MP11 + "user_id, " + _MP11 + "action, " + _MP11 + "ref, " + _MP11 + "pessoa, " + _MP11 + "email, " + _MP11 + "lugar, " + _MP11 + "address, " + _MP11 + "rel ] }}",
                [3250, 6200]),
        code_node('Memoria: resposta', RESP, [3500, 6200]),
    ]
    nodes[-2].update(_ONERR)
    _refresh()
    setc('Memoria: preparar', ['Memoria: executar'])
    setc('Memoria: executar', ['Memoria: resposta'])
    setc('Memoria: resposta', ['Preparar envio'])
    # (sem 'Oferta: botao?': botao 'of:' cai em Executar botao como antes)


# --- comandos: /contatos (so pessoas e grupos), /locais (so lugares), /memoria, /config (interruptores) ---
_U11 = "$('Normalizar update').first().json.text"
CMD_QUERY = ("SELECT agente.f_command_data($1::bigint) AS r, CASE $2::text "
             "WHEN '/contatos' THEN agente.f_list_pessoas($1::bigint) "
             "WHEN '/locais' THEN agente.f_list_lugares($1::bigint) "
             "WHEN '/memoria' THEN agente.f_mem_list($1::bigint, $3::text) "
             "WHEN '/config' THEN agente.f_mem_switches($1::bigint) END AS x")
CMD_REPL = ("={{ [ $('Buscar usuario').first().json.id, String(" + _U11 + " || '').split(' ')[0].split('@')[0].toLowerCase(), "
            "String(" + _U11 + " || '').split(' ').slice(1).join(' ').trim() ] }}")
USER_REPL = ("={{ [ $('Normalizar update').first().json.from_id, "
             "(['text', 'photo', 'document'].indexOf($('Normalizar update').first().json.kind) >= 0 ? String($('Normalizar update').first().json.text || '') : '') ] }}")

_RC = 'Resposta do comando'
INTENT = Intent(
    name='memory_manage',
    hint="memory_manage (gerir memoria, ver GERIR MEMORIA)",
    schema=SCHEMA,
    rules=[R_MEM, R_OFERTA, R_GERIR],
    prompt_ctx=PROMPT_CTX,
    interpret_js=INTERPRET,
    send_js=SEND,
    user_cols=["agente.f_mem_prompt_txt(u.id, $2::text) AS mem_txt"],
    sets=[Set('Buscar usuario', ('options', 'queryReplacement'), USER_REPL),
          Set('Comando: dados', ('query',), CMD_QUERY),
          Set('Comando: dados', ('options', 'queryReplacement'), CMD_REPL)],
    edits=[
        Edit(_RC, 'jsCode', "let text = '', kb = 'none';", "let x = null;\ntry { x = $('Comando: dados').first().json.x || null; } catch (e) { x = null; }\nlet text = '', kb = 'none';"),
        Edit(_RC, 'jsCode', "text = dados.locais || 'Nao consegui ler seus locais agora. Tente de novo.';",
             "text = (x && x.text) || dados.locais || 'Nao consegui ler seus locais agora. Tente de novo.';"),
        Edit(_RC, 'jsCode', "text = dados.contatos || 'Nao consegui ler seus contatos agora. Tente de novo.';",
             "text = (x && x.text) || dados.contatos || 'Nao consegui ler seus contatos agora. Tente de novo.';"),
        Edit(_RC, 'jsCode', "text = dados.config || 'Nao consegui ler suas preferencias agora. Tente de novo.';",
             """text = dados.config || 'Nao consegui ler suas preferencias agora. Tente de novo.';
  if (x && typeof x.mem_enabled === 'boolean') {
    text += NL + NL + 'Memória: ' + (x.mem_enabled ? 'ligada' : 'desligada') + NL + 'Perguntar se salvo: ' + (x.offer_save_enabled ? 'ligado' : 'desligado') + NL + 'Sugestões: ' + (x.suggest_enabled ? 'ligadas' : 'desligadas') + NL + '(Para mudar, é só dizer: "sem sugestões", "para de perguntar se salvo", "desliga a memória" e o contrário.)';
  }"""),
        Edit(_RC, 'jsCode', "} else {\n  text = 'Nao conheco esse comando. Use /ajuda.';",
             "} else if (cmd === '/memoria') {\n  text = (x && x.text) || 'Nao consegui ler sua memoria agora. Tente de novo.';\n} else {\n  text = 'Nao conheco esse comando. Use /ajuda.';"),
    ],
    route=('memoria', 'Memoria: preparar'),
    build=build,
)
