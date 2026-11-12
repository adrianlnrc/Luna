"""Ferramenta listas_notas: invoucro de agente.f_lists e agente.f_notes."""
from __future__ import annotations

from ..tipos import Resultado
from .base import ALTERA, CONSULTA, CRIA, Acao, Ferramenta, L, S
from .util import do_banco

LISTA = {"lista_ver": "show", "listas": "lists", "lista_criar": "create", "lista_adicionar": "add", "lista_marcar": "check",
         "lista_desmarcar": "uncheck", "lista_tirar_item": "remove", "lista_limpar": "clear", "lista_apagar": "delete"}
NOTA = {"nota_buscar": "search", "notas": "list", "nota_guardar": "save", "nota_apagar": "delete"}


async def _executar(ctx, acao: str, a: dict) -> Resultado:
    async with ctx.cx() as cx:
        if acao in LISTA:
            return do_banco(await cx.fn("f_lists", ctx.uid, {
                "list_action": LISTA[acao], "list_name": a.get("lista") or "", "list_items": a.get("itens") or [], "text": ctx.texto}))
        return do_banco(await cx.fn("f_notes", ctx.uid, {
            "note_action": NOTA[acao], "note_text": a.get("texto") or "", "note_query": a.get("busca") or "", "text": ctx.texto}))


def _ri(titulo: str):
    return lambda a: f"{titulo} {a.get('lista') or ''}".strip() + (": " + ", ".join(a.get("itens") or []) if a.get("itens") else "")


FERRAMENTA = Ferramenta(
    nome="listas_notas",
    descricao="Listas (mercado, compras, afazeres simples) e notas de texto livre (ideias, anotações).",
    acoes={
        "lista_ver": Acao("lista_ver", CONSULTA, "mostra uma lista"),
        "listas": Acao("listas", CONSULTA, "quais listas existem"),
        "nota_buscar": Acao("nota_buscar", CONSULTA, "procura nas notas"),
        "notas": Acao("notas", CONSULTA, "lista as notas"),
        "lista_criar": Acao("lista_criar", CRIA, "cria lista", resumo=_ri("Criar a lista")),
        "lista_adicionar": Acao("lista_adicionar", CRIA, "põe itens numa lista (cria a lista se não existir)", resumo=_ri("Pôr na lista")),
        "lista_marcar": Acao("lista_marcar", CRIA, "marca itens como feitos/comprados", resumo=_ri("Marcar na lista")),
        "lista_desmarcar": Acao("lista_desmarcar", CRIA, "desmarca itens", resumo=_ri("Desmarcar na lista")),
        "nota_guardar": Acao("nota_guardar", CRIA, "guarda uma nota", resumo=lambda a: f"Guardar a nota: {a.get('texto')}"),
        "lista_tirar_item": Acao("lista_tirar_item", ALTERA, "tira itens de uma lista", resumo=_ri("Tirar da lista")),
        "lista_limpar": Acao("lista_limpar", ALTERA, "esvazia a lista", nativa=True),
        "lista_apagar": Acao("lista_apagar", ALTERA, "apaga a lista", nativa=True),
        "nota_apagar": Acao("nota_apagar", ALTERA, "apaga uma nota", nativa=True),
    },
    parametros={
        "lista": S("string", "nome da lista"),
        "itens": L("string", "itens"),
        "texto": S("string", "texto da nota"),
        "busca": S("string", "o que procurar nas notas"),
    },
    executar=_executar,
)
