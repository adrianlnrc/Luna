# subworkflows/ - geradores e arquivos SDK do n8n

Convencao: os `*.sdk.js` sao a saida que vai para o n8n; a fonte de verdade, quando existe
gerador, e o `gen_*.py` / molde. Nada aqui envia ao n8n.

## Agenda: molde unico (etapa 5 do PLANO-MELHORIAS)

Arquivo: `agenda_molde.py` (um template, parametros por pessoa e por variante).

| Saida | pessoa | variante |
|---|---|---|
| `agenda_adrian.sdk.js`, `agenda_maria.sdk.js` | calendario + credencial Google Calendar | `base` (no nativo googleCalendar cria o evento) |
| `agenda_adrian.live.sdk.js`, `agenda_maria.live.sdk.js` | idem | `live` (Code "Montar evento" + HTTP POST; recorrencia padrao, Meet, lembretes) |

Parametros por pessoa (dict `PESSOAS`): `cal`, `credid`, `credname`, `key`, `name`.
Variantes (dict `VARIANTS`): normalizador, no de criacao, posicao do "Normalizar saida", saida final.

```
python3 agenda_molde.py --check       # gera em memoria e compara byte a byte com os 4 arquivos (exit 0 = identicos)
python3 agenda_molde.py --out DIR     # grava os 4 em DIR (nao toca os atuais)
python3 agenda_molde.py --write       # regrava ao lado (so use depois de --check; hoje e no-op)
```

Para nova pessoa: adicionar entrada em `PESSOAS`. Para mudar logica de agenda: editar o molde,
rodar `--check` (vai acusar DIFF), revisar e so entao `--write`.

### gen_agenda.py (aposentado)
Removido: estava defasado (nao produzia `no_reminders` nem `useDefaultReminders` por expressao e nao
cobria o `.live`). `agenda_molde.py` o substitui; o historico esta no git.

## Disparadores: gerador unico (etapa 5, rodada 2)

Arquivo: `gen_disparador.py`, com o modulo base `disparador_base.js` (copia fiel do texto de
`disparador.sdk.js`; para mudar o que e comum aos tres, edite o base e rode `--check`/`--write`).

```
disparador_base.js --perfil base-->  disparador.sdk.js
        |--perfil projetos (gen_projetos_google.disparador)--> disparador_projetos.sdk.js
                  |--perfil resumo (logica absorvida de gen_resumo_enxuto.py)--> disparador_resumo.sdk.js
```
```
python3 gen_disparador.py --check    # sha256 gerado x atual dos 3 (exit 0 = identicos)
python3 gen_disparador.py --out DIR  # grava em DIR
python3 gen_disparador.py --write    # regrava ao lado (so depois de --check)
```
Os tres perfis sao byte a byte identicos aos arquivos atuais. O id do sub-workflow Projetos Google
(`G5N2OpaT2v6Pczcl`) e o padrao; sobrescreva com `PROJ_GOOGLE_WF_ID` (e `TAREFAS_RESUMO_WF_ID` para o resumo).

### Decisao sobre os geradores antigos
- `gen_resumo_enxuto.py`: APAGADO. Sua unica saida era `disparador_resumo.sdk.js`; a logica virou
  `perfil_resumo` em `gen_disparador.py`.
- `gen_projetos_google.py`: MANTIDO. E a origem de `projetos_google.sdk.js` e `projetos_backfill.sdk.js`
  (nao gerados pelo novo). Unica mudanca: `disparador(s=None)` agora aceita o texto base; a saida
  `disparador_projetos.sdk.js` dele continua identica, mas a fonte canonica dos disparadores e `gen_disparador.py`.

### Estrutura (analise original)
Comparacao por bloco `const X = ...`: ~35 blocos identicos nos tres (envios, gatilho/selecao do resumo,
ramo de convites `conv*`); projetos e resumo acrescentam `WF_PROJETOS_GOOGLE`, `proj*`; so o resumo
acrescenta `ag*` e altera `tarefasResumo`, `montarResumo` e o `export default`.
Possivel passo futuro (muda workflow vivo, precisa de teste no n8n): transformar o ramo de convites
em sub-workflow.
