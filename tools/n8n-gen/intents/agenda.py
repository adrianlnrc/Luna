# Intencoes manage_event (+ link_reminder interna) e a agenda do create_event (A1): mover/cancelar, conflito, horario livre, recorrentes,
# lembrete ligado a compromisso, promover lembrete, convites e botoes de acao externa (Google).
# Depende de db (agente.f_agenda_manage, f_agenda_after_create, f_agenda_done, f_reminder_link).
from .core import Intent, Edit

# regras: AGENDA (manage_event), AGENDA recorrente (create_event), LEMBRETE LIGADO (link_reminder), EXPEDIENTE (set_preference)
RULES = [
    """AGENDA (gerir compromissos que ja existem): use intent=manage_event com ev_action = move (mudar a data ou o horario de um compromisso: \"muda a reuniao de sexta para segunda as 10h\", \"a reuniao de sexta pode virar 15h?\", \"adia o dentista para quinta\"), cancel (cancelar, desmarcar ou apagar um compromisso), free (consultar horario livre: \"tenho horario livre sexta de manha?\", \"quando posso marcar 1 hora essa semana?\") ou promote (transformar um LEMBRETE em compromisso do Google Calendar: \"poe o dentista no meu Google Agenda\"). title = so o nome do compromisso ou lembrete (sem data nem hora; vazio em free). duration_minutes = nova duracao (move) ou o tamanho do bloco procurado (free: \"1 hora\" = 60); senao null. Em move: range_start e range_end = o DIA em que o compromisso esta HOJE (YYYY-MM-DD; \"a reuniao de sexta\" = essa sexta; null se o usuario nao citou o dia), date = a NOVA data (YYYY-MM-DD; null se so mudou a hora) e time = o NOVO horario HH:MM (se o usuario nao disse a hora nova, deixe time vazio). Em cancel: range_start e range_end (ou date) = o dia do compromisso, se citado. Em free: range_start e range_end = os dias pedidos (no maximo 7 dias; \"essa semana\" = de hoje ate daqui 6 dias) e time = manha, tarde ou noite (ou HH:MM-HH:MM) se pediu um periodo do dia, senao vazio. Perguntas como \"qual e minha reuniao de sexta?\" ou \"o que tenho amanha?\" sao list_agenda, nao manage_event.""",
    """AGENDA recorrente: em create_event, repeat_freq = daily, weekly ou monthly quando o compromisso se repete (\"toda quarta as 20h\" = weekly, date = a PROXIMA quarta, time = 20:00); repeat_until = YYYY-MM-DD se o usuario deu uma data final; repeat_count = numero de vezes se disse \"por 8 semanas\". Compromisso unico: repeat_* null. Nunca use repeat_* em lembretes.""",
    """LEMBRETE LIGADO A COMPROMISSO: intent=create_reminder com link_event = nome do compromisso ao qual o lembrete pertence (\"levar uma calca pra Maria Luisa na celebracao\": title = levar uma calca pra Maria Luisa, link_event = celebracao, person = Maria Luisa). Nesse caso NAO invente horario: deixe time vazio (o sistema usa a proxima ocorrencia do compromisso). So preencha link_event quando o lembrete e para aquele compromisso.""",
    """EXPEDIENTE: set_preference com pref_work_start e pref_work_end (HH:MM) quando o usuario disser o horario de trabalho (\"meu expediente e das 9 as 18\" = 09:00 e 18:00). Serve para a busca de horario livre.""",
]

# lembrete com link_event e sem hora vira a intent interna link_reminder (ancora propria, antes de needsTime)
LINK_BLOCK = """if (out.intent === 'create_reminder' && out.link_event && !(out.time && okTime.test(out.time))) {
  out.intent = 'link_reminder';
  out.lr_json = JSON.stringify({ title: out.title || '', link_event: out.link_event, person: out.person || '', lead_minutes: (typeof out.lead_minutes === 'number' && out.lead_minutes > 0) ? out.lead_minutes : null, source: ctx.via_audio ? 'audio' : 'text' });
}
"""

INTERPRET = """if (out.intent === 'create_event') {
  const rfq = (out.repeat_freq === 'daily' || out.repeat_freq === 'weekly' || out.repeat_freq === 'monthly') ? out.repeat_freq : '';
  out.rp_freq = rfq;
  out.rp_until = (rfq && out.repeat_until && okDate.test(out.repeat_until)) ? out.repeat_until : '';
  out.rp_count = (rfq && !out.rp_until && typeof out.repeat_count === 'number' && out.repeat_count > 0) ? String(Math.floor(out.repeat_count)) : '';
}
if (out.intent === 'manage_event') {
  const act = (out.ev_action === 'move' || out.ev_action === 'cancel' || out.ev_action === 'free' || out.ev_action === 'promote') ? out.ev_action : '';
  if (!act) {
    out.intent = 'clarify'; out.reply = out.reply || 'O que voce quer fazer na agenda: mover, cancelar, ver horario livre ou transformar um lembrete em compromisso?';
  } else {
    const txtm = String(out.transcript || u.text || '').toLowerCase();
    const rs = (out.range_start && okDate.test(out.range_start)) ? out.range_start : '';
    const rb = (out.range_end && okDate.test(out.range_end)) ? out.range_end : '';
    const dd = (out.date && okDate.test(out.date)) ? out.date : '';
    const mg = { act: act, title: out.title || '', calendar_key: out.calendar_key || '' };
    let ini = now.startOf('day');
    let fim = now.startOf('day').plus({ days: 60 });
    if (act === 'promote') {
      ini = now; fim = now.plus({ minutes: 60 });
      if (out.duration_minutes) { mg.duration_minutes = out.duration_minutes; }
    } else if (act === 'free') {
      let a0 = rs || dd || now.toFormat('yyyy-MM-dd');
      let b0 = rb || a0;
      if (b0 < a0) { const tmp = a0; a0 = b0; b0 = tmp; }
      ini = DateTime.fromISO(a0, { zone: tz }).startOf('day');
      fim = DateTime.fromISO(b0, { zone: tz }).startOf('day').plus({ days: 1 });
      if (fim > ini.plus({ days: 7 })) { fim = ini.plus({ days: 7 }); }
      const pt = String(out.time || '').toLowerCase();
      let part = '';
      if (pt.indexOf('manh') >= 0) { part = 'manha'; }
      else if (pt.indexOf('tarde') >= 0) { part = 'tarde'; }
      else if (pt.indexOf('noite') >= 0) { part = 'noite'; }
      else if (/^[0-9]{1,2}:[0-9]{2}-[0-9]{1,2}:[0-9]{2}$/.test(pt)) { part = pt; }
      else if (/(^|[^a-z])manh/.test(txtm)) { part = 'manha'; }
      else if (txtm.indexOf('tarde') >= 0) { part = 'tarde'; }
      else if (txtm.indexOf('noite') >= 0) { part = 'noite'; }
      mg.part = part;
      mg.min_minutes = out.duration_minutes || 30;
    } else {
      const a0 = rs || dd;
      const b0 = rb || a0;
      if (act === 'cancel') {
        if (a0) { ini = DateTime.fromISO(a0, { zone: tz }).startOf('day'); fim = DateTime.fromISO(b0, { zone: tz }).startOf('day').plus({ days: 1 }); }
      } else {
        const a1 = rs;
        const b1 = rb || rs;
        if (a1) { ini = DateTime.fromISO(a1, { zone: tz }).startOf('day'); fim = DateTime.fromISO(b1, { zone: tz }).startOf('day').plus({ days: 1 }); }
        let tm = (out.time && okTime.test(out.time)) ? out.time : '';
        if (!tm) {
          const re1 = /([0-9]{1,2})[ ]*(?:h|:)[ ]*([0-9]{2})?/gi;
          let mm = re1.exec(txtm);
          while (mm) { tm = mm[1] + ':' + (mm[2] ? mm[2] : '00'); mm = re1.exec(txtm); }
        }
        if (!tm) {
          out.intent = 'clarify'; out.reply = 'Para que horario eu movo "' + (out.title || 'o compromisso') + '"?';
        } else {
          const hhmm = tm.length === 4 ? '0' + tm : tm;
          mg.new_time = hhmm;
          if (out.duration_minutes) { mg.duration_minutes = out.duration_minutes; }
          if (dd) {
            const nd = DateTime.fromISO(dd + 'T' + hhmm, { zone: tz });
            if (!nd.isValid) { out.intent = 'clarify'; out.reply = 'Nao entendi a nova data e hora. Pode repetir?'; }
            else if (nd <= now) { out.intent = 'clarify'; out.reply = 'Esse horario novo ja passou. Para quando eu movo?'; }
            else {
              mg.new_start = nd.toISO();
              if (nd.startOf('day') < ini) { ini = nd.startOf('day'); }
              if (nd.startOf('day').plus({ days: 1 }) > fim) { fim = nd.startOf('day').plus({ days: 1 }); }
            }
          }
        }
      }
    }
    if (out.intent === 'manage_event') {
      out.time_min = ini.toISO(); out.time_max = fim.toISO();
      mg.win_start = out.time_min; mg.win_end = out.time_max;
      out.mg = mg;
    }
  }
}"""


# campos do schema da IA (antes tinham ficado no patch_f2a.py)
SCHEMA_AGENDA = """pref_work_start: NN('string'), pref_work_end: NN('string'),
  ev_action: { type: ['string', 'null'], enum: ['move', 'cancel', 'free', 'promote', null] },
  repeat_freq: { type: ['string', 'null'], enum: ['daily', 'weekly', 'monthly', null] }, repeat_until: NN('string'), repeat_count: NN('integer'),
  link_event: NN('string'), invitees: { type: ['array', 'null'], items: { type: 'string' } }, meet: NN('boolean'),"""


def build():
    global nodes, byname
    IR = "$('Interpretar resposta').first().json."

    # preferencias: expediente
    sp = byname['Salvar preferencias']['parameters']
    sp['options']['queryReplacement'] = rep(sp['options']['queryReplacement'],
        "evening: $('Interpretar resposta').first().json.pref_evening })",
        "evening: $('Interpretar resposta').first().json.pref_evening, work_start: $('Interpretar resposta').first().json.pref_work_start, work_end: $('Interpretar resposta').first().json.pref_work_end })")

    # ===== 4) Criacao de evento: novos inputs + conclusao =====
    for nm in ('Agenda Adrian - criar evento', 'Agenda Maria Clara - criar evento'):
        v = byname[nm]['parameters']['workflowInputs']['value']
        v.update({
            'attendees': "={{ " + IR + "attendees_csv || '' }}",
            'send_updates': 'all',
            'force': 'false',
            'meet': 'false',
            'repeat_freq': "={{ " + IR + "rp_freq || '' }}",
            'repeat_until': "={{ " + IR + "rp_until || '' }}",
            'repeat_count': "={{ " + IR + "rp_count || '' }}",
        })
    # remove Registrar compromisso / Resposta do compromisso
    nodes[:] = [n for n in nodes if n['name'] not in ('Registrar compromisso', 'Resposta do compromisso')]
    conns.pop('Registrar compromisso', None); conns.pop('Resposta do compromisso', None)
    _refresh()

    RESP_JS = ("const a = $('Interpretar resposta').first().json;\n"
               "const r = $input.first().json.r || {};\n"
               "return [{ json: { chat_id: a.chat_id, text: r.text || '%s', kb: r.kb || 'none', rid: r.rid || 0, state: r.state || '' } }];")
    nodes += [
     pg_node('Agenda: concluir criacao', "SELECT agente.f_agenda_after_create($1::bigint, $2::jsonb, $3::jsonb) AS r",
       "={{ [ " + IR + "user_id, JSON.stringify({ title: " + IR + "title, due_iso: " + IR + "due_iso, end_iso: " + IR + "end_iso, location: " + IR + "location || '', lead_str: " + IR + "lead_str, source: " + IR + "source, calendar_key: " + IR + "calendar_key, repeat_freq: " + IR + "rp_freq || '', repeat_until: " + IR + "rp_until || '', repeat_count: " + IR + "rp_count || '', attendees: " + IR + "attendees_csv || '', meet: 'false' }), JSON.stringify($input.first().json) ] }}",
       [4480, 3600]),
     code_node('Agenda: resposta da criacao', RESP_JS % 'Nao consegui registrar o compromisso agora. Tente de novo.', [4704, 3600]),
    ]
    setc('Agenda Adrian - criar evento', ['Agenda: concluir criacao'])
    setc('Agenda Maria Clara - criar evento', ['Agenda: concluir criacao'])
    setc('Agenda: concluir criacao', ['Agenda: resposta da criacao'])
    setc('Agenda: resposta da criacao', ['Preparar envio'])

    # ===== 5) Gerir agenda (manage_event) =====
    nodes += [
     ifnode('Agenda: gerir?', "={{ " + IR + "intent }}", 'string', 'equals', 'manage_event', [4260, 3900]),
     pg_node('Agenda: gerir agenda', "SELECT agente.f_agenda_manage($1::bigint, $2::jsonb) AS r",
       "={{ [ " + IR + "user_id, JSON.stringify(Object.assign({}, " + IR + "mg || {}, { ok: $input.first().json.ok, error: $input.first().json.error, events: $input.first().json.events || [] })) ] }}",
       [4480, 3800]),
     code_node('Agenda: resposta da gestao', RESP_JS % 'Nao consegui mexer na agenda agora. Tente de novo.', [4704, 3800]),
    ]
    setc('Agenda: gerir?', ['Agenda: gerir agenda', 'Lembretes do periodo'])
    setc('Agenda: gerir agenda', ['Agenda: resposta da gestao'])
    setc('Agenda: resposta da gestao', ['Preparar envio'])
    setc('Agenda Adrian - listar', ['Agenda: gerir?'])
    setc('Agenda Maria Clara - listar', ['Agenda: gerir?'])
    setc('Qual calendario? (consulta)', ['Agenda Adrian - listar', 'Agenda Maria Clara - listar', 'Agenda: gerir?'])

    # ===== 6) Lembrete ligado a compromisso =====
    nodes += [
     pg_node('Agenda: ligar lembrete', "SELECT agente.f_reminder_link($1::bigint, $2::jsonb) AS r",
       "={{ [ " + IR + "user_id, " + IR + "lr_json ] }}", [4480, 4000]),
     code_node('Agenda: resposta do lembrete ligado', RESP_JS % 'Nao consegui ligar o lembrete agora. Tente de novo.', [4704, 4000]),
    ]
    setc('Agenda: ligar lembrete', ['Agenda: resposta do lembrete ligado'])
    setc('Agenda: resposta do lembrete ligado', ['Preparar envio'])

    # ===== 7) Botoes: acao externa (Google) =====
    CB = "$('Executar botao').first().json.r.cal."
    def _exec_values():
        vals = {'action': "={{ " + CB + "op }}"}
        for k in ('summary', 'start', 'end', 'location', 'attendees', 'event_id', 'send_updates', 'force', 'meet', 'repeat_freq', 'repeat_until', 'repeat_count', 'response'):
            vals[k] = "={{ " + CB + k + " || '' }}"
        return vals
    nodes += [
     ifnode('Agenda: acao externa?', "={{ !!($json.r && $json.r.cal) }}", 'boolean', 'true', '', [900, 3500]),
     switch_cal('Agenda: qual calendario (acao)', [1100, 3500], field="={{ $json.r.cal.calendar_key }}"),
     exec_wf('Agenda Adrian - executar acao', 'bBJo78YVQ1cOMX09', _exec_values(), [1300, 3400]),
     exec_wf('Agenda Maria Clara - executar acao', '6bXuicjujajBuXbd', _exec_values(), [1300, 3560]),
     code_node('Agenda: sem calendario (acao)',
       "const u = $('Normalizar update').first().json;\nreturn [{ json: { chat_id: u.chat_id, text: 'Nao encontrei o calendario dessa acao. Peca de novo.', kb: 'none', rid: 0, state: '' } }];", [1300, 3720]),
     pg_node('Agenda: concluir acao', "SELECT agente.f_agenda_done($1::bigint, $2::bigint, $3::jsonb) AS r",
       "={{ [ $('Buscar usuario').first().json.id, " + CB + "pid, JSON.stringify($input.first().json) ] }}", [1500, 3480]),
     code_node('Agenda: resposta da acao',
       "const u = $('Normalizar update').first().json;\nconst r = $input.first().json.r || {};\nreturn [{ json: { chat_id: u.chat_id, text: r.text || 'Nao consegui concluir agora. Confira sua agenda.', kb: r.kb || 'none', rid: r.rid || 0, state: r.state || '' } }];", [1700, 3480]),
    ]
    _refresh()
    for nm in ('Agenda Adrian - executar acao', 'Agenda Maria Clara - executar acao'):
        byname[nm]['onError'] = 'continueRegularOutput'
    setc('Executar botao', ['Agenda: acao externa?'])
    setc('Agenda: acao externa?', ['Agenda: qual calendario (acao)', 'Resposta do botao'])
    setc('Agenda: qual calendario (acao)', ['Agenda Adrian - executar acao', 'Agenda Maria Clara - executar acao', 'Agenda: sem calendario (acao)'])
    setc('Agenda Adrian - executar acao', ['Agenda: concluir acao'])
    setc('Agenda Maria Clara - executar acao', ['Agenda: concluir acao'])
    setc('Agenda: sem calendario (acao)', ['Preparar envio'])
    setc('Agenda: concluir acao', ['Agenda: resposta da acao'])
    setc('Agenda: resposta da acao', ['Preparar envio'])

    # ===== 8) Teclados =====
    add_kb('ag_confirm', [('Confirmar', 'agok:{rid}'), ('Cancelar', 'agno:{rid}')])
    add_kb('ag_pick2', [('1', 'agpk:{rid}:1'), ('2', 'agpk:{rid}:2')])
    add_kb('ag_pick3', [('1', 'agpk:{rid}:1'), ('2', 'agpk:{rid}:2'), ('3', 'agpk:{rid}:3')])
    add_kb('ag_scope', [('Só este', 'agsc:{rid}:1'), ('A série', 'agsc:{rid}:a')])
    add_kb('ag_conflict', [('Marcar mesmo assim', 'agfy:{rid}'), ('Outro horário', 'agfo:{rid}')])
    add_kb('ag_invite', [('Aceitar', 'agrs:{rid}'), ('Recusar', 'agrn:{rid}')])
    _refresh()


INTENT = Intent(
    name='manage_event',
    enum_after='finance',
    schema_parts=[(SCHEMA_AGENDA, "\n  ", "pref_no_emoji: NN('boolean'),")],   # expediente, ev_action, repeat_*, link_event, invitees, meet
    internal=['link_reminder'],
    rules=RULES,
    interpret_js=INTERPRET,
    edits=[
        Edit('Montar pedido a IA', 'jsCode', 'Excecao: create_task, create_event, list_* e os intents de estoque seguem suas proprias regras abaixo.',
             'Excecao: create_task, create_event, list_*, manage_event, lembrete com link_event e os intents de estoque seguem suas proprias regras abaixo.'),
        Edit('Interpretar resposta', 'jsCode', "const needsTime = [", LINK_BLOCK + "const needsTime = ["),
    ],
    route=('agenda gerir', 'Qual calendario? (consulta)'),
    routes=[('agenda lembrete ligado', 'link_reminder', 'Agenda: ligar lembrete')],
    build=build,
)
