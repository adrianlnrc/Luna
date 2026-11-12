"""Interface de canal (PRD RF-01). Nenhum outro modulo conhece a API de um canal especifico."""
from __future__ import annotations

from typing import Protocol

from ..tipos import Arquivo, Mensagem, Saida


class Canal(Protocol):
    nome: str

    def receber(self, bruto: dict) -> Mensagem | None:
        """Converte o evento bruto do canal em Mensagem (None = ignorar)."""
        ...

    async def enviar(self, chat_id: str, saida: Saida) -> str:
        """Envia texto, botoes e/ou arquivo. Devolve o id da mensagem."""
        ...

    async def indicar_digitando(self, chat_id: str) -> None: ...

    async def baixar(self, arquivo: Arquivo) -> bytes: ...

    async def encerrar_botoes(self, chat_id: str, msg_id: str) -> None:
        """Tira os botoes de uma mensagem ja respondida."""
        ...
