# Plano de melhorias de arquitetura (08/11/2026)

Origem: revisão de arquitetura (candidatos 1 a 5). Baseline git: commit `0334ac4`.

## Regras para todas as etapas
- Nada vai para produção: não enviar workflow ao n8n, não aplicar SQL no banco, não usar SSH/VPS, não rodar `tests/natural/run.py`.
- Refatoração sem mudança de comportamento: o workflow gerado (`modified.json`, `main.sdk.js`) deve continuar **idêntico** ao do baseline, salvo onde a etapa disser o contrário.
- Cada etapa mexe só nos seus arquivos (lista abaixo), para rodar em paralelo.

| # | Etapa | Arquivos próprios | Pronto quando |
|---|---|---|---|
| 4 | git no lugar de snapshots | `.gitignore` (feito, commit baseline) | repositório criado; snapshots permanecem até o dono aprovar a remoção |
| 1 | Registro de Intenções | `tools/n8n-gen/intents/` (novo), `gen.py`, `patch_f10*`, `patch_f11*` | geração idêntica ao baseline + checagem de consistência do registro |
| 2 | Executor local dos nós Code | `tools/n8n-gen/nodetest/` (novo), `tests/offline/` (novo) | testes offline rodam sem rede e passam |
| 3 | Esquema SQL atual | `agente-telegram/db/current/` (novo) | uma definição atual por função + script de conferência |
| 5 | Molde de Agenda | `tools/n8n-gen/subworkflows/` | agenda_adrian/maria gerados do molde, idênticos aos atuais |
