"""Ferramenta tarefas: afazeres no Google Tarefas do usuario."""
from __future__ import annotations

import unicodedata

from ..tipos import Resultado
from .base import ALTERA, CONSULTA, CRIA, Acao, Ferramenta, S
from .util import data_ok

SEM_GOOGLE = "Suas tarefas do Google ainda não estão conectadas. Conecte em /config."


def _n(s: str) -> str:
    s = unicodedata.normalize("NFD", (s or "").lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn").strip()


def _prazo(d: str | None) -> str:
    return f" (prazo {d[8:10]}/{d[5:7]})" if d and len(d) >= 10 else ""


async def _achar(ctx, titulo: str) -> dict | None:
    alvo = _n(titulo)
    cand = [t for t in await ctx.nucleo.google.tarefas(ctx.uid) if alvo and (alvo in _n(t["title"]) or _n(t["title"]) in alvo)]
    return cand[0] if cand else None


async def _executar(ctx, acao: str, a: dict) -> Resultado:
    if not ctx.usuario.google:
        return Resultado(texto=SEM_GOOGLE)
    g = ctx.nucleo.google
    if acao == "listar":
        ts = await g.tarefas(ctx.uid)
        if not ts:
            return Resultado(texto="Você não tem tarefas pendentes.", dados=[])
        return Resultado(texto="Suas tarefas pendentes:\n" + "\n".join(f"- {t['title']}{_prazo(t.get('due'))}" for t in ts), dados=ts)
    if acao == "concluidas":
        ts = [t for t in await g.tarefas(ctx.uid, concluidas=True) if t.get("done")]
        if not ts:
            return Resultado(texto="Nenhuma tarefa concluída recentemente.", dados=[])
        return Resultado(texto=f"Você concluiu {len(ts)} tarefa(s):\n" + "\n".join(f"- {t['title']}" for t in ts[:15]), dados=ts)
    titulo = a.get("titulo") or ""
    if not titulo:
        return Resultado(ok=False, erro="falta o título da tarefa")
    if acao == "criar":
        prazo = a["prazo"] if data_ok(a.get("prazo")) else None
        r = await g.criar_tarefa(ctx.uid, titulo, prazo)
        if not r.get("ok"):
            return Resultado(ok=False, erro=r.get("error") or "o Google recusou")
        if ctx.lote:
            async with ctx.cx() as cx:
                await cx.exec("INSERT INTO agente.recent_actions (user_id, batch_id, kind, ref_text, calendar_key, label) "
                              "VALUES (%s, %s, 'task', %s, 'oauth', %s)", ctx.uid, ctx.lote, r.get("task_id"), f"tarefa {titulo}"[:120])
        return Resultado(texto=f'Anotei na sua lista de tarefas: "{titulo}"{_prazo(prazo)}.', dados=r)
    t = await _achar(ctx, titulo)
    if not t:
        return Resultado(texto=f'Não achei uma tarefa pendente parecida com "{titulo}". Diga "o que tenho nas tarefas?" para ver a lista.')
    if acao == "concluir":
        r = await g.concluir_tarefa(ctx.uid, t["id"])
        return Resultado(ok=bool(r.get("ok")), texto=f"Tarefa concluída: {t['title']}.", erro=r.get("error") or "")
    r = await g.apagar_tarefa(ctx.uid, t["id"])
    return Resultado(ok=bool(r.get("ok")), texto=f"Apaguei a tarefa: {t['title']}.", erro=r.get("error") or "")


FERRAMENTA = Ferramenta(
    nome="tarefas",
    descricao="Afazeres no Google Tarefas (\"anota: ligar pro eletricista\"). Para tarefas de um projeto use `projetos`; "
              "para texto livre use `listas_notas`.",
    google=True,
    acoes={
        "listar": Acao("listar", CONSULTA, "tarefas pendentes"),
        "concluidas": Acao("concluidas", CONSULTA, "tarefas concluídas"),
        "criar": Acao("criar", CRIA, "cria tarefa (com prazo opcional)",
                      resumo=lambda a: f"Criar a tarefa \"{a.get('titulo')}\"" + (f" com prazo {a.get('prazo')}" if a.get("prazo") else "")),
        "concluir": Acao("concluir", CRIA, "marca como feita", resumo=lambda a: f"Concluir a tarefa \"{a.get('titulo')}\""),
        "apagar": Acao("apagar", ALTERA, "apaga a tarefa", resumo=lambda a: f"Apagar a tarefa \"{a.get('titulo')}\""),
    },
    parametros={"titulo": S("string"), "prazo": S("string", "AAAA-MM-DD")},
    executar=_executar,
)
