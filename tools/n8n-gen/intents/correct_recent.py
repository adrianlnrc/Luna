# Intencao correct_recent (F10 / etapa 1 da secretaria natural): corrigir lembrete ou nota recem-criados.
# Contexto: bloco ACOES RECENTES (db: agente.f_recent_actions_txt) e RESPONDIDA (reply do Telegram) no prompt.
from .core import Intent, Edit

R_CORR = (
    "CORRECAO DE ACAO RECENTE: o bloco ACOES RECENTES (antes da mensagem atual) lista o que voce acabou de criar: [id] tipo: o que, quando (ha quanto tempo). "
    "Se o usuario corrigir algo dali (na verdade o dentista e as 10, muda para amanha, o nome e outro, era 50 e nao 40), trate a CORRECAO e NAO crie nada novo. "
    "Se ele responder (reply do Telegram) a uma mensagem sua, o bloco RESPONDIDA mostra o texto dela e indica qual acao e. Por tipo: "
    "lembrete = intent=correct_recent com recent_id = o id da lista e so o que mudou (title = novo titulo; date = nova data YYYY-MM-DD; time = nova hora HH:MM; o que nao mudou fica vazio ou null); "
    "nota = correct_recent com recent_id e note_text = o novo texto inteiro da nota; "
    "compromisso = manage_event com ev_action=move, title = titulo EXATO como esta na lista, e a nova date e time (so a hora nova se o dia nao mudou); "
    "gasto = finance com fin_action=correct (valor, categoria ou data novos) e title = nome do gasto; "
    "tarefa = intent=chat e reply curto: tarefa do Google eu ainda nao altero, posso criar outra com o texto certo. "
    "Se mais de um item da lista combina com o que ele disse (dois compromissos de dentista), use intent=clarify e pergunte qual, citando os itens pelo horario (o das 10h ou o das 15h?). "
    "Para algo antigo que NAO esta na lista (dias depois: dentista remarcou pra proxima quarta as 14h) use manage_event com ev_action=move e title = o nome citado: o sistema procura na agenda e pergunta se houver mais de um. "
    "So use a lista quando a mensagem for mesmo uma correcao; pedido novo continua pedido novo.")

PROMPT_CTX = """if (user.recent_txt) { prompt += 'ACOES RECENTES (mais recente primeiro):' + NL + user.recent_txt + NL + NL; }
if (u.reply_text) { prompt += 'RESPONDIDA (o usuario respondeu a esta mensagem sua, via reply do Telegram):' + NL + u.reply_text + NL + NL; }"""

INTERPRET = """if (out.intent === 'correct_recent') {
const hm3 = function (v) { return (v && okTime.test(v)) ? (v.length === 4 ? '0' + v : v) : ''; };
out.corr_json = JSON.stringify({ recent_id: (typeof out.recent_id === 'number') ? out.recent_id : null, title: out.title || '',
date: (out.date && okDate.test(out.date)) ? out.date : '', time: hm3(out.time), note_text: out.note_text || '' });
}"""


def build():
    global nodes
    _IR = "$('Interpretar resposta').first().json."
    nodes.append(pg_node('Correcao: executar', "SELECT agente.f_recent_correct($1::bigint,$2::jsonb) AS r",
        "={{ [ " + _IR + "user_id, " + _IR + "corr_json || '{}' ] }}", [3000, 4900]))
    nodes.append(code_node('Correcao: resposta', """const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
return [{ json: { chat_id: a.chat_id, text: r.text || 'Nao consegui corrigir agora. Tente de novo.', kb: r.kb || 'none', rid: r.rid || 0, state: '' } }];""", [3250, 4900]))
    _refresh()
    setc('Correcao: executar', ['Correcao: resposta'])
    setc('Correcao: resposta', ['Preparar envio'])


INTENT = Intent(
    name='correct_recent',
    hint="correct_recent (corrigir um LEMBRETE ou uma NOTA da lista ACOES RECENTES: muda a hora, a data, o titulo ou o texto)",
    # recent_id e proprio da intent; unsupported_note/social_event/more_actions sao do pedido multiplo e ficam em patch_f10_acoes.py
    schema="recent_id: NN('integer')",
    rules=[R_CORR],
    prompt_ctx=PROMPT_CTX,
    interpret_js=INTERPRET,
    user_cols=["agente.f_recent_actions_txt(u.id) AS recent_txt"],
    # reply do Telegram (mensagem respondida) alimenta o bloco RESPONDIDA
    edits=[Edit('Normalizar update', 'jsCode', "return [{ json: { update_id: u.update_id,",
                "let reply_text = '';\nif (m && m.reply_to_message) { reply_text = String(m.reply_to_message.text || m.reply_to_message.caption || '').slice(0, 300); }\nreturn [{ json: { reply_text: reply_text, update_id: u.update_id,")],
    route=('correcao recente', 'Correcao: executar'),
    build=build,
)
