"""Gerador unico dos 3 disparadores (etapa 5, rodada 2).

Perfis (cadeia de derivacao a partir do modulo base):
  disparador          = disparador_base.js (texto base, copia fiel de disparador.sdk.js)
  disparador_projetos = base + reconciliacao de projetos no Google Tarefas (logica em
                        gen_projetos_google.disparador(), que tambem gera projetos_google/backfill)
  disparador_resumo   = projetos + tarefas agendadas do dia + resumo enxuto (logica abaixo,
                        absorvida do antigo gen_resumo_enxuto.py)

Uso (nunca sobrescreve sem --write):
  python3 gen_disparador.py --check        # compara bytes com os 3 .sdk.js atuais (exit 0 = identicos)
  python3 gen_disparador.py --out DIR      # grava os 3 em DIR
  python3 gen_disparador.py --write        # regrava ao lado (so depois de --check)
"""
import json, re, os, sys, hashlib
HERE = os.path.dirname(os.path.abspath(__file__))
os.environ.setdefault('PROJ_GOOGLE_WF_ID', 'G5N2OpaT2v6Pczcl')   # id vivo do sub-workflow Projetos Google
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
import gen_projetos_google

LER_WF = os.environ.get('TAREFAS_RESUMO_WF_ID', 'Rm1WJplH1mnvWQCR')
TAREFAS_WF = 'dnVm8cfVhpqXGWmr'


def perfil_base():
    return open(os.path.join(HERE, 'disparador_base.js'), newline='').read()


def perfil_projetos():
    return gen_projetos_google.disparador(perfil_base())


def perfil_resumo():
    s = perfil_projetos()

    def jsq(code):
        assert '`' not in code and '${' not in code and '\\' not in code, 'JS perigoso'
        return json.dumps(code, ensure_ascii=False)

    # ---- 1. sub-workflow de leitura
    old = re.search(r"const tarefasResumo = node\(\{.*?\n\}\);\n", s, re.S).group(0)
    new = """const tarefasResumo = node({
  type: 'n8n-nodes-base.executeWorkflow', version: 1.3,
  config: {
    name: 'Tarefas do resumo', position: [1344, 1040],
    parameters: { source: 'database', mode: 'once', workflowId: { __rl: true, mode: 'id', value: '%s' },
      workflowInputs: { mappingMode: 'defineBelow', value: { calendar_key: expr("{{ $('Cada usuario').first().json.calendar_key || '' }}") } } }
  },
  output: [{ tasks: [] }]
});
""" % LER_WF
    s = s.replace(old, new)

    # ---- 2. tarefas agendadas do dia (antes de ler)
    PG = "credentials: { postgres: { id: '1xCdaqn8KYskDi8x', name: 'Postgres Agente' } }"
    sep_js = """const u = $('Cada usuario').first().json;
const r = $input.first().json || {};
const lista = (r.r && Array.isArray(r.r.items)) ? r.r.items : [];
if (!lista.length || (u.calendar_key !== 'adrian' && u.calendar_key !== 'maria')) { return [{ json: { skip: true } }]; }
return lista.map(function (x) { return { json: { skip: false, sid: x.id, calendar_key: u.calendar_key, action: 'add', title: String(x.title), due: String(x.due).slice(0, 10) } }; });"""
    juntar_js = """const sep = $('Agendadas: separar').all();
const res = $input.all();
const ids = [];
res.forEach(function (it, i) {
  const j = it.json || {};
  const o = sep[i] ? sep[i].json : null;
  if (o && j.id) { ids.push(o.sid); }
});
return [{ json: { ids: JSON.stringify(ids) } }];"""
    novos = """
const agPegar = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Agendadas: do dia', position: [1232, 1040], onError: 'continueRegularOutput', alwaysOutputData: true, %(pg)s,
    parameters: { operation: 'executeQuery', query: 'SELECT CASE WHEN $2::text = \\'evening\\' THEN \\'{"items":[]}\\'::jsonb ELSE agente.f_agimp_tasks_due($1::bigint) END AS r',
      options: { queryReplacement: expr("{{ [ $('Cada usuario').first().json.user_id, $('Cada usuario').first().json.kind ] }}") } } },
  output: [{ r: { items: [] } }]
});

const agSeparar = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Agendadas: separar', position: [1344, 1040], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: %(sep)s } },
  output: [{ skip: false, sid: 1, calendar_key: 'adrian', action: 'add', title: 't', due: '2026-11-04' }]
});

const agTem = ifElse({
  version: 2.2,
  config: { name: 'Agendadas: ha tarefas?', position: [1456, 1040],
    parameters: { conditions: { options: { caseSensitive: true, leftValue: '', typeValidation: 'loose' },
      conditions: [{ leftValue: expr('{{ $json.skip }}'), operator: { type: 'boolean', operation: 'false', singleValue: true }, rightValue: '' }],
      combinator: 'and' } } }
});

const agCriar = node({
  type: 'n8n-nodes-base.executeWorkflow', version: 1.3,
  config: { name: 'Agendadas: criar no Google', position: [1568, 960], onError: 'continueRegularOutput',
    parameters: { source: 'database', mode: 'each', workflowId: { __rl: true, mode: 'id', value: '%(tar)s' },
      workflowInputs: { mappingMode: 'defineBelow', value: { calendar_key: expr('{{ $json.calendar_key }}'), action: expr('{{ $json.action }}'), title: expr('{{ $json.title }}'), due: expr('{{ $json.due }}') } } } },
  output: [{ id: 'abc', title: 't' }]
});

const agJuntar = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Agendadas: conferir', position: [1680, 960], parameters: { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: %(jun)s } },
  output: [{ ids: '[]' }]
});

const agMarcar = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Agendadas: marcar criadas', position: [1792, 960], onError: 'continueRegularOutput', %(pg)s,
    parameters: { operation: 'executeQuery', query: 'SELECT agente.f_agimp_tasks_mark($1::bigint, $2::jsonb) AS n',
      options: { queryReplacement: expr("{{ [ $('Cada usuario').first().json.user_id, $json.ids ] }}") } } },
  output: [{ n: 1 }]
});
""" % {'pg': PG, 'sep': jsq(sep_js), 'jun': jsq(juntar_js), 'tar': TAREFAS_WF}
    s = s.replace("\nconst dadosResumo = node({", novos + "\nconst dadosResumo = node({", 1)

    # ---- 3. texto do resumo
    mr = re.search(r'name: .Montar resumo.*?jsCode: (".*?"), *\}? *\}', s, re.S)
    # jsCode e uma string JSON em uma linha: localizar pelo prefixo
    i = s.index("name: 'Montar resumo'")
    j = s.index('jsCode: "', i) + len('jsCode: ')
    k = s.index('" } },', j)  # fim da string
    code = json.loads(s[j:k + 1])

    def sub(old, new):
        nonlocal code
        assert old in code, old[:70]
        code = code.replace(old, new, 1)

    a = code.index('const tarefasAbertas = [];')
    b = code.index('const contas = ')
    code = code[:a] + """const nome = function (t) { return t.project ? t.title + ' (' + t.project + ')' : t.title; };
const tarefasHoje = [];
let atrasadas = 0;
let semPrazo = 0;
lista.forEach(function (t) {
  if (t.due && t.due < u.hoje_iso) { atrasadas += 1; }
  else if (t.due && t.due === u.hoje_iso) { tarefasHoje.push('- ' + nome(t)); }
  else if (!t.due) { semPrazo += 1; }
});
const partesCont = [];
if (atrasadas) { partesCont.push(atrasadas + (atrasadas === 1 ? ' atrasada' : ' atrasadas')); }
if (semPrazo) { partesCont.push(semPrazo + ' sem prazo'); }
const linhaCont = partesCont.length ? '- e ' + partesCont.join(' e ') + ' (diga minhas tarefas para ver)' : '';
""" + code[b:]

    a = code.index("  const pend = [];")
    b = code.index("  (d.overdue_today")
    code = code[:a] + """  const pend = [];
  lista.forEach(function (t) {
    if (t.due && t.due === u.hoje_iso) { pend.push('- Tarefa: ' + nome(t)); }
  });
  if (atrasadas) { pend.push('- ' + atrasadas + (atrasadas === 1 ? ' tarefa atrasada' : ' tarefas atrasadas') + ' (diga minhas tarefas para ver)'); }
""" + code[b:]

    sub("filter(function (t) { return t.due === amanhaIso; }).map(function (t) { return '- ' + t.title; });",
        "filter(function (t) { return t.due === amanhaIso; }).map(function (t) { return '- ' + nome(t); });")
    sub("partes.push(tarefasAbertas.length ? 'Tarefas:' + NL + tarefasAbertas.join(NL) + (semPrazo > 5 ? NL + '- e mais ' + (semPrazo - 5) + ' sem prazo' : '') : 'Tarefas: nenhuma.');",
        "const linhasT = tarefasHoje.slice();\n  if (linhaCont) { linhasT.push(linhaCont); }\n  partes.push(linhasT.length ? 'Tarefas:' + NL + linhasT.join(NL) : 'Tarefas: nenhuma.');")
    s = s[:j] + json.dumps(code, ensure_ascii=False) + s[k + 1:]

    # ---- 4. ligacao
    i0 = s.index(".onCase(0, agendaAdrianHoje.to(tarefasResumo.to(")
    i1 = s.index("\n", i0)
    orig = s[i0:i1]
    rest = orig[len(".onCase(0, agendaAdrianHoje.to(tarefasResumo.to("):]   # projPlano...)))
    nova = ".onCase(0, agendaAdrianHoje.to(agPegar.to(agSeparar.to(agTem.onTrue(agCriar.to(agJuntar.to(agMarcar.to(tarefasResumo.to(" + rest + ")).onFalse(tarefasResumo)))))"
    s = s[:i0] + nova + s[i1:]
    s = s.replace(".onCase(1, agendaMariaHoje.to(tarefasResumo))", ".onCase(1, agendaMariaHoje.to(agPegar))").replace(".onCase(2, tarefasResumo)))", ".onCase(2, agPegar)))")
    return s


PERFIS = [('disparador.sdk.js', perfil_base), ('disparador_projetos.sdk.js', perfil_projetos), ('disparador_resumo.sdk.js', perfil_resumo)]


if __name__ == '__main__':
    args = sys.argv[1:]
    if '--out' in args:
        d = args[args.index('--out') + 1]; os.makedirs(d, exist_ok=True)
        for fn, f in PERFIS:
            open(os.path.join(d, fn), 'w', newline='').write(f())
    elif '--write' in args:
        for fn, f in PERFIS:
            open(os.path.join(HERE, fn), 'w', newline='').write(f())
    else:
        ok = True
        for fn, f in PERFIS:
            gen = f().encode(); cur = open(os.path.join(HERE, fn), 'rb').read()
            same = gen == cur; ok = ok and same
            print('%-28s %s gerado=%s atual=%s' % (fn, 'OK  ' if same else 'DIFF', hashlib.sha256(gen).hexdigest()[:16], hashlib.sha256(cur).hexdigest()[:16]))
        sys.exit(0 if ok else 1)
