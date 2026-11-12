"""Acoes pendentes (PRD RF-07): propostas que so executam depois de o usuario confirmar.

Confirmar executa EXATAMENTE os argumentos gravados: o modelo nao e chamado de novo.
"""
from __future__ import annotations

from typing import TYPE_CHECKING

from ..ferramentas.base import Acao, Ferramenta
from ..tipos import Botao, Resultado, Saida, Usuario
from .politica import EstadoExec

if TYPE_CHECKING:
    from ..nucleo import Nucleo
    from .contexto import Ctx


def resumir(f: Ferramenta, acao: Acao, args: dict) -> str:
    """Frase que o usuario le na proposta. Vem dos argumentos gravados, nao do texto do modelo."""
    if acao.resumo:
        try:
            return acao.resumo(args)[:300]
        except Exception:
            pass
    partes = []
    for k, v in args.items():
        if v in (None, "", [], False):
            continue
        partes.append(f"{k}: {', '.join(map(str, v)) if isinstance(v, list) else v}")
    return f"{f.nome} · {acao.nome}" + (" (" + "; ".join(partes) + ")" if partes else "")


async def criar(ctx: "Ctx", f: Ferramenta, acao: Acao, args: dict, origem: str) -> tuple[int, str]:
    resumo = resumir(f, acao, args)
    async with ctx.cx() as cx:
        pid = await cx.valor(
            "INSERT INTO agente.pending_actions (user_id, run_id, ferramenta, acao, args, nivel, origem, resumo) "
            "VALUES (%s, %s, %s, %s, %s::jsonb, %s, %s, %s) RETURNING id",
            ctx.uid, ctx.run_id, f.nome, acao.nome, __import__("json").dumps(args, ensure_ascii=False), acao.nivel, origem, resumo)
    ctx.propostas.append((pid, resumo))
    ctx.est.propostas += 1
    return pid, resumo


def botoes_proposta(pid: int) -> list[list[Botao]]:
    return [[Botao("Confirmar", f"pa:{pid}:ok"), Botao("Cancelar", f"pa:{pid}:no")]]


def botoes_propostas_run(run_id: int) -> list[list[Botao]]:
    return [[Botao("Confirmar tudo", f"pr:{run_id}:ok"), Botao("Cancelar", f"pr:{run_id}:no")]]


async def confirmar(nucleo: "Nucleo", usuario: Usuario, pid: int) -> list[Saida]:
    """Clique em Confirmar. Transicao atomica no banco: clique duplo e proposta vencida nao executam."""
    from .contexto import Ctx
    async with nucleo.banco.usuario(usuario.id) as cx:
        r = await cx.fn("f_pending_claim", usuario.id, pid)
    if not r or not r.get("ok"):
        return [Saida((r or {}).get("text") or "Essa proposta já foi resolvida.")]
    f = nucleo.registro.pegar(r["ferramenta"])
    acao = f.acoes.get(r["acao"]) if f else None
    if not f or not acao:
        async with nucleo.banco.usuario(usuario.id) as cx:
            await cx.fn("f_pending_finish", usuario.id, pid, False, {"erro": "ferramenta inexistente"})
        return [Saida("Não consegui executar essa proposta.")]
    ctx = Ctx(nucleo=nucleo, usuario=usuario, est=EstadoExec(confirmada=True), run_id=r.get("run_id"))
    try:
        res = await f.executar(ctx, acao.nome, r["args"] or {})
    except Exception as e:  # nada de gravacao parcial sem aviso
        res = Resultado(ok=False, erro=f"{type(e).__name__}: {e}"[:200])
    async with nucleo.banco.usuario(usuario.id) as cx:
        await cx.fn("f_pending_finish", usuario.id, pid, res.ok, {"texto": res.texto[:500], "erro": res.erro[:300]})
        if r.get("run_id"):
            await cx.fn("f_run_result", usuario.id, r["run_id"], "acao_confirmada" if res.ok else "erro")
    from ..teclados import botoes as bt
    if not res.ok:
        return [Saida("Não consegui fazer isso: " + (res.erro or "erro") + ". Nada foi alterado.")]
    saidas = [Saida(res.texto or "Feito.", bt(res.kb, res.rid))]
    saidas += ctx.teclados + ctx.extras + res.saidas
    return saidas


async def cancelar(nucleo: "Nucleo", usuario: Usuario, pid: int) -> list[Saida]:
    async with nucleo.banco.usuario(usuario.id) as cx:
        r = await cx.fn("f_pending_cancel", usuario.id, pid)
        if r and r.get("ok") and r.get("run_id"):
            await cx.fn("f_run_result", usuario.id, r["run_id"], "rejeitado")
    return [Saida((r or {}).get("text") or "Ok.")]


async def do_run(nucleo: "Nucleo", usuario: Usuario, run_id: int) -> list[int]:
    async with nucleo.banco.usuario(usuario.id) as cx:
        linhas = await cx.linhas(
            "SELECT id FROM agente.pending_actions WHERE user_id = %s AND run_id = %s AND status = 'pendente' ORDER BY id",
            usuario.id, run_id)
    return [l["id"] for l in linhas]
