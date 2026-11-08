# Extensao de list_manage (M1, onda 2): lista de compras padrao, lista em tracos, tarefa solta para projeto.
# Depende de db/025_listas_compras.sql (apelidos de lista, f_lists/f_projects/f_menu embrulhados).
from .core import Intent, Edit

# lista em formato de tracos (>= 2 linhas que comecam com - * bullet ou en-dash), so mensagem de texto
TRACO_JS = """const trSemAcento = function (s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const para = 'aaaaaeeeeiiiiooooouuuuc';
  let r = '';
  String(s || '').toLowerCase().split('').forEach(function (ch) { const k = de.indexOf(ch); r += k >= 0 ? para.charAt(k) : ch; });
  return r.trim();
};
const trListaTracos = function (txt) {
  const NL = String.fromCharCode(10);
  const linhas = String(txt || '').split(NL);
  const marcas = '-•*–';
  const itens = [];
  let primeira = -1;
  for (let i = 0; i < linhas.length; i++) {
    const t = linhas[i].trim();
    if (t === '' || marcas.indexOf(t.charAt(0)) < 0) { continue; }
    let k = 0;
    while (k < t.length && (marcas.indexOf(t.charAt(k)) >= 0 || t.charAt(k) === ' ')) { k++; }
    let item = t.slice(k).trim();
    while (item.length > 0 && ',;'.indexOf(item.charAt(item.length - 1)) >= 0) { item = item.slice(0, item.length - 1).trim(); }
    if (item === '') { continue; }
    if (primeira < 0) { primeira = i; }
    itens.push(item);
  }
  if (itens.length < 2) { return null; }
  let cab = '';
  for (let j = primeira - 1; j >= 0; j--) {
    if (linhas[j].trim() !== '') { cab = linhas[j].trim(); break; }
  }
  while (cab.length > 0 && ':.-'.indexOf(cab.charAt(cab.length - 1)) >= 0) { cab = cab.slice(0, cab.length - 1).trim(); }
  let nome = cab.replace(/^((a|o|minha|nossa) )*lista ((de|da|do|dos|das) )?/i, '').trim();
  const chave = trSemAcento(nome).split(' ').filter(function (x) { return x !== ''; }).join(' ');
  const padroes = ['', 'lista', 'mercado', 'compras', 'compra', 'supermercado', 'super', 'feira', 'feiras', 'mercados', 'preciso comprar', 'comprar', 'pra comprar', 'para comprar', 'falta', 'faltam', 'anota', 'anota ai', 'anota ai na lista'];
  const apelidos = ['mercado', 'compras', 'compra', 'supermercado', 'super', 'feira', 'feiras', 'mercados'];
  if (padroes.indexOf(chave) >= 0 || chave.split(' ').length > 4 || apelidos.indexOf(chave.split(' ')[0]) >= 0) { nome = ''; }
  return { itens: itens, nome: nome };
};
if (out.source === 'text' && u.kind === 'text') {
  const trLista = trListaTracos(u.text);
  if (trLista) {
    out.intent = 'list_manage';
    out.list_action = 'add';
    out.list_items = trLista.itens;
    out.list_name = trLista.nome || null;
  }
}
"""

RULES = [
 "LISTA DE COMPRAS PADRAO: existe uma lista padrao chamada Mercado. As palavras compras, mercado, supermercado e feira apontam todas para ela: em list_name use mercado (ou null quando o usuario nao citou lista). So use outro list_name quando o usuario pedir uma lista por outro nome (farmacia, mala, obra). Pedidos de compra SEM hora: preciso comprar leite, falta cafe, acabou o arroz, compra pao e ovos = list_manage add, list_name null, list_items [leite]. Remedio ou vitamina que ja esta nos itens de estoque cadastrados segue as regras de remedios, nao a lista. Compra COM hora (me lembra de comprar pao as 18h) = create_reminder. Em list_manage preencha reply com texto vazio.",
 "LISTA EM TRACOS: mensagem com itens em formato de lista (duas ou mais linhas comecando com traco, asterisco ou bolinha, um item por linha) = list_manage add com um item por linha em list_items (mantenha quantidades: 2 leite), list_name null (lista padrao Mercado), a nao ser que a primeira linha, antes dos tracos, nomeie outra lista (Farmacia: ... = list_name farmacia). Cabecalho Mercado, Compras ou Feira = list_name null. O sistema ja trata isso antes de voce; se chegar ate aqui, siga esta regra.",
 "TAREFA SOLTA PARA PROJETO: coloca a tarefa ligar pro contador no projeto Reforma, essa tarefa e do projeto Reforma, move a tarefa X para o projeto Y = project_manage com project_action=add_tasks, project_name = o projeto, project_tasks = [titulo da tarefa, sem verbo de pedido] e task_name=solta (nao use lista_do_usuario). Se disser essa tarefa, use o titulo da tarefa que acabou de ser criada na conversa. NAO conclua nem apague nada no Google Tasks: a resposta do sistema avisa que a tarefa solta continua la.",
 "URGENCIA EM PROJETOS: marca X como urgente, X e urgente, poe X como prioridade (tarefa de projeto) = project_manage set_urgent com task_name = X e urgent=true; tira a urgencia de X, X nao e mais urgente = set_urgent com urgent=false. Tarefas soltas do Google Tasks nao tem urgencia.",
]

INTENT = Intent(
    name='list_manage.compras',
    extends='list_manage',
    rules=RULES,
    edits=[
        Edit('Interpretar resposta', 'jsCode', "const needsTime = ['create_reminder', 'create_event', 'provide_time'].indexOf(out.intent) >= 0;",
        TRACO_JS + "const needsTime = ['create_reminder', 'create_event', 'provide_time'].indexOf(out.intent) >= 0;"),
        Edit('Montar pedido a IA', 'jsCode', "itens de compra em lista sao list_manage)",
        "itens de compra, mesmo sem citar lista (preciso comprar leite), sao list_manage)"),
        Edit('Montar pedido a IA', 'jsCode', "comprar leite, sem citar lista nem mercado = create_task.",
        "preciso comprar leite, falta cafe, acabou o arroz, compra pao (SEM hora) = list_manage add com list_name null (lista padrao Mercado) e list_items curtos; com hora = create_reminder."),
        Edit('Montar pedido a IA', 'jsCode', "Acao a fazer (ligar, pagar, comprar) segue a regra de tarefas.",
        "Acao a fazer (ligar, pagar) segue a regra de tarefas; comprar algo sem hora vai para a lista de compras.")],
)
