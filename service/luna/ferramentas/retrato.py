"""Ferramenta retrato (PRD RF-08): visao unica de todas as areas + compromissos do Google."""
from __future__ import annotations

from datetime import timedelta

from ..google.base import ErroGoogle
from ..tipos import Resultado
from .base import CONSULTA, Acao, Ferramenta, S
from .util import rotulo


async def eventos_txt(ctx, dias: int) -> tuple[str, list[dict]]:
    """Compromissos dos proximos dias, em texto. Sem Google conectado devolve um aviso curto."""
    if not ctx.usuario.google:
        return "AGENDA: Google não conectado (sem compromissos para cruzar).", []
    ini = ctx.agora.replace(hour=0, minute=0, second=0, microsecond=0)
    try:
        evs = await ctx.nucleo.google.eventos(ctx.uid, ini, ini + timedelta(days=dias + 1))
    except ErroGoogle as e:
        return ("AGENDA: desconectada, peça para reconectar em /config." if e.desconectado
                else "AGENDA: não consegui ler agora."), []
    if not evs:
        return f"AGENDA: nenhum compromisso nos próximos {dias} dias.", []
    from datetime import datetime
    linhas = []
    for e in evs[:40]:
        ini_e = datetime.fromisoformat(e["start"].replace("Z", "+00:00"))
        fim_e = datetime.fromisoformat(e["end"].replace("Z", "+00:00")).astimezone(ctx.usuario.tz)
        linhas.append(f"{rotulo(ctx, ini_e)}–{fim_e.strftime('%H:%M')} {e['title']}"
                      + (f" ({e['location']})" if e.get("location") else ""))
    return "AGENDA: " + "; ".join(linhas) + ".", evs


async def _executar(ctx, acao: str, args: dict) -> Resultado:
    dias = max(1, min(int(args.get("dias") or 14), 60))
    async with ctx.cx() as cx:
        snap = await cx.fn("f_assessor_snapshot", ctx.uid, dias)
    if not snap or not snap.get("ok"):
        return Resultado(ok=False, erro="não consegui montar o retrato")
    ag, evs = await eventos_txt(ctx, dias)
    snap["agenda"] = evs
    return Resultado(texto=snap["text"] + "\n" + ag, dados=snap)


FERRAMENTA = Ferramenta(
    nome="retrato",
    descricao="Visão única do usuário para decidir e planejar: dinheiro (limite, orçamentos, contas, cartões, metas), "
              "prazos de projetos, estoque acabando, documentos vencendo, lembretes e compromissos. "
              "Use em perguntas de decisão ou que cruzem áreas.",
    acoes={"ver": Acao("ver", CONSULTA, "retrato dos próximos dias")},
    parametros={"dias": S("integer", "horizonte em dias (padrão 14)")},
    executar=_executar,
)
