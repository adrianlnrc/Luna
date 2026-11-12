"""Operacoes externas que o banco pede (Google Agenda e Tarefas) e acoes que juntam banco e Google.

As funcoes SQL de agenda nao falam com o Google: devolvem um pedido (`cal`, `cals`, `imp`) e esperam o resultado.
No n8n quem fazia isso eram os sub-workflows de agenda por pessoa; aqui e este modulo, com o OAuth do usuario.
"""
from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from .google.base import ErroGoogle
from .teclados import botoes
from .tipos import Resultado, Saida, Usuario

if TYPE_CHECKING:
    from .nucleo import Nucleo


def _dt(s: str) -> datetime:
    return datetime.fromisoformat(str(s).replace("Z", "+00:00"))


async def conflitos(nucleo: "Nucleo", uid: int, inicio: str, fim: str) -> list[dict]:
    evs = await nucleo.google.eventos(uid, _dt(inicio), _dt(fim))
    return [{"title": e["title"], "start": e["start"], "end": e["end"]} for e in evs
            if not e.get("all_day") and e.get("self_status") != "declined"]


async def executar_cal(nucleo: "Nucleo", uid: int, cal: dict) -> dict:
    """Executa um pedido `cal` (op: create | update | delete | respond) e devolve o resultado que o banco espera."""
    g = nucleo.google
    op = cal.get("op")
    avisar = cal.get("send_updates") == "all"
    try:
        if op == "create":
            if str(cal.get("force")).lower() != "true":
                conf = await conflitos(nucleo, uid, cal["start"], cal["end"])
                if conf:
                    return {"ok": True, "conflict": True, "conflicts": conf}
            r = await g.criar_evento(uid, cal)
            return {**r, "conflict": False}
        if op == "update":
            return await g.atualizar_evento(uid, cal["event_id"], cal["start"], cal["end"], avisar)
        if op == "delete":
            return await g.apagar_evento(uid, cal["event_id"], avisar)
        if op == "respond":
            return await g.responder_convite(uid, cal["event_id"], cal.get("response") or "accepted")
    except ErroGoogle as e:
        return {"ok": False, "error": "agenda desconectada: reconecte em /config" if e.desconectado else str(e)[:140]}
    except Exception as e:
        return {"ok": False, "error": f"{type(e).__name__}"}
    return {"ok": False, "error": "operacao desconhecida"}


async def concluir_cal(nucleo: "Nucleo", usuario: Usuario, cal: dict) -> Resultado:
    """Pedido `cal` vindo de um botao: executa no Google e fecha a pendencia no banco (f_agenda_done)."""
    res = await executar_cal(nucleo, usuario.id, cal)
    async with nucleo.banco.usuario(usuario.id) as cx:
        r = await cx.fn("f_agenda_done", usuario.id, int(cal["pid"]), res)
    r = r or {}
    return Resultado(texto=r.get("text") or "Ok.", kb=r.get("kb") or "none", rid=r.get("rid") or 0, dados=r)


async def desfazer_lote(nucleo: "Nucleo", usuario: Usuario, lote: int) -> Resultado:
    """"Desfazer tudo": o banco desfaz o que e dele e devolve os eventos do Google a apagar."""
    async with nucleo.banco.usuario(usuario.id) as cx:
        r = await cx.fn("f_batch_undo", usuario.id, lote) or {}
    texto = r.get("text") or "Desfeito."
    falhas = []
    for c in r.get("cals") or []:
        res = await executar_cal(nucleo, usuario.id, {**c, "op": "delete"})
        if not res.get("ok"):
            falhas.append("- " + str(c.get("title") or "compromisso")[:60])
    if falhas:
        texto += "\n\nNão consegui apagar estes compromissos do Google (apague na agenda se quiser):\n" + "\n".join(falhas)
    return Resultado(texto=texto, dados=r)


async def concluir_importacao(nucleo: "Nucleo", usuario: Usuario, imp: dict) -> Resultado:
    """Importacao de agenda de papel confirmada: cria compromissos e tarefas no Google e fecha o rascunho."""
    g = nucleo.google
    res = {"events_ok": 0, "events_fail": 0, "tasks_ok": 0, "tasks_fail": 0, "errors": []}
    for e in imp.get("events") or []:
        try:
            r = await g.criar_evento(usuario.id, {"summary": e.get("summary"), "start": e["start"], "end": e["end"],
                                                  "no_reminders": e.get("no_reminders")})
            res["events_ok" if r.get("ok") else "events_fail"] += 1
        except Exception as ex:
            res["events_fail"] += 1
            if len(res["errors"]) < 3:
                res["errors"].append(str(ex)[:80])
    for t in imp.get("tasks") or []:
        try:
            r = await g.criar_tarefa(usuario.id, t.get("title") or "", t.get("due"))
            res["tasks_ok" if r.get("ok") else "tasks_fail"] += 1
        except Exception as ex:
            res["tasks_fail"] += 1
            if len(res["errors"]) < 3:
                res["errors"].append(str(ex)[:80])
    async with nucleo.banco.usuario(usuario.id) as cx:
        r = await cx.fn("f_agimp_done", usuario.id, int(imp["draft_id"]), res)
    r = r or {}
    return Resultado(texto=r.get("text") or "Ok.", kb=r.get("kb") or "none", rid=r.get("rid") or 0, dados=r)


async def botao_do_banco(nucleo: "Nucleo", usuario: Usuario, dado: str) -> list[Saida]:
    """Clique em botao de teclado do banco: agente.f_callback decide; aqui cumprimos o que ele pedir de externo."""
    if dado.startswith("mu:") and dado[3:].isdigit():
        res = await desfazer_lote(nucleo, usuario, int(dado[3:]))
        return [Saida(res.texto)]
    async with nucleo.banco.usuario(usuario.id) as cx:
        r = await cx.fn("f_callback", usuario.id, dado) or {}
    if r.get("cals"):
        falhas = []
        for c in r["cals"]:
            res = await executar_cal(nucleo, usuario.id, {**c, "op": "delete"})
            if not res.get("ok"):
                falhas.append("- " + str(c.get("title") or "compromisso")[:60])
        t = r.get("text") or "Desfeito."
        if falhas:
            t += "\n\nNão consegui apagar estes compromissos do Google (apague na agenda se quiser):\n" + "\n".join(falhas)
        return [Saida(t)]
    if r.get("imp"):
        res = await concluir_importacao(nucleo, usuario, r["imp"])
        return [Saida(res.texto, botoes(res.kb, res.rid))]
    if r.get("cal"):
        res = await concluir_cal(nucleo, usuario, r["cal"])
        return [Saida(res.texto, botoes(res.kb, res.rid))]
    return [Saida(r.get("text") or "Ok.", botoes(r.get("kb") or "none", r.get("rid") or 0))]
