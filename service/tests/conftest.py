"""Base dos testes: banco Postgres real (com as migracoes aplicadas), provedor e canal em memoria. Sem rede.

O banco vem de LUNA_TEST_DB_APP / LUNA_TEST_DB_SCHED (ver service/README.md). Cada teste cria os seus usuarios.
"""
from __future__ import annotations

import itertools
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest
import pytest_asyncio

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from luna.busca import BuscaFalsa  # noqa: E402
from luna.canais.memoria import CanalMemoria  # noqa: E402
from luna.config import Config  # noqa: E402
from luna.db import Banco  # noqa: E402
from luna.estado import EstadoMemoria  # noqa: E402
from luna.ferramentas import montar_registro  # noqa: E402
from luna.google.base import GoogleFalso  # noqa: E402
from luna.nucleo import Nucleo  # noqa: E402
from luna.provedor.falso import ProvedorRoteiro  # noqa: E402

DB_APP = os.environ.get("LUNA_TEST_DB_APP", "postgresql://luna_app@/AgenteTelegram?host=/tmp&port=55432")
DB_SCHED = os.environ.get("LUNA_TEST_DB_SCHED", "postgresql://luna_sched@/AgenteTelegram?host=/tmp&port=55432")

_tg = itertools.count(int(datetime.now().timestamp()) % 100000 * 10000 + 9_000_000_000)


@pytest_asyncio.fixture
async def banco():
    b = Banco(DB_APP, DB_SCHED)
    await b.abrir()
    yield b
    await b.fechar()


@pytest_asyncio.fixture
async def nucleo(banco):
    cfg = Config(db_app=DB_APP, db_sched=DB_SCHED, exige_convite=False)
    n = Nucleo(cfg=cfg, banco=banco, provedor=ProvedorRoteiro(), canal=CanalMemoria(), registro=montar_registro(),
               estado=EstadoMemoria(), google=GoogleFalso(), busca=BuscaFalsa())
    yield n


async def criar_usuario(nucleo, nome="Teste", papel="cliente", google=False, saude=True, politica=True, onboarding="done"):
    """Cria um usuario pronto para usar (aceites dados, cadastro concluido). Devolve o Usuario."""
    tg = next(_tg)
    async with nucleo.banco.servico() as cx:
        uid = await cx.valor(
            "INSERT INTO agente.users (telegram_id, name, onboarding_step, onboarded_at, papel, calendar_key) "
            "VALUES (%s, %s, %s, now(), %s, %s) RETURNING id", tg, nome, onboarding, papel, "oauth" if google else None)
        await cx.exec("INSERT INTO agente.user_channels (user_id, canal, id_externo) VALUES (%s, 'memoria', %s), (%s, 'telegram', %s)",
                      uid, str(tg), uid, str(tg))
        if politica:
            await cx.exec("INSERT INTO agente.user_consents (user_id, tipo, versao) VALUES (%s, 'politica', '1')", uid)
        if saude:
            await cx.exec("INSERT INTO agente.user_consents (user_id, tipo, versao) VALUES (%s, 'saude', '1')", uid)
    if google:
        nucleo.google.conectar(uid)
    u = await nucleo.usuario(uid)
    u.tg = str(tg)  # type: ignore[attr-defined]
    return u


@pytest_asyncio.fixture
async def usuario(nucleo):
    return await criar_usuario(nucleo)


@pytest_asyncio.fixture
async def dono(nucleo):
    return await criar_usuario(nucleo, nome="Dono", papel="dono", google=True)
