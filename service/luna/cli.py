"""Uso local, na linha de comando, sem Telegram.

  python -m luna.cli                 conversa interativa (canal em memoria)
  python -m luna.cli --demo          roda um roteiro de demonstracao e sai
  python -m luna.cli --resumo        mostra o resumo da manha (com o bloco "Atencao")
  python -m luna.cli --revisao       roda a revisao da semana

Na conversa: digite a mensagem; "#2" clica no botao 2 da ultima resposta; "/sair" encerra.
Sem LUNA_OPENAI_API_KEY usa o provedor local de regras (frases simples). O Google e simulado em memoria.
"""
from __future__ import annotations

import argparse
import asyncio
import itertools
import logging
import sys
from datetime import timedelta

from .agendador import Agendador
from .app import Luna
from .config import Config
from .fabrica import montar
from .canais.memoria import CanalMemoria
from .google.base import GoogleFalso
from .tipos import Mensagem, Saida

ID_LOCAL = "900000001"
_seq = itertools.count(1)


async def preparar(n) -> int:
    """Cria (uma vez) o usuario local, ja com aceites, como dono, e uma agenda simulada com alguns compromissos."""
    async with n.banco.servico() as cx:
        uid = await cx.valor("SELECT user_id FROM agente.user_channels WHERE canal = 'memoria' AND id_externo = %s", ID_LOCAL)
        if not uid:
            uid = await cx.valor("INSERT INTO agente.users (telegram_id, name, onboarding_step, onboarded_at, papel, calendar_key) "
                                 "VALUES (%s, 'Você', 'done', now(), 'dono', 'oauth') RETURNING id", int(ID_LOCAL))
            await cx.exec("INSERT INTO agente.user_channels (user_id, canal, id_externo) VALUES (%s, 'memoria', %s)", uid, ID_LOCAL)
            for tipo in ("politica", "saude"):
                await cx.exec("INSERT INTO agente.user_consents (user_id, tipo, versao) VALUES (%s, %s, 'local')", uid, tipo)
        await cx.exec("UPDATE agente.users SET calendar_key = 'oauth' WHERE id = %s", uid)
    if isinstance(n.google, GoogleFalso):
        n.google.conectar(uid)
        u = await n.usuario(uid)
        base = n.agora().astimezone(u.tz).replace(hour=0, minute=0, second=0, microsecond=0)
        sexta = base + timedelta(days=(4 - base.weekday()) % 7 or 7)
        iso = lambda d, h, m=0: d.replace(hour=h, minute=m).isoformat()
        n.google.por_evento(uid, "Reunião com cliente", iso(base + timedelta(days=1), 10), iso(base + timedelta(days=1), 11))
        n.google.por_evento(uid, "Dentista", iso(base + timedelta(days=1), 10, 30), iso(base + timedelta(days=1), 11, 30))
        n.google.por_evento(uid, "Jantar com a família", iso(sexta, 20), iso(sexta, 22), location="Restaurante")
    return uid


def mostrar(saidas: list[Saida]) -> list[str]:
    acoes: list[str] = []
    for s in saidas:
        if s.texto:
            print("\nLuna> " + s.texto.replace("\n", "\n      "))
        if s.arquivo:
            print(f"      [arquivo reenviado: {s.arquivo.nome or s.arquivo.file_id}]")
        if s.anexo:
            print(f"      [arquivo gerado: {s.anexo[0]}, {len(s.anexo[1])} bytes]")
        for linha in s.botoes:
            for b in linha:
                acoes.append(b.acao_id)
                print(f"      [#{len(acoes)} {b.rotulo}]")
    return acoes


async def enviar(luna: Luna, texto: str, acoes: list[str]) -> list[str]:
    base = dict(canal="memoria", id_externo=ID_LOCAL, chat_id=ID_LOCAL, update_id=f"cli{next(_seq)}")
    if texto.startswith("#") and texto[1:].isdigit() and 0 < int(texto[1:]) <= len(acoes):
        m = Mensagem(tipo="botao", acao_id=acoes[int(texto[1:]) - 1], **base)
    else:
        m = Mensagem(tipo="comando" if texto.startswith("/") else "texto", texto=texto, **base)
    return mostrar(await luna.processar(m))


DEMO = ["gastei 42 no mercado", "quero gastar no máximo 3000", "#1", "me lembra amanhã às 9h de ligar pro contador",
        "lista de mercado: arroz, café", "nunca marque nada antes das 9h", "posso aceitar o jantar de sexta?", "/custo"]


async def principal(args) -> None:
    logging.basicConfig(level=logging.WARNING)
    cfg = Config.do_ambiente()
    n = montar(cfg, canal=CanalMemoria())
    await n.banco.abrir()
    try:
        uid = await preparar(n)
        luna = Luna(n)
        print(f"Luna local · provedor: {n.provedor.nome} · usuario {uid} · banco: {cfg.db_app.split('@')[-1]}")
        if args.resumo or args.revisao:
            ag = Agendador(n)
            u = await n.usuario(uid)
            if args.resumo:
                mostrar(await ag.montar_resumo({"user_id": uid, "name": u.como_chamar, "timezone": u.fuso, "kind": "morning"}))
            else:
                mostrar(await ag.revisao(uid))
            return
        acoes: list[str] = []
        if args.demo:
            for t in DEMO:
                print(f"\nVocê> {t}")
                acoes = await enviar(luna, t, acoes)
            return
        print('Digite a mensagem ("#2" clica no botão 2; "/sair" encerra).')
        while True:
            try:
                t = (await asyncio.to_thread(input, "\nVocê> ")).strip()
            except (EOFError, KeyboardInterrupt):
                break
            if t in ("/sair", "/exit", "/quit"):
                break
            if t:
                acoes = await enviar(luna, t, acoes)
    finally:
        await n.banco.fechar()


def main() -> None:
    p = argparse.ArgumentParser(description="Luna Assessor em modo local")
    p.add_argument("--demo", action="store_true")
    p.add_argument("--resumo", action="store_true")
    p.add_argument("--revisao", action="store_true")
    asyncio.run(principal(p.parse_args()))


if __name__ == "__main__":
    main()
