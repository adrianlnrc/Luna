"""Pesquisa web como ferramenta propria do servico (PRD RF-11), independente do provedor de IA."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

import httpx


@dataclass
class Achado:
    titulo: str
    url: str
    trecho: str


class Busca(Protocol):
    async def buscar(self, consulta: str, n: int = 5) -> list[Achado]: ...


class BuscaFalsa:
    def __init__(self, achados: list[Achado] | None = None) -> None:
        self.achados = achados or []
        self.consultas: list[str] = []
        self.erro: Exception | None = None

    async def buscar(self, consulta: str, n: int = 5) -> list[Achado]:
        self.consultas.append(consulta)
        if self.erro:
            raise self.erro
        return self.achados[:n]


class BuscaHttp:
    """Adaptador para uma API de busca com resposta {results: [{title, url, content}]} (formato da Tavily).
    A escolha do fornecedor e pendencia do PRD (secao 14, item 7): trocar de API e trocar este adaptador."""

    def __init__(self, api_key: str, url: str, cliente: httpx.AsyncClient | None = None):
        self._key, self._url = api_key, url
        self._http = cliente or httpx.AsyncClient(timeout=20.0)

    async def buscar(self, consulta: str, n: int = 5) -> list[Achado]:
        r = await self._http.post(self._url, json={"query": consulta, "max_results": n},
                                  headers={"Authorization": "Bearer " + self._key})
        r.raise_for_status()
        out = []
        for x in (r.json().get("results") or [])[:n]:
            if x.get("url"):
                out.append(Achado(str(x.get("title") or x["url"])[:160], str(x["url"]), str(x.get("content") or "")[:700]))
        return out
