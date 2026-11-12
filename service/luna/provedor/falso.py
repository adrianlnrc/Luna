"""Provedores sem rede: roteiro (testes) e regras (uso local sem chave de API)."""
from __future__ import annotations

import itertools
from typing import Callable

from .base import Chamada, RespostaModelo, Turno

_seq = itertools.count(1)


def chamada(nome: str, **args) -> Chamada:
    return Chamada(id=f"c{next(_seq)}", nome=nome, args=args)


class ProvedorRoteiro:
    """Devolve respostas pre-gravadas, na ordem. Cada item pode ser RespostaModelo, str, lista de Chamada,
    ou uma funcao (turnos, ferramentas) -> um desses. Guarda tudo o que recebeu, para os testes conferirem."""

    nome = "roteiro"

    def __init__(self, roteiro: list | None = None, transcricao: str = ""):
        self.roteiro = list(roteiro or [])
        self.recebidos: list[tuple[list[Turno], list[dict], str]] = []
        self.transcricao = transcricao
        self.atraso: float = 0.0
        self.erro: Exception | None = None

    def _norm(self, item, turnos, ferramentas) -> RespostaModelo:
        if callable(item):
            item = item(turnos, ferramentas)
        if isinstance(item, RespostaModelo):
            return item
        if isinstance(item, str):
            return RespostaModelo(texto=item, tokens_in=100, tokens_out=20, modelo="roteiro")
        if isinstance(item, Chamada):
            item = [item]
        return RespostaModelo(chamadas=list(item), tokens_in=100, tokens_out=20, modelo="roteiro")

    async def responder(self, turnos, ferramentas, modelo, esquema=None) -> RespostaModelo:
        import asyncio
        self.recebidos.append((list(turnos), list(ferramentas), modelo))
        if self.atraso:
            await asyncio.sleep(self.atraso)
        if self.erro:
            raise self.erro
        if not self.roteiro:
            return RespostaModelo(texto="(fim do roteiro)", tokens_in=10, tokens_out=5, modelo="roteiro")
        r = self._norm(self.roteiro.pop(0), turnos, ferramentas)
        if not r.modelo or r.modelo == "roteiro":
            r.modelo = modelo
        return r

    async def transcrever(self, audio: bytes, nome: str, modelo: str) -> tuple[str, int]:
        return self.transcricao, 3


class ProvedorFuncao:
    """Provedor dirigido por uma funcao (turnos, ferramentas, modelo) -> RespostaModelo|str|[Chamada]."""

    nome = "funcao"

    def __init__(self, fn: Callable):
        self.fn = fn
        self.recebidos: list = []

    async def responder(self, turnos, ferramentas, modelo, esquema=None) -> RespostaModelo:
        self.recebidos.append((list(turnos), list(ferramentas), modelo))
        r = ProvedorRoteiro()._norm(self.fn(turnos, ferramentas, modelo), turnos, ferramentas)
        r.modelo = r.modelo if r.modelo and r.modelo != "roteiro" else modelo
        return r

    async def transcrever(self, audio: bytes, nome: str, modelo: str) -> tuple[str, int]:
        return "", 0
