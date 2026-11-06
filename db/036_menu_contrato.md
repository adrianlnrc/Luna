# Contrato do db/036 (menu reformulado)

Arquivo: `db/036_menu_secretaria.sql`. NAO aplicado em producao. Idempotente. Mudanca de botoes: `tools/n8n-gen/patch_f13_menu.py` (entra no `gen.py` antes de `patch_zz_compact.py`). Ordem de deploy: aplicar o SQL, depois enviar o workflow principal. Se o SQL entrar sozinho, os textos novos funcionam com os botoes antigos (as chaves antigas continuam valendo), mas "Ver mais" so aparece depois do workflow.

## f_menu(p_user bigint, p_key text) -> jsonb {text, kb, rid}

A funcao anterior foi renomeada para `f_menu_pre_f13` (so uma vez). A nova e autocontida (nao chama a cadeia antiga). O despachante `f_callback` (prefixo `mn`) nao mudou: `mn:<chave>` chama `f_menu(user, <chave>)`.

| Tela | kb | rid | Botoes (montados no workflow) |
|---|---|---|---|
| `inicio` (e qualquer chave desconhecida) | `menu` | 0 | 9 areas, 2 por linha |
| area n (1..9) | `menu_area` | n | Ver mais (`mn:mais<rid>`), Voltar ao menu (`mn:inicio`) |
| ver mais da area n | `menu_mais` | n | Voltar a area (`mn:a<rid>`), Menu (`mn:inicio`) |

### Chaves novas (ordem do menu)

| n | Area | Chave | Ver mais |
|---|---|---|---|
| 1 | Lembretes e agenda | `lemb` | `lemb_mais` ou `mais1` |
| 2 | Tarefas e listas | `tar` | `tar_mais` / `mais2` |
| 3 | Dinheiro | `din` | `din_mais` / `mais3` |
| 4 | Remedios | `rem` | `rem_mais` / `mais4` |
| 5 | Projetos | `proj` | `proj_mais` / `mais5` |
| 6 | Documentos | `doc` | `doc_mais` / `mais6` |
| 7 | Pessoas e memoria | `pess` | `pess_mais` / `mais7` |
| 8 | Fotos, audio e pesquisa | `foto` | `foto_mais` / `mais8` |
| 9 | Ajustes | `aj` | `aj_mais` / `mais9` |

Voltar a area: `a1`..`a9`.

### Chaves antigas (continuam funcionando; botoes de mensagens antigas nao quebram)

- `lembretes`, `agenda`, `resumos` -> 1 (`lemb`)
- `tarefas`, `listas` (e `notas`) -> 2 (`tar`)
- `dinheiro` -> 3; `remedios` -> 4; `projetos` -> 5; `docs` (e `documentos`) -> 6
- `pessoas` (e `contatos`, `locais`, `memoria`) -> 7 (`pess`)
- `entrada`, `pesquisa` -> 8 (`foto`)
- `ajustes` -> 9 (`aj`)
- Sufixo `_mais` tambem funciona nas chaves antigas (`dinheiro_mais`).

## Regras de texto

- Maximo 5 exemplos em "Tente dizer:" por area; detalhes extras vao no "Ver mais".
- Dica unica (substitui a falsa "uma coisa por mensagem"): "Pode mandar varios pedidos juntos: eu faco todos e mostro num Feito:. Se errar, toque em Desfazer tudo."
- Sem emoji. Nao cita oferta de salvar pessoa/lugar, sugestao do dia nem Google Maps.
- O texto de `/menu` no workflow (nó "Resposta do comando") e lido do `inicio` deste SQL pelo `patch_f13_menu.py`; se mudar um, regere o workflow.

## Comandos de barra (lista recomendada para o BotFather)

O bot nao configura isso por API. No BotFather: `/setcommands`, escolher o bot e colar:

```
menu - O que eu faço, por área
memoria - O que eu sei de você (pessoas, lugares, fatos)
config - Suas preferências
custo - Gasto de IA hoje e no mês
```

`/contatos` (so pessoas e grupos) e `/locais` (so lugares) continuam funcionando, mas saem da lista. `/start` e `/ajuda` tambem continuam (a ajuda abre o menu).

## Fora do escopo / pendente

- `/config` ainda mostra as linhas "Perguntar se salvo" e "Sugestoes" (texto montado no workflow, `patch_f11_memoria.py`); nao mexido aqui.
- A dica semanal `f_tip` (resumo da manha) cita "/menu" e nao foi alterada.
- Antigas telas por area (`f_menu_pre_f13` e a cadeia) ficam no banco so como historico.
