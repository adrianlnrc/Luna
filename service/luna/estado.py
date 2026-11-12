"""Estado curto (deduplicacao, historico, fila, pendencias de conversa). Memoria para testes, Redis em producao."""
from __future__ import annotations

import asyncio
import json
import time
from typing import Any, Protocol


class Estado(Protocol):
    async def pegar(self, chave: str) -> Any: ...
    async def por(self, chave: str, valor: Any, ttl: int | None = None) -> None: ...
    async def apagar(self, chave: str) -> None: ...
    async def por_se_novo(self, chave: str, ttl: int) -> bool: ...
    async def enfileirar(self, fila: str, item: Any) -> None: ...
    async def desenfileirar(self, fila: str, espera: float = 1.0) -> Any: ...
    async def confirmar(self, fila: str, item: Any) -> None: ...
    async def recuperar(self, fila: str) -> int: ...


class EstadoMemoria:
    def __init__(self) -> None:
        self._kv: dict[str, tuple[Any, float | None]] = {}
        self._filas: dict[str, asyncio.Queue] = {}
        self._processando: dict[str, list] = {}

    def _vivo(self, chave: str) -> bool:
        v = self._kv.get(chave)
        if v is None:
            return False
        if v[1] is not None and v[1] < time.monotonic():
            del self._kv[chave]
            return False
        return True

    async def pegar(self, chave: str) -> Any:
        return self._kv[chave][0] if self._vivo(chave) else None

    async def por(self, chave: str, valor: Any, ttl: int | None = None) -> None:
        self._kv[chave] = (valor, time.monotonic() + ttl if ttl else None)

    async def apagar(self, chave: str) -> None:
        self._kv.pop(chave, None)

    async def por_se_novo(self, chave: str, ttl: int) -> bool:
        if self._vivo(chave):
            return False
        await self.por(chave, 1, ttl)
        return True

    def _fila(self, fila: str) -> asyncio.Queue:
        return self._filas.setdefault(fila, asyncio.Queue())

    async def enfileirar(self, fila: str, item: Any) -> None:
        await self._fila(fila).put(item)

    async def desenfileirar(self, fila: str, espera: float = 1.0) -> Any:
        try:
            item = await asyncio.wait_for(self._fila(fila).get(), espera)
        except asyncio.TimeoutError:
            return None
        self._processando.setdefault(fila, []).append(item)
        return item

    async def confirmar(self, fila: str, item: Any) -> None:
        try:
            self._processando.get(fila, []).remove(item)
        except ValueError:
            pass

    async def recuperar(self, fila: str) -> int:
        pend = self._processando.pop(fila, [])
        for it in pend:
            await self._fila(fila).put(it)
        return len(pend)


class EstadoRedis:
    """Mesma interface sobre o Redis. A fila usa lista + lista de processamento: reinicio nao perde mensagem."""

    def __init__(self, url: str, prefixo: str = "luna:") -> None:
        import redis.asyncio as redis
        self._r = redis.from_url(url, decode_responses=True)
        self._p = prefixo

    async def pegar(self, chave: str) -> Any:
        v = await self._r.get(self._p + chave)
        return json.loads(v) if v is not None else None

    async def por(self, chave: str, valor: Any, ttl: int | None = None) -> None:
        await self._r.set(self._p + chave, json.dumps(valor, ensure_ascii=False), ex=ttl)

    async def apagar(self, chave: str) -> None:
        await self._r.delete(self._p + chave)

    async def por_se_novo(self, chave: str, ttl: int) -> bool:
        return bool(await self._r.set(self._p + chave, "1", ex=ttl, nx=True))

    async def enfileirar(self, fila: str, item: Any) -> None:
        await self._r.lpush(self._p + "fila:" + fila, json.dumps(item, ensure_ascii=False))

    async def desenfileirar(self, fila: str, espera: float = 1.0) -> Any:
        v = await self._r.brpoplpush(self._p + "fila:" + fila, self._p + "proc:" + fila, timeout=max(int(espera), 1))
        return json.loads(v) if v is not None else None

    async def confirmar(self, fila: str, item: Any) -> None:
        await self._r.lrem(self._p + "proc:" + fila, 1, json.dumps(item, ensure_ascii=False))

    async def recuperar(self, fila: str) -> int:
        n = 0
        while await self._r.rpoplpush(self._p + "proc:" + fila, self._p + "fila:" + fila) is not None:
            n += 1
        return n
