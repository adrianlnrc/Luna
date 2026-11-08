"""Registro declarativo de Intencoes do agente (ver README.md).

Uso no gen.py / patches:   REGISTRY.apply('nome_da_intent', globals())
Checagem de consistencia:  python3 intents/check.py   (le modified.json) ou check(workflow_dict).
"""
import importlib

from .core import Intent, Edit, Set, Registry, schema_add, enum_add, once, safe_rule  # noqa: F401

# Modulos de Intencao (um arquivo por modulo; INTENT = Intent(...)). A ORDEM DE APLICACAO e a das chamadas
# REGISTRY.apply() nos patch_*.py, nao a desta lista.
MODULES = ('base', 'correct_recent', 'memory_manage', 'research', 'ai_cost', 'contatos', 'extras', 'documentos', 'listas', 'projetos', 'projetos_google', 'agenda', 'fin_recibo', 'fin_relatorio', 'listas_compras', 'contatos_locais', 'evento_locais', 'agenda_import', 'correcoes', 'prefs_fin', 'financas')

REGISTRY = Registry()
for _m in MODULES:
    _mod = importlib.import_module('.' + _m, __name__)
    for _it in (getattr(_mod, 'INTENTS', None) or [_mod.INTENT]):
        REGISTRY.register(_it)
