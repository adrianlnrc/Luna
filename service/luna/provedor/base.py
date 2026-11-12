"""Camada fina de provedor de IA (PRD RF-04). O agente so conhece esta interface."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Protocol


@dataclass
class Chamada:
    id: str
    nome: str
    args: dict


@dataclass
class Turno:
    """Mensagem em formato neutro. papel: sistema | usuario | assistente | ferramenta."""
    papel: str
    texto: str = ""
    imagens: list[tuple[bytes, str]] = field(default_factory=list)   # (bytes, mime)
    chamadas: list[Chamada] = field(default_factory=list)            # so no assistente
    chamada_id: str = ""                                             # so na ferramenta


@dataclass
class RespostaModelo:
    texto: str = ""
    chamadas: list[Chamada] = field(default_factory=list)
    tokens_in: int = 0
    tokens_out: int = 0
    modelo: str = ""
    estimado: bool = False


class Provedor(Protocol):
    nome: str

    async def responder(self, turnos: list[Turno], ferramentas: list[dict], modelo: str,
                        esquema: dict | None = None) -> RespostaModelo:
        """ferramentas: [{name, description, parameters}]. esquema: saida JSON estrita (sem ferramentas)."""
        ...

    async def transcrever(self, audio: bytes, nome: str, modelo: str) -> tuple[str, int]:
        """Devolve (texto, segundos estimados)."""
        ...
