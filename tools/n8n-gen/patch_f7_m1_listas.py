# ---------- Onda 2, M1: lista de compras, lista em tracos, tarefa solta para projeto ----------
# Depende de db/025_listas_compras.sql (apelidos de lista, f_lists/f_projects/f_menu embrulhados).
# Ancoras alteradas (todas com rep, unicas):
#   Interpretar resposta : "const needsTime = ['create_reminder', 'create_event', 'provide_time'].indexOf(out.intent) >= 0;"
#                          (insere o trecho da lista em tracos antes dele)
#   Montar pedido a IA   : "SEM horario, e uma ACAO a fazer: ligar pro contador, pagar o IPTU, renovar a CNH; itens de compra em lista sao list_manage)"
#                          "comprar leite, sem citar lista nem mercado = create_task." (regra LISTA x TAREFA x NOTA x LEMBRETE)
#                          "Acao a fazer (ligar, pagar, comprar) segue a regra de tarefas." (regra ANOTA CURTO)
#                          "  'FINANCAS categorias: " (insere as regras novas antes)
# Schema da IA: nenhum campo novo (usa list_*, project_tasks e task_name='solta' ja existentes).
from intents import REGISTRY
REGISTRY.apply('list_manage.compras', globals())
