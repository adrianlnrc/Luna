"""Tipos compartilhados entre os modulos."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo


@dataclass
class Usuario:
    id: int
    nome: str
    fuso: str = "America/Sao_Paulo"
    apelido: str | None = None
    papel: str = "cliente"           # dono | cliente
    status: str = "ativo"
    google: bool = False             # users.calendar_key preenchido
    sem_emoji: bool = False
    onboarding: str = "done"
    debug: bool = False

    @property
    def tz(self) -> ZoneInfo:
        try:
            return ZoneInfo(self.fuso)
        except Exception:
            return ZoneInfo("America/Sao_Paulo")

    @property
    def como_chamar(self) -> str:
        return self.apelido or self.nome


@dataclass
class Arquivo:
    file_id: str
    tipo: str = "document"           # photo | document | audio | video
    mime: str = ""
    nome: str = ""
    tamanho: int = 0


@dataclass
class Mensagem:
    """Entrada normalizada de qualquer canal."""
    canal: str
    id_externo: str                  # quem escreveu, no canal
    chat_id: str
    tipo: str = "texto"              # texto | comando | botao | audio | foto | documento
    texto: str = ""
    arquivo: Arquivo | None = None
    acao_id: str = ""                # tipo == botao
    msg_id: str = ""                 # mensagem que trazia o botao
    update_id: str = ""
    nome_exibicao: str = ""
    grupo_midia: str = ""            # album


@dataclass
class Botao:
    rotulo: str
    acao_id: str


@dataclass
class Saida:
    """Uma mensagem a enviar. botoes e uma lista de linhas."""
    texto: str
    botoes: list[list[Botao]] = field(default_factory=list)
    arquivo: Arquivo | None = None            # reenvio por file_id
    anexo: tuple[str, bytes, str] | None = None  # (nome, bytes, mime): arquivo gerado


@dataclass
class Resultado:
    """Retorno de uma ferramenta. texto e o que o modelo le; kb/rid sao os teclados do banco."""
    ok: bool = True
    texto: str = ""
    kb: str = "none"
    rid: int | str = 0
    dados: Any = None
    erro: str = ""
    arquivos: list[Arquivo] = field(default_factory=list)
    anexo: tuple[str, bytes, str] | None = None
    saidas: list[Saida] = field(default_factory=list)   # mensagens extras prontas (ex.: confirmacao propria)

    def para_modelo(self) -> str:
        if not self.ok:
            return "ERRO: " + (self.erro or self.texto or "falhou")
        return self.texto or "ok"


def agora_utc() -> datetime:
    from datetime import timezone
    return datetime.now(timezone.utc)
