"""Ferramenta contatos_lugares: pessoas, grupos e lugares salvos. Invoucro de agente.f_contacts."""
from __future__ import annotations

from ..tipos import Resultado
from .base import ALTERA, CONSULTA, CRIA, Acao, Ferramenta, L, S
from .util import do_banco

MAPA = {"contatos": "list", "grupos": "group_list", "lugares": "place_list", "contato_salvar": "save", "grupo_salvar": "group_save",
        "lugar_salvar": "place_save", "contato_apagar": "remove", "grupo_apagar": "group_remove", "lugar_apagar": "place_remove"}


async def _executar(ctx, acao: str, a: dict) -> Resultado:
    nome = a.get("nome") or ""
    async with ctx.cx() as cx:
        return do_banco(await cx.fn("f_contacts", ctx.uid, {
            "contact_action": MAPA[acao], "contact_name": nome, "contact_email": a.get("email") or "",
            "place_address": a.get("endereco") or "", "group_name": a.get("grupo") or (nome if "grupo" in acao else ""),
            "group_members": a.get("membros") or [], "text": ctx.texto}))


FERRAMENTA = Ferramenta(
    nome="contatos_lugares",
    descricao="Pessoas (nome e e-mail), grupos de pessoas e lugares com endereço. Nunca invente e-mail: sem cadastro, peça ao usuário.",
    acoes={
        "contatos": Acao("contatos", CONSULTA, "lista contatos"),
        "grupos": Acao("grupos", CONSULTA, "lista grupos e membros"),
        "lugares": Acao("lugares", CONSULTA, "lista lugares salvos"),
        "contato_salvar": Acao("contato_salvar", CRIA, "salva pessoa com e-mail", resumo=lambda a: f"Salvar o contato {a.get('nome')} ({a.get('email')})"),
        "grupo_salvar": Acao("grupo_salvar", CRIA, "cria ou atualiza grupo com membros",
                             resumo=lambda a: f"Salvar o grupo {a.get('grupo') or a.get('nome')}: {', '.join(a.get('membros') or [])}"),
        "lugar_salvar": Acao("lugar_salvar", CRIA, "salva lugar com endereço", resumo=lambda a: f"Salvar o lugar {a.get('nome')}: {a.get('endereco')}"),
        "contato_apagar": Acao("contato_apagar", ALTERA, "tira um contato", nativa=True),
        "grupo_apagar": Acao("grupo_apagar", ALTERA, "apaga um grupo", nativa=True),
        "lugar_apagar": Acao("lugar_apagar", ALTERA, "tira um lugar", resumo=lambda a: f"Tirar o lugar {a.get('nome')}"),
    },
    parametros={
        "nome": S("string", "nome da pessoa ou do lugar"),
        "email": S("string"),
        "endereco": S("string"),
        "grupo": S("string", "nome do grupo"),
        "membros": L("string", "nomes dos membros do grupo"),
    },
    executar=_executar,
)
