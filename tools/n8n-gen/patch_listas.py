# ---------- FASE 4, MODULO N: listas de itens e notas livres ----------
# A Intencao (list_manage + note_manage: regras, hint, JSON, nos, teclado, rota, textos de /ajuda) mora em intents/listas.py.
from intents import REGISTRY
REGISTRY.apply('list_manage', globals())
