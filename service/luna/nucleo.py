"""Nucleo: junta os servicos de que o agente precisa. E o unico objeto passado entre os modulos."""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Callable

from .busca import Busca, BuscaFalsa
from .canais.base import Canal
from .config import Config
from .db import Banco
from .estado import Estado, EstadoMemoria
from .ferramentas.base import Registro
from .google.base import Google, GoogleFalso
from .provedor.base import Provedor
from .tipos import Usuario


@dataclass
class Nucleo:
    cfg: Config
    banco: Banco
    provedor: Provedor
    canal: Canal
    registro: Registro
    estado: Estado = field(default_factory=EstadoMemoria)
    google: Google = field(default_factory=GoogleFalso)
    busca: Busca = field(default_factory=BuscaFalsa)
    relogio: Callable[[], datetime] = lambda: datetime.now(timezone.utc)
    _modelos: dict = field(default_factory=dict)
    _modelos_ate: float = 0.0

    def agora(self) -> datetime:
        return self.relogio()

    async def modelo(self, papel: str) -> str:
        """Modelo de um papel (ai_model_roles), com cache curto: trocar na tabela vale sem novo deploy."""
        if time.monotonic() > self._modelos_ate:
            async with self.banco.anonimo() as cx:
                linhas = await cx.linhas("SELECT papel, modelo FROM agente.ai_model_roles")
            self._modelos = {l["papel"]: l["modelo"] for l in linhas}
            self._modelos_ate = time.monotonic() + 30
        return self._modelos.get(papel) or self._modelos.get("simples") or "gpt-6-luna"

    def esquecer_modelos(self) -> None:
        self._modelos_ate = 0.0

    async def usuario(self, user_id: int) -> Usuario | None:
        async with self.banco.usuario(user_id) as cx:
            u = await cx.linha(
                "SELECT id, name, timezone, nickname, papel, status, calendar_key, no_emoji, onboarding_step, debug_trace "
                "FROM agente.users WHERE id = %s", user_id)
        if not u:
            return None
        return Usuario(id=u["id"], nome=u["name"], fuso=u["timezone"], apelido=u["nickname"], papel=u["papel"],
                       status=u["status"], google=bool(u["calendar_key"]), sem_emoji=u["no_emoji"],
                       onboarding=u["onboarding_step"], debug=u["debug_trace"])
