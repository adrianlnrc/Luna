# ---------- PROJETOS (P): projetos com tarefas proprias no banco (nao e o Google Tasks) ----------
# A Intencao project_manage (regras, JSON, nos, teclados e rota) mora em intents/projetos.py.
from intents import REGISTRY
REGISTRY.apply('project_manage', globals())
