# Contrato do db/035 (memória unificada, Etapa 3)

Arquivo: `db/035_memoria_unificada.sql`. NÃO aplicado em produção. Aplicar antes de enviar o workflow principal. Idempotente. Sem IA no banco. Schema `agente`. Todas as funções devolvem `jsonb` (exceto onde indicado) e sempre recebem o `user_id` interno (`users.id`), nunca o telegram_id.

## Estrutura Pessoas / Lugares / Memória

- **Pessoas = `contacts`** (colunas novas `relation` = parentesco, `aliases` = apelidos). Pessoa sem e-mail guarda `email = ''` (a coluna segue NOT NULL para não quebrar as funções antigas). Grupos continuam em `contact_groups` / `contact_group_members`.
- **Lugares = `places`** (coluna nova `aliases`). Lugar sem endereço guarda `address = ''`.
- **Memória = `user_memory`** (nova): `texto`, `tipo` (habito | preferencia | fato | relacao), `origem`, `criado_em`, `ultimo_uso`, `usos`, `ativo`. Teto de 40 ativos por usuário.
- Views de leitura: `v_pessoas`, `v_lugares` (com `user_id`; sempre filtrar por usuário).
- Interruptores: `user_switches` (`mem_enabled`, `offer_save_enabled`, `suggest_enabled`; sem linha = tudo ligado).
- Backups criados uma vez: `_bak_f11_contacts`, `_bak_f11_places`, `_bak_f11_contact_groups`, `_bak_f11_contact_group_members`.
- Nenhum dado é movido: em produção `contacts` só tem pessoas (e-mail é validado no `f_contact_save`) e `places` só tem lugares. A "duplicidade" era de roteamento e exibição: `f_contacts` desvia `place_*` para `f_places`, e o texto de `/contatos` (`f_command_data_base`, chave `contatos`) lista também os locais. Isso NÃO foi alterado (para o workflow atual não mudar); a separação visível vem das funções de listagem abaixo, que o workflow passa a usar.

## Funções que o workflow usa

### Prompt (gancho único)
- `f_mem_prompt_txt(p_user bigint, p_msg text) -> text`. Vazio se memória desligada ou sem fatos; senão `"MEMORIA (fatos ...):\n- fato\n- fato"` (até 8 linhas: os que casam com palavras da mensagem + até 4 recentes). Chamar na query "Buscar usuario" como `f_recent_actions_txt`, concatenando no FIM do prompt (`... || E'\n\n' || f_mem_prompt_txt(u.id, <mensagem>)` quando não vazio). Efeito colateral intencional: marca `ultimo_uso/usos` nos fatos que casaram (protege-os do descarte do teto). Chamar uma vez por mensagem.

### Gravar e esquecer
- `f_mem_add(p_user, p_texto text, p_tipo text DEFAULT 'fato', p_origem text DEFAULT 'ia')`. Chamar para cada item do campo novo do JSON de intenção. Devolve `{ok, duplicate, id, tipo, evicted, text}`; `text` = `"Anotei: ..."` ou `"Já estava anotado: ..."` (usar na linha de aviso). `{ok:false, disabled:true, text:''}` se memória desligada (não avisar nada); `{ok:false, error:'vazio'}`. Tipo aceita variações (hábitos, preferências, relações); desconhecido vira `fato`. Texto vai a 200 caracteres.
- `f_mem_forget(p_user, p_ref text)`. `p_ref` = id (`12` ou `#12`), trecho do texto, ou `''`/`isso`/`ultimo` = último anotado. Devolve `{ok, found, removed[], text}`; se mais de um casa: `{ok:false, found:true, count, ambiguous:[{id,texto}] (até 8), text}` com a pergunta "Qual eu esqueço?" (não apaga). É "soft delete" (`ativo=false`); só apaga fatos da memória (pessoas e lugares seguem pelos fluxos de remoção existentes com confirmação).

### Listagens por tipo
- `f_list_pessoas(p_user)` -> `{text, pessoas, grupos}` para `/contatos` (só pessoas e grupos; mostra parentesco, "sem e-mail", apelidos).
- `f_list_lugares(p_user)` -> `{text, lugares}` para `/locais` (só lugares; "sem endereço ainda" quando vazio).
- `f_mem_list(p_user, p_filtro text DEFAULT '')` -> `{text, total, pessoas, lugares, memoria, items[{id,tipo,texto}], switches}` para `/memoria`. Filtro: `''` (tudo), `pessoas|contatos|grupos`, `lugares|locais`, `memoria`, `habito|preferencia|fato|relacao` (e plurais), ou texto livre (busca nas três). `items` traz só os fatos (para botões "apagar #id").

### Interruptores
- `f_mem_set_switch(p_user, p_name text, p_value boolean)` -> `{ok, name, value, text}`. Nomes: `mem_enabled`, `offer_save_enabled`, `suggest_enabled`, ou apelidos em português (`memoria`, `sugestoes`, `perguntar se salvo`, `oferta`). Nome inválido: `{ok:false, error:'nome_invalido'}`.
- `f_mem_switches(p_user)` -> `{mem_enabled, offer_save_enabled, suggest_enabled}`. `f_mem_sw(p_user, p_name) -> boolean`.
- Mapeamento sugerido de frases: "para de perguntar se salvo" -> offer_save_enabled=false; "sem sugestões" -> suggest_enabled=false; "não guarda nada / esquece tudo" (memória) -> mem_enabled=false.

### Oferta de salvar (depois de concluir a tarefa)
1. `f_offer_candidates(p_user, p_pessoa text DEFAULT '', p_lugar text DEFAULT '')` (não grava). Devolve `{enabled, offer, offer_person, offer_place, ask_email, ask_address, person:{name,status,id,has_email,silenced_until}|null, place:{name,status,id,has_address,silenced_until}|null, message}`. `status`: `new | exists | silenced | self | group | none`. `message` é a pergunta única pronta ("Quer adicionar Maria Luisa nos contatos e salvar o lugar "igreja"? Se quiser, me manda o e-mail e o endereço."), vazia quando `offer=false`. Busca tolerante a acento/caixa/artigo, apelido e nome parcial único ("Maria" acha "maria luisa"; "Igreja Matriz" acha "igreja"). Uma mensagem cobre no máximo 1 pessoa e 1 lugar (o workflow passa só um de cada).
2. Se `offer=true`: o workflow envia `message` DEPOIS da resposta da tarefa e guarda `{pessoa, lugar}` pendentes (Redis/estado do chat, como já faz nos fluxos pendentes).
3. "Sim": `f_offer_accept(p_user, p_pessoa, p_email, p_lugar, p_endereco, p_parentesco DEFAULT '')` -> `{ok, person:{status created|updated,id,name,email,parentesco}, place:{...address}, email_invalid, text}`. E-mail e endereço opcionais. Quando o usuário mandar o e-mail/endereço depois, chamar de novo com os mesmos nomes: completa o registro, não duplica. E-mail inválido é descartado e sinalizado (`email_invalid`), o resto é salvo.
4. "Não": `f_offer_decline(p_user, p_pessoa, p_lugar)` -> `{ok, silenced, until, text}`; silencia 30 dias (`save_offers_silenced`). Salvar de verdade remove o silêncio.
- Só oferecer quando `offer=true`; o resultado já considera interruptor, silêncio, "eu mesmo" (nome/apelido do usuário) e nomes de grupo.

### Sugestão proativa
- `f_suggest_pick(p_user, p_dry boolean DEFAULT false)` -> `{suggest:false, reason}` (`disabled | already_today | no_pattern | no_user`) ou `{suggest:true, kind:'conta'|'lembrete', key, text, data, dry}`. Máximo 1 por dia por usuário (UNIQUE `user_id, day` em `suggestions_log`, no fuso do usuário); a mesma sugestão (`key`) não volta em 30 dias. Padrões: (conta) gasto com a mesma descrição em 3+ meses no mesmo dia do mês (±4 dias), sem lançamento neste mês, sem conta fixa ativa, e hoje já é (ou passou até 10 dias) o dia típico; (lembrete) mesmo título criado 3+ vezes em 60 dias sem repetição configurada. Chamar SEM `p_dry` consome a vez do dia. Onde chamar: ao final de uma conversa normal do dia (primeira interação, depois da resposta da tarefa), anexando `text` como pergunta; não no resumo automático. Se o usuário aceitar, o workflow trata como pedido comum ("sim" cadastra a conta/o lembrete repetido pelas ações já existentes usando `data`). Na maioria dos dias devolve `no_pattern`.

### Alteração em função existente
- `f_resolve_invitees(p_user, p_names text[])`: idêntica ao original, exceto que contato com `email=''` cai em `unknown` (nunca vira convidado com e-mail vazio). Para quem hoje tem e-mail em todos os contatos o resultado é o mesmo.

## Funções auxiliares (não precisam ser chamadas pelo workflow)
`f_find_pessoa(user, nome) -> bigint`, `f_find_lugar(user, nome) -> bigint`, `f_mem_tokens(text) -> text[]`, `f_mem_tipo(text) -> text`, `f_mem_switch_name(text) -> text`, `f_mem_relevant_txt(user, msg, max=8) -> text`.

## O que ficou de fora
- Extração dos fatos e das entidades (pessoa/lugar/fato) é feita pela IA na mesma chamada de intenção; o banco só guarda. Campos novos do JSON de intenção, regras de prompt e botões/Redis de "pendência da oferta" são do workflow (não mexido aqui).
- `/contatos` e `/locais` ainda exibem como antes enquanto o workflow não trocar para `f_list_pessoas` / `f_list_lugares`; `f_command_data_base` e o roteamento `place_*` de `f_contacts` foram mantidos de propósito (compatibilidade). O menu e os comandos terão grilling próprio.
- Sem busca de endereço no Maps (backlog). Sem parser de "sim/não" nem de e-mail/endereço em texto livre (a IA extrai e chama `f_offer_accept`).
- Sem RLS do Postgres: o isolamento por usuário é feito por `user_id` em todas as funções (o workflow usa uma única role). Contato sem e-mail aparece na listagem antiga de `/contatos` como `Nome - ` (só estética, até a troca para `f_list_pessoas`).
- Sugestões: só os dois padrões acima; não há aprendizado de "ignorou N vezes"; mantém só o limite de 1/dia e 30 dias por sugestão.
- Memória: sem embeddings; relevância por palavras (prefixo, plural simples). Fatos esquecidos/descartados ficam 30 dias inativos e depois são apagados na próxima gravação.
