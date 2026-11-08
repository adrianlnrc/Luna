# ---------- F8: importar agenda de papel por foto (compromissos -> Google Agenda, tarefas -> Google Tarefas) ----------
# Depende de db/031_agenda_import.sql (agenda_import, f_agimp_create/edit/confirm/done/cb, f_callback com o prefixo ai*)
# e do sub-workflow "Agente | Importar agenda" (id abaixo, codigo em subworkflows/importar_agenda.sdk.js).
# Entra em gen.py DEPOIS de patch_f7_m5_pesquisa.py e ANTES de patch_zz_compact.py.
#
# ANCORAS ALTERADAS (todas via rep, uma ocorrencia):
#   [Montar pedido a IA] "'research', 'clarify', 'chat'] },"          -> intents agenda_import e agenda_import_edit
#   [Montar pedido a IA] "research_query: NN('string')\n};"            -> campos imp_action, imp_n, imp_end (nulaveis)
#   [Montar pedido a IA] ", clarify (falta informacao essencial"       -> lista de INTENTS (regra estatica)
#   [Montar pedido a IA] "  'FINANCAS categorias: "                     -> regra estatica AGENDA DE PAPEL (vai para rules.json)
#   [Interpretar resposta] "if (out.intent === 'finance') {"          -> agenda_import sem foto vira chat; monta imp_json da correcao
#   [Executar botao] saida passa por 'Importar agenda: botao em massa?' antes de 'Agenda: acao externa?'
# MUDANCAS DE SCHEMA DA IA: intent += agenda_import, agenda_import_edit; campos novos imp_action (enum+null), imp_n, imp_end.
# NOS NOVOS (prefixo 'Importar agenda: '): montar pedido, ler foto (OpenAI nativo), normalizar, rascunho (Postgres), editar (Postgres),
#   criar em massa? / botao em massa? (If), executar (Execute Workflow), preparar conclusao, concluir (Postgres), resposta (Code); teclado 'agimp'.
from intents import REGISTRY
REGISTRY.apply('agenda_import', globals())
