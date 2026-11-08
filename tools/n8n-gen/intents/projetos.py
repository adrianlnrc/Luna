# Intencao project_manage (P): projetos com tarefas proprias no banco (nao e o Google Tasks).
# Depende de db (agente.f_projects, f_projects_cb). A parte Google Tarefas fica em intents/projetos_google.py.
from .core import Intent

INTERPRET = """if (out.intent === 'project_manage') {
  out.proj_json = JSON.stringify({
    action: out.project_action || '',
    name: out.project_name || '',
    title: out.title || '',
    task: out.task_name || '',
    tasks: Array.isArray(out.project_tasks) ? out.project_tasks.filter(function (x) { return String(x || '').trim() !== ''; }) : [],
    due: (out.date && okDate.test(out.date)) ? out.date : '',
    urgent: (typeof out.urgent === 'boolean') ? out.urgent : null
  });
}"""

RULES = [
 "PROJETOS: intent=project_manage para PROJETOS, que sao trabalhos maiores com varias tarefas e prazo, guardados no banco do agente (NAO e o Google Tasks). Use quando o usuario falar de PROJETO (novo projeto, no projeto X, meus projetos, como esta o projeto) ou pedir para quebrar, dividir ou planejar algo em tarefas. create_task, list_tasks e complete_task continuam sendo as pendencias SOLTAS do Google Tasks, sem projeto. Contraste: anota a tarefa ligar pro contador = create_task; adiciona a tarefa ligar pro contador ao projeto da mudanca = project_manage add_tasks; conclui a tarefa ligar pro contador (sem citar projeto) = complete_task; conclui a tarefa da proposta do projeto do site = project_manage complete_task; minhas tarefas = list_tasks; meus projetos = project_manage list. Nao e projeto: lista de compras ou de itens (list_manage), ideia ou texto solto para guardar (note_manage), lembrete com hora (create_reminder).",
 "PROJETOS acoes (project_action): create = novo projeto (project_name = nome, date = prazo YYYY-MM-DD se o usuario deu, project_tasks se ja listou tarefas); show = como esta o projeto, andamento, progresso (project_name); list = meus projetos; add_tasks = adicionar tarefas (project_name e project_tasks; uma tarefa so com prazo proprio: date = prazo); complete_task = concluir tarefa (task_name e project_name se citado); reopen_task = reabrir; set_urgent = tarefa urgente (task_name; urgent=true; urgent=false se pedir para tirar a urgencia); set_due = mudar prazo (project_name e date; se o prazo for de uma tarefa, preencha tambem task_name); rename = renomear (project_name = nome atual e title = nome novo); delete = apagar projeto (project_name); overdue = o que esta atrasado (project_name se citou um projeto, senao vazio para todos). Exemplos: novo projeto: mudanca do escritorio, prazo 30 de setembro = create, project_name mudanca do escritorio, date do proximo 30 de setembro; como esta o projeto do site? = show, project_name site; o que esta atrasado? = overdue; poe a tarefa da proposta como urgente = set_urgent, task_name proposta; muda o prazo do projeto para 15/11 = set_due, date 15/11 do ano certo; conclui a tarefa contratar frete do projeto da mudanca = complete_task, task_name contratar frete, project_name mudanca.",
 "PROJETOS quebrar em tarefas: se o usuario pedir quebra o projeto em tarefas, planeja o projeto ou o que preciso fazer para concluir o projeto, use add_tasks (ou create se o projeto ainda nao existe) e preencha project_tasks com 4 a 10 tarefas curtas, concretas e em ordem, no imperativo, ate 8 palavras cada. Se o usuario ja deu a lista (nomeou as tarefas, ex.: adiciona as tarefas pintar sala e trocar piso), use exatamente as tarefas dele e preencha task_name=lista_do_usuario: o sistema grava direto, sem pedir confirmacao. Quando VOCE sugere as tarefas (quebra, planeja), deixe task_name null. Prazo por tarefa so se o usuario disse: escreva tarefa|YYYY-MM-DD; nunca invente prazos. Nas tarefas sugeridas por voce, o sistema mostra a lista e so grava depois que o usuario confirma por botao. Datas sem ano = a proxima ocorrencia futura no fuso do usuario; datas relativas (daqui a 2 semanas) contam a partir de hoje. Em project_manage preencha reply com texto vazio e use null nos campos que nao se aplicam.",
]


# campos do schema da IA (inseridos antes da ancora, na ordem em que os modulos entram)
SCHEMA_PROJ = """project_action: { type: ['string', 'null'], enum: ['create', 'show', 'list', 'add_tasks', 'complete_task', 'reopen_task', 'set_urgent', 'set_due', 'rename', 'delete', 'overdue', null] },
  project_name: NN('string'), project_tasks: { type: ['array', 'null'], items: { type: 'string' } }, task_name: NN('string'), urgent: NN('boolean'),"""


def build():
    global nodes, byname
    IR = "$('Interpretar resposta').first().json."
    nodes += [
     pg_node("Projetos: Executar", "SELECT agente.f_projects($1::bigint, $2::jsonb) AS r",
             "={{ [ " + IR + "user_id, " + IR + "proj_json ] }}", [4480, 4176]),
     code_node("Projetos: Resposta", "const a = $('Interpretar resposta').first().json;\nconst r = $input.first().json.r || {};\n"
       "return [{ json: { chat_id: a.chat_id, text: r.text || 'Nao consegui mexer nos projetos agora. Tente de novo.', kb: r.kb || 'none', rid: r.rid || 0, state: '' } }];", [4704, 4176]),
    ]
    _refresh()
    byname['Projetos: Executar']['onError'] = 'continueRegularOutput'
    setc('Projetos: Executar', ['Projetos: Resposta'])
    setc('Projetos: Resposta', ['Preparar envio'])
    # teclados: pj_tasks (pjok/pjno:<pending>) e pj_del (pjdel/pjkeep:<projeto>); tratados em agente.f_projects_cb
    add_kb('pj_tasks', [('Gravar tarefas', 'pjok:{rid}'), ('Cancelar', 'pjno:{rid}')])
    add_kb('pj_del', [('Sim, apagar', 'pjdel:{rid}'), ('Nao', 'pjkeep:{rid}')])
    _refresh()


INTENT = Intent(
    name='project_manage',
    enum_after='list_manage',
    schema_parts=[(SCHEMA_PROJ, "\n  ", "note_action: { type")],
    rules=RULES,
    interpret_js=INTERPRET,
    route=('projetos', 'Projetos: Executar'),
    build=build,
)
