"""Acesso ao Postgres. Toda consulta em nome de um usuario roda numa transacao com app.user_id definido (RLS)."""
from __future__ import annotations

from contextlib import asynccontextmanager
from typing import Any, AsyncIterator

import psycopg
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb
from psycopg_pool import AsyncConnectionPool


class Cx:
    """Conexao dentro de uma transacao."""

    def __init__(self, conn: psycopg.AsyncConnection):
        self.conn = conn

    async def valor(self, sql: str, *params: Any) -> Any:
        cur = await self.conn.execute(sql, params)
        row = await cur.fetchone()
        if row is None:
            return None
        return next(iter(row.values()))

    async def linha(self, sql: str, *params: Any) -> dict | None:
        cur = await self.conn.execute(sql, params)
        return await cur.fetchone()

    async def linhas(self, sql: str, *params: Any) -> list[dict]:
        cur = await self.conn.execute(sql, params)
        return await cur.fetchall()

    async def exec(self, sql: str, *params: Any) -> None:
        await self.conn.execute(sql, params)

    async def fn(self, nome: str, *params: Any) -> Any:
        """SELECT agente.<nome>(...). dict/list viram jsonb."""
        ps = [Jsonb(p) if isinstance(p, (dict, list)) else p for p in params]
        marc = ", ".join(["%s"] * len(ps))
        return await self.valor(f"SELECT agente.{nome}({marc}) AS r", *ps)


class Banco:
    def __init__(self, dsn_app: str, dsn_sched: str, tamanho: int = 5):
        kw = {"row_factory": dict_row, "autocommit": False}
        self._app = AsyncConnectionPool(dsn_app, min_size=1, max_size=tamanho, kwargs=kw, open=False)
        self._sched = AsyncConnectionPool(dsn_sched, min_size=1, max_size=3, kwargs=kw, open=False)

    async def abrir(self) -> None:
        await self._app.open()
        await self._sched.open()

    async def fechar(self) -> None:
        await self._app.close()
        await self._sched.close()

    @asynccontextmanager
    async def usuario(self, user_id: int) -> AsyncIterator[Cx]:
        """Transacao em nome de um usuario. O RLS so deixa passar as linhas dele."""
        async with self._app.connection() as conn:
            async with conn.transaction():
                await conn.execute("SELECT set_config('app.user_id', %s, true)", (str(int(user_id)),))
                yield Cx(conn)

    @asynccontextmanager
    async def anonimo(self) -> AsyncIterator[Cx]:
        """Papel do aplicativo sem usuario: so alcanca as portas de entrada (f_channel_user, f_signup)."""
        async with self._app.connection() as conn:
            async with conn.transaction():
                await conn.execute("SELECT set_config('app.user_id', '', true)")
                yield Cx(conn)

    @asynccontextmanager
    async def servico(self) -> AsyncIterator[Cx]:
        """Papel do agendador: enxerga todos os usuarios. Usar so em tarefas de disparo."""
        async with self._sched.connection() as conn:
            async with conn.transaction():
                yield Cx(conn)
