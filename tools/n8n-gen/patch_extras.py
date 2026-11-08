# ---------- EXTRAS (B): lembrete recorrente, cancelar lembrete, cartoes, consultas financeiras, misc_query ----------
from intents import REGISTRY
# estagios em sequencia (a ordem das regras no prompt e esta): ver intents/extras.py
for _st in ('create_reminder.repeat', 'cancel_reminder', 'finance.cartoes', 'misc_query', 'finance.cartoes_kb'):
    REGISTRY.apply(_st, globals())
