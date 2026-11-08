# ---------- F8: espelho dos PROJETOS no Google Tarefas (banco = fonte de verdade; Google = espelho) ----------
# Roda DEPOIS de patch_projetos.py e ANTES de patch_zz_compact.py. Requer db/030_projetos_google.sql aplicado e o sub-workflow
# "Agente | Projetos Google" criado no n8n (tools/n8n-gen/subworkflows/projetos_google.sdk.js). O id do sub-workflow vem de
# PROJ_GOOGLE_WF_ID (variavel de ambiente) ou da constante abaixo.
from intents import REGISTRY
REGISTRY.apply('project_manage.google', globals())
