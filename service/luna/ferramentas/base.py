"""Registro de ferramentas (PRD RF-05). Cada ferramenta e um dominio; cada acao tem um nivel de autonomia (RF-06).

Schema estrito: todo campo e obrigatorio e aceita null; nao ha campos extras. O usuario NUNCA e argumento do modelo:
vem do contexto da execucao.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Awaitable, Callable

from ..tipos import Resultado

# niveis (PRD RF-06)
CONSULTA, CRIA, ALTERA, TERCEIROS = 0, 1, 2, 3


@dataclass
class Acao:
    nome: str
    nivel: int
    descricao: str = ""
    nativa: bool = False        # o proprio banco pede confirmacao (cria pendencia e devolve botoes): chamar ja e propor
    web: bool = False           # traz conteudo externo: contamina a execucao (RF-06 regra 2)
    resumo: Callable[[dict], str] | None = None

    @property
    def escreve(self) -> bool:
        return self.nivel > CONSULTA


def S(tipo: str, desc: str = "", enum: list | None = None) -> dict:
    """Campo simples que aceita null."""
    d: dict = {"type": [tipo, "null"]}
    if desc:
        d["description"] = desc
    if enum is not None:
        d["enum"] = list(enum) + [None]
    return d


def L(tipo: str = "string", desc: str = "") -> dict:
    d: dict = {"type": ["array", "null"], "items": {"type": tipo}}
    if desc:
        d["description"] = desc
    return d


@dataclass
class Ferramenta:
    nome: str
    descricao: str
    acoes: dict[str, Acao]
    parametros: dict[str, dict]
    executar: Callable[[Any, str, dict], Awaitable[Resultado]]
    saude: bool = False         # exige aceite de dados de saude (RF-14)
    google: bool = False        # precisa do Google conectado para gravar

    def esquema(self) -> dict:
        linhas = []
        for a in self.acoes.values():
            linhas.append(f"- {a.nome}: {a.descricao}" if a.descricao else f"- {a.nome}")
        props: dict = {"acao": {"type": "string", "enum": list(self.acoes.keys())}}
        props.update(self.parametros)
        return {
            "name": self.nome,
            "description": self.descricao + "\nAcoes:\n" + "\n".join(linhas),
            "parameters": {"type": "object", "properties": props, "required": list(props.keys()),
                           "additionalProperties": False},
        }

    def validar(self, args: dict) -> tuple[str, dict, str]:
        """Devolve (acao, argumentos limpos, erro). Campos desconhecidos sao descartados; ausentes viram None."""
        if not isinstance(args, dict):
            return "", {}, "argumentos invalidos"
        acao = str(args.get("acao") or "")
        if acao not in self.acoes:
            return "", {}, f"acao desconhecida: {acao!r}. Use uma de: {', '.join(self.acoes)}"
        limpo: dict = {}
        for nome, esq in self.parametros.items():
            v = args.get(nome)
            tipos = esq.get("type")
            tipos = tipos if isinstance(tipos, list) else [tipos]
            if v is None:
                limpo[nome] = None
                continue
            if "string" in tipos and not isinstance(v, str):
                v = str(v)
            if "integer" in tipos and isinstance(v, (float, str)):
                try:
                    v = int(float(v))
                except (TypeError, ValueError):
                    return acao, {}, f"campo {nome}: esperava numero inteiro"
            if "number" in tipos and isinstance(v, str):
                try:
                    v = float(v.replace(",", "."))
                except ValueError:
                    return acao, {}, f"campo {nome}: esperava numero"
            if "array" in tipos:
                if not isinstance(v, list):
                    v = [v]
                v = [str(x) for x in v if str(x).strip()] if esq.get("items", {}).get("type") == "string" else v
            if "boolean" in tipos and not isinstance(v, bool):
                v = str(v).lower() in ("true", "1", "sim")
            if esq.get("enum") and v not in esq["enum"]:
                return acao, {}, f"campo {nome}: valor {v!r} fora das opcoes"
            if isinstance(v, str):
                v = v.strip()
                if v == "":
                    v = None
            limpo[nome] = v
        return acao, limpo, ""


class Registro:
    def __init__(self) -> None:
        self._f: dict[str, Ferramenta] = {}

    def registrar(self, f: Ferramenta) -> Ferramenta:
        if f.nome in self._f:
            raise ValueError(f"ferramenta repetida: {f.nome}")
        self._f[f.nome] = f
        return f

    def pegar(self, nome: str) -> Ferramenta | None:
        return self._f.get(nome)

    def todas(self) -> list[Ferramenta]:
        return list(self._f.values())

    def esquemas(self, excluir: set[str] | None = None) -> list[dict]:
        return [f.esquema() for f in self._f.values() if not excluir or f.nome not in excluir]
