# Registro de Intencoes

Uma Intencao (valor do enum `intent` que a IA devolve) toca varios nos do workflow. Em vez de cada patch raspar ancoras de texto,
a Intencao e declarada uma vez aqui e o motor (`core.py`) injeta cada parte na ancora certa. Os `patch_*.py` ficaram so com o que NAO e
uma Intencao (veja o fim deste arquivo).

## Interface
```python
from intents import REGISTRY
REGISTRY.apply('research', globals())   # dentro de um patch_*.py ou do gen.py (globals() = as do gen.py)
```
`Intent` (em `core.py`) declara, tudo opcional menos `name`:

| Campo | Vai para |
|---|---|
| `name`, `also`, `internal` | enum de intents (name + also) e intents internas (so rota, ex. `invite_event`) |
| `enum` / `enum_after` / `also_after` | `enum=False` se o nome ja entra por outro lugar; `enum_after='x'` posiciona depois de `x` (padrao: antes de `clarify`) |
| `hint` | descricao curta na regra INTENTS de `Montar pedido a IA` |
| `schema`, `schema_sep`, `schema_before`, `schema_parts` | propriedades do schema estrito (fim de `props`, ou antes de um texto-ancora) |
| `rules` / `raw_rules` | regras estaticas do prompt (texto simples / bloco ja formatado com trecho dinamico) |
| `prompt_ctx` | contexto variavel antes da mensagem atual |
| `interpret_js`, `send_js` | `Interpretar resposta` (antes de `if (out.intent === 'finance')`) e `Preparar envio` |
| `user_cols` | colunas SQL extras em `Buscar usuario` |
| `edits`, `sets` | trocas ancoradas / atribuicoes em qualquer no (`Edit(no, campo, antigo, novo)`) |
| `route`, `routes` | saidas do `Roteador de intencao` |
| `build()` | cria nos, conexoes, teclados e textos. **Roda com as globais do gen.py** (`nodes`, `conns`, `byname`, `pg_node`, `setc`, `add_kb`, `rep`...): declare `global nodes, byname` se for reatribuir; constantes do proprio modulo entram por `from intents.<modulo> import X` |
| `extends='finance'` | estagio/extensao de uma intent base (sem enum nem rota proprios) |
| `base=True` | intent do modelo original, so para a checagem |

Cada trecho entra em ancora fixa (constantes `A_*` em `core.py`). A ancora tem de existir exatamente uma vez, senao o gerador falha.

## A ORDEM IMPORTA
O texto final depende da ordem de `apply()` (regras, blocos de interpretacao e nos entram na ordem em que sao aplicados). Por isso uma feature
que os patches antigos montavam em pedacos fica em varios *estagios* (`finance.cartoes`, `list_manage.compras`...), aplicados nos mesmos pontos do `gen.py`.
`MODULES` em `__init__.py` so lista os arquivos; a ordem de aplicacao e a das chamadas `REGISTRY.apply()`.

## Modulos
| Arquivo | Intencoes / estagios | Aplicado em |
|---|---|---|
| `base.py` | create_reminder, create_event, list_agenda, supply_*, set_preference, provide_time, create_task, list_tasks, complete_task, clarify, chat (so checagem) | - |
| `financas.py` | `finance`, `finance.nos` | gen.py |
| `prefs_fin.py` | `finance.planejamento`, `set_preference.prefs` | patch_f2a |
| `agenda.py` | `manage_event` (+ `link_reminder` interna) | patch_agenda |
| `extras.py` | `create_reminder.repeat`, `cancel_reminder`, `finance.cartoes`, `misc_query`, `finance.cartoes_kb` | patch_extras |
| `contatos.py` | `contact_manage` (+ `invite_event` interna) | patch_fase3 |
| `documentos.py`, `listas.py`, `projetos.py`, `projetos_google.py` | `document_manage`, `list_manage`+`note_manage`, `project_manage`, `project_manage.google` | patch_docs/listas/projetos/f8_projetos_google |
| `contatos_locais.py`, `evento_locais.py` | `contact_manage.locais`, `create_event.locais` | patch_f5_cmd, patch_f5_locais |
| `correcoes.py` | `correcoes` (transversal: fin_items, supply_action, lembrete/ajuste) | patch_f6_correcoes |
| `listas_compras.py`, `fin_recibo.py`, `fin_relatorio.py`, `ai_cost.py`, `research.py` | `list_manage.compras`, `finance.recibo`, `finance.relatorio`, `ai_cost`, `research` | patch_f7_m1..m5 |
| `agenda_import.py` | `agenda_import`, `agenda_import_edit` | patch_f8_agenda_import |
| `correct_recent.py`, `memory_manage.py` | `correct_recent`, `memory_manage` | patch_f10_acoes, patch_f11_memoria |

## Como adicionar uma Intencao
1. Crie `intents/<nome>.py` com `INTENT = Intent(...)` (ou `INTENTS = [...]`) e, se precisar de nos, `build()`.
2. Inclua o arquivo em `MODULES` (`__init__.py`).
3. Chame `REGISTRY.apply('<nome>', globals())` no ponto certo do gen.py/patch (nao mude a ordem dos patches).
4. Rode `python3 gen.py`: a checagem roda sozinha. Confira que so muda o que voce quer.

## O que continua nos patches (nao e Intencao)
Cadeia Lote/Multi, "Desfazer tudo" e `Preparar envio` base da F10; regra TOM e reconciliacao do rules.json vivo (F11); persona/apelido (patch_f2a);
leitura de arquivos, historico e `Tipo de mensagem` (patch_docs, trechos do gen.py); HTML do `Preparar envio` e /start curto (F6); comandos
(`Comando: dados`, /locais, /contatos, /menu, /custo), menus (f5_menu, f13), registro de uso de IA e `simplify=false` (M4), PDF/foto (gen.py), `patch_zz_compact`.
Tambem no `gen.py`: o texto base do modelo original (enum e schema iniciais, regras de estoque/lembrete/tarefa) que define as intents `base`.

## Checagem de consistencia
`python3 intents/check.py [modified.json]` (e automatica no fim do `gen.py`): intent no enum <=> rota no Roteador <=> rota liga a no existente
com caminho ate `Preparar envio`. Erro para qualquer intent do enum sem rota, rota quebrada ou intent registrada que sumiu do enum/rota;
aviso para rota fora do enum que nao esta registrada como `internal`.
