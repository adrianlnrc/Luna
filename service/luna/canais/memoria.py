"""Canal em memoria: usado nos testes e no modo local (linha de comando)."""
from __future__ import annotations

import itertools

from ..tipos import Arquivo, Mensagem, Saida


class CanalMemoria:
    nome = "memoria"

    def __init__(self) -> None:
        self.enviadas: list[tuple[str, Saida]] = []
        self.digitando: list[str] = []
        self.arquivos: dict[str, bytes] = {}
        self.botoes_encerrados: list[tuple[str, str]] = []
        self._seq = itertools.count(1)

    def receber(self, bruto: dict) -> Mensagem | None:
        return Mensagem(**bruto)

    async def enviar(self, chat_id: str, saida: Saida) -> str:
        self.enviadas.append((chat_id, saida))
        return str(next(self._seq))

    async def indicar_digitando(self, chat_id: str) -> None:
        self.digitando.append(chat_id)

    async def baixar(self, arquivo: Arquivo) -> bytes:
        return self.arquivos.get(arquivo.file_id, b"")

    async def encerrar_botoes(self, chat_id: str, msg_id: str) -> None:
        self.botoes_encerrados.append((chat_id, msg_id))

    # ajudas de teste
    def textos(self) -> list[str]:
        return [s.texto for _, s in self.enviadas]

    def ultima(self) -> Saida:
        return self.enviadas[-1][1]

    def limpar(self) -> None:
        self.enviadas.clear()
