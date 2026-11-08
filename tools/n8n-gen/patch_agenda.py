# ---------- A1: gestao de agenda (mover/cancelar, conflito, horario livre, recorrentes, lembrete ligado, promover, convites) ----------
from intents import REGISTRY
REGISTRY.apply('manage_event', globals())
