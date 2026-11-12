"""Ferramenta projetos: invoucro de agente.f_projects."""
from __future__ import annotations

from ..tipos import Resultado
from .base import ALTERA, CONSULTA, CRIA, Acao, Ferramenta, L, S
from .util import data_ok, do_banco

MAPA = {"ver": "show", "listar": "list", "atrasadas": "overdue", "criar": "create", "adicionar_tarefas": "add_tasks",
        "sugerir_tarefas": "add_tasks", "concluir_tarefa": "complete_task", "reabrir_tarefa": "reopen_task",
        "marcar_urgente": "set_urgent", "definir_prazo": "set_due", "renomear": "rename", "apagar": "delete"}


async def _executar(ctx, acao: str, a: dict) -> Resultado:
    async with ctx.cx() as cx:
        return do_banco(await cx.fn("f_projects", ctx.uid, {
            "action": MAPA[acao], "name": a.get("projeto") or "", "title": a.get("novo_nome") or "", "task": a.get("tarefa") or "",
            "tasks": a.get("tarefas") or [], "due": a["prazo"] if data_ok(a.get("prazo")) else "", "urgent": a.get("urgente")}),
            "Não consegui mexer nos projetos agora. Tente de novo.")


def _r(titulo: str):
    def f(a: dict) -> str:
        return (f"{titulo} {a.get('projeto') or ''}".strip()
                + (f": {a.get('tarefa')}" if a.get("tarefa") else "")
                + (": " + ", ".join(a.get("tarefas") or []) if a.get("tarefas") else "")
                + (f" (prazo {a.get('prazo')})" if a.get("prazo") else ""))
    return f


FERRAMENTA = Ferramenta(
    nome="projetos",
    descricao="Projetos com prazo e tarefas (progresso, atrasadas, urgente).",
    acoes={
        "ver": Acao("ver", CONSULTA, "mostra um projeto e suas tarefas"),
        "listar": Acao("listar", CONSULTA, "lista os projetos"),
        "atrasadas": Acao("atrasadas", CONSULTA, "tarefas atrasadas"),
        "criar": Acao("criar", CRIA, "cria projeto (com prazo e as tarefas que o usuário listou)", resumo=_r("Criar o projeto")),
        "adicionar_tarefas": Acao("adicionar_tarefas", CRIA, "inclui tarefas que o USUÁRIO listou", resumo=_r("Incluir tarefas em")),
        "concluir_tarefa": Acao("concluir_tarefa", CRIA, "marca tarefa como feita", resumo=_r("Concluir tarefa de")),
        "sugerir_tarefas": Acao("sugerir_tarefas", ALTERA, "tarefas que VOCÊ sugeriu para o projeto (vira proposta)",
                                resumo=_r("Incluir as tarefas sugeridas em")),
        "reabrir_tarefa": Acao("reabrir_tarefa", ALTERA, "reabre uma tarefa", resumo=_r("Reabrir tarefa de")),
        "marcar_urgente": Acao("marcar_urgente", ALTERA, "marca ou desmarca tarefa como urgente", resumo=_r("Marcar urgência em")),
        "definir_prazo": Acao("definir_prazo", ALTERA, "muda o prazo do projeto ou de uma tarefa", resumo=_r("Mudar o prazo de")),
        "renomear": Acao("renomear", ALTERA, "renomeia o projeto", resumo=lambda a: f"Renomear {a.get('projeto')} para {a.get('novo_nome')}"),
        "apagar": Acao("apagar", ALTERA, "apaga o projeto", nativa=True),
    },
    parametros={
        "projeto": S("string", "nome do projeto"),
        "tarefa": S("string", "nome de uma tarefa"),
        "tarefas": L("string", "lista de tarefas"),
        "prazo": S("string", "AAAA-MM-DD"),
        "urgente": S("boolean"),
        "novo_nome": S("string"),
    },
    executar=_executar,
)
