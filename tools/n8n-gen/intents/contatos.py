# Intencoes contact_manage e invite_event (Fase 3): contatos, grupos, convites do Google Agenda e link do Meet.
# invite_event e interna: nasce de create_event com convidados/Meet (ver INTERPRET), nao esta no enum da IA.
from .core import Intent

INTERPRET = """if (out.intent === 'create_event' && out.due_iso) {
  const convidados = Array.isArray(out.invitees) ? out.invitees.filter(function (x) { return String(x || '').trim() !== ''; }) : [];
  if (convidados.length > 0 || out.meet === true) {
    out.intent = 'invite_event';
    out.invite_json = JSON.stringify({
      summary: out.title || '', start: out.due_iso, end: out.end_iso || '', location: out.location || '',
      meet: out.meet === true, invitees: convidados, repeat_freq: out.repeat_freq || '', repeat_until: out.repeat_until || '',
      repeat_count: out.repeat_count || null, lead_str: out.lead_str || '',
      source: (u.kind === 'photo' || u.kind === 'document') ? 'photo' : (ctx.via_audio ? 'audio' : 'text')
    });
  }
}
if (out.intent === 'contact_manage') {
  out.contact_json = JSON.stringify({
    contact_action: out.contact_action || '', contact_name: out.contact_name || '', contact_email: out.contact_email || '',
    group_name: out.group_name || '', group_members: Array.isArray(out.group_members) ? out.group_members : [],
    text: String(out.transcript || u.text || '')
  });
}"""

RULES = [
    """CONTATOS E GRUPOS: intent contact_manage com contact_action. save = guardar o e-mail de alguem (\"salva o e-mail da Claudia: claudia@x.com\", \"o e-mail do Douglas e douglas@x.com\"): contact_name e contact_email; tambem \"a Bia e favorita\" (contact_name, sem e-mail; a frase original diz favorita). list = \"meus contatos\", \"meus favoritos\". remove = \"tira a Claudia dos contatos\" (contact_name). group_save = \"cria o grupo time com Douglas, Bia e Claudia\" (group_name e group_members, so os nomes), tambem \"poe a Bia no grupo time\" ou \"tira a Bia do grupo time\" (group_name e group_members so com quem entra ou sai). group_list = \"meus grupos\" ou \"quem esta no grupo time\" (group_name se citado). group_remove = \"apaga o grupo time\" (group_name). Nao invente e-mail: sem e-mail dito pelo usuario, deixe contact_email nulo. Em contact_manage preencha reply com texto vazio.""",
    """CONVITES E MEET: quando o usuario quer COMPROMISSO COM OUTRAS PESSOAS (\"chama\", \"convida\", \"marca com\", \"manda o convite\") use create_event e preencha invitees com os nomes, grupos ou e-mails citados, so o nome (sem \"o\" ou \"a\"). meet = true quando pedir link, Meet, videochamada ou chamada de video. Sem titulo claro use title Reuniao. Exemplos: \"chama o Douglas e a Bia pra sexta 16h\" = create_event, title Reuniao, invitees [Douglas, Bia], date da sexta, time 16:00. \"marca uma reuniao com o time quinta 14h30 e manda os convites\" = create_event, title Reuniao com o time, invitees [time]. \"marca 30 min com a contadora e manda o link\" = create_event, duration_minutes 30, meet true, invitees [contadora]. Compromisso sem convidado e sem pedido de link continua create_event normal, com invitees e meet nulos. Quem confirma e o usuario, por botao.""",
]


# campos do schema da IA (antes tinham ficado no patch_f2a.py)
SCHEMA_CONTATOS = """contact_action: { type: ['string', 'null'], enum: ['save', 'list', 'remove', 'group_save', 'group_list', 'group_remove', null] },
  contact_name: NN('string'), contact_email: NN('string'), group_name: NN('string'), group_members: { type: ['array', 'null'], items: { type: 'string' } },"""


def build():
    global nodes, byname
    IR = "$('Interpretar resposta').first().json."
    nodes.append(pg_node('Contatos: executar',"SELECT agente.f_contacts($1::bigint, $2::jsonb) AS r",
      "={{ [ "+IR+"user_id, "+IR+"contact_json ] }}",[4480,3600]))
    nodes.append(pg_node('Convites: preparar',"SELECT agente.f_invite_prepare($1::bigint, $2::jsonb) AS r",
      "={{ [ "+IR+"user_id, "+IR+"invite_json ] }}",[4480,3792]))
    nodes.append(code_node('Contatos: resposta',
      "const a = $('Interpretar resposta').first().json;\nconst r = $input.first().json.r || {};\nreturn [{ json: { chat_id: a.chat_id, text: r.text || 'Nao consegui agora. Tente de novo.', kb: r.kb || 'none', rid: r.rid || 0, state: '' } }];",
      [4704,3696]))
    _refresh()
    setc('Contatos: executar',['Contatos: resposta'])
    setc('Convites: preparar',['Contatos: resposta'])
    setc('Contatos: resposta',['Preparar envio'])
    add_kb('ct_confirm',[('Confirmar','ctok:{rid}'),('Cancelar','ctno:{rid}')])

    # /start e /ajuda
    rc=byname['Resposta do comando']['parameters']['jsCode']
    rc=rep(rc,"    'Privacidade: para entender","    'Contatos e convites: \"salva o e-mail da Claudia: claudia@x.com\", \"cria o grupo time com Douglas e Bia\", \"chama o Douglas pra sexta 16h\" (mando o convite do Google Agenda, com link do Meet se pedir).', '',\n    'Privacidade: para entender")
    rc=rep(rc,"    'Quando eu avisar um lembrete, use os botoes:","""    '- "salva o e-mail da Claudia: claudia@x.com" / "meus contatos" / "tira a Claudia dos contatos" / "a Bia e favorita"',
    '- "cria o grupo time com Douglas, Bia e Claudia" / "meus grupos" / "quem esta no grupo time?" / "apaga o grupo time"',
    '- "chama o Douglas e a Bia pra sexta 16h" / "marca reuniao com o time quinta 14h30 e manda os convites" / "marca 30 min com a contadora e manda o link" (confirmo antes de enviar)',
    'Quando eu avisar um lembrete, use os botoes:""")
    byname['Resposta do comando']['parameters']['jsCode']=rc
    _refresh()


INTENT = Intent(
    name='contact_manage',
    enum_after='cancel_reminder',
    schema_parts=[(SCHEMA_CONTATOS, "\n  ", "query_kind: { type")],
    internal=['invite_event'],
    rules=RULES,
    interpret_js=INTERPRET,
    route=('contatos', 'Contatos: executar'),
    routes=[('convite', 'invite_event', 'Convites: preparar')],
    build=build,
)
