# db/current: versão atual das funções SQL

**Derivado das migrações. Não edite nada aqui.** As migrações `db/NNN_*.sql` continuam sendo o histórico e a fonte da verdade; esta pasta só mostra "como cada função ficou no fim".

## Como ler
- `functions/<nome>.sql`: uma função por arquivo, com o texto da **última** definição e um cabeçalho dizendo de qual migração/linha ela veio e por quais migrações passou. Sobrecargas ganham sufixo com os tipos (`nome__bigint_text.sql`).
- `INDEX.md`: tabela com todas as funções, assinatura, origem e número de definições.
- Padrão "renomeia a antiga e recria" (ex.: `f_menu` chama `f_menu_pre_f13`, que chama `f_menu_pre_m5`...): as migrações fazem `ALTER FUNCTION ... RENAME TO *_pre_*/*_base` e criam uma nova. Cada elo da cadeia aparece como arquivo próprio; o texto de um elo renomeado ainda traz o nome original no `CREATE`, e o cabeçalho avisa. Para entender uma função "casca", siga a cadeia.

## Como regenerar / conferir
```
python3 agente-telegram/db/current/build_current.py     # reescreve functions/ e INDEX.md
python3 agente-telegram/db/current/check_current.py     # confere se está em dia; lista alertas
python3 agente-telegram/db/current/check_current.py --strict   # alertas também falham (saída 2)
```
Rode o `build` sempre que criar uma migração nova com funções. Só biblioteca padrão; não conecta a nenhum banco.

## O que o parser faz (e não faz)
- Lê as migrações `.sql` em ordem numérica (`011` < `011b` < `012`); ignora os `.md` (contratos).
- Entende comentários, strings, `E'...'`, identificadores entre aspas e dollar-quoting (`$$`, `$tag$`), inclusive aninhado (`DO $$ ... EXECUTE $w$ CREATE FUNCTION ... $w$ ... $$`).
- Simula `CREATE [OR REPLACE] FUNCTION`, `ALTER FUNCTION ... RENAME TO` e `DROP FUNCTION`. A identidade da função é nome + tipos dos argumentos de entrada (nomes de parâmetros e DEFAULT não contam).
- Definições dentro de `DO ... IF to_regproc(...) IS NULL` são tratadas como executadas (num banco novo aplicando tudo em sequência é o que acontece).
- **Não reflete** atributos mudados por `ALTER FUNCTION ... SET search_path` dinâmico (004 a 007, via `EXECUTE format(...)`): funções criadas sem `SET search_path` no texto recebem `agente, public` no banco. Também não trata `GRANT`, `COMMENT ON`, triggers e views.

## Comparar com o banco (opcional, só quando o dono quiser; nada disso foi rodado)
Rodar no banco `AgenteTelegram` (somente leitura) e comparar com `functions/`:
```sql
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args, pg_get_functiondef(p.oid) AS def
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'agente' AND p.prokind = 'f'
ORDER BY 1, 2;
```
O `pg_get_functiondef` normaliza o texto (formatação, `SET search_path`), então a comparação é por conteúdo do corpo, não byte a byte. Diferenças de nome/assinatura (função no banco que não está em `INDEX.md`, ou vice-versa) são o sinal útil.
