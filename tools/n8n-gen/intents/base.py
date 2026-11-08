# Intencoes BASE: nascem do workflow original (main.json) e do texto base do 'Montar pedido a IA' em gen.py (enum, schema, regras iniciais).
# Estao aqui so para a checagem de consistencia (enum <=> rota <=> handler); nao sao aplicadas pelo registro.
# create_task, list_tasks e complete_task sao roteadas por task_action; clarify e chat caem no fallback do Roteador (ver check.py).
from .core import Intent

BASE_NAMES = ['create_reminder', 'create_event', 'list_agenda', 'create_supply', 'supply_bought', 'supply_adjust', 'supply_taken',
              'supply_schedule', 'set_preference', 'provide_time', 'create_task', 'list_tasks', 'complete_task', 'clarify', 'chat']

INTENTS = [Intent(name=n, base=True) for n in BASE_NAMES]
