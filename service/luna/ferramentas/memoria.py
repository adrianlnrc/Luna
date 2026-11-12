"""Ferramenta memoria (PRD RF-10): fatos, criterios de decisao e interruptores."""
from __future__ import annotations

import re

from ..tipos import Resultado
from .base import ALTERA, CONSULTA, CRIA, Acao, Ferramenta, S

# dado de saude so entra na memoria com pedido explicito do usuario (RF-10)
RE_SAUDE = re.compile(
    r"\b(rem[eé]dio|medicamento|toma|tomo|diagn[oó]stic|doen[cç]a|depress|ansiedade|diabet|hipertens|press[aã]o alta|c[aâ]ncer|"
    r"hiv|gr[aá]vid|gesta|terapia|psiquiatr|psic[oó]log|cirurgia|exame|alergia|antidepress|insulina|sertralina|losartana)", re.I)
RE_PEDIDO = re.compile(r"\b(anota|anote|lembra|lembre|guarda|guarde|memoriza|memorize|registra|registre|salva|salve|nunca|sempre)\b", re.I)


def _pedido_explicito(ctx) -> bool:
    return bool(RE_PEDIDO.search(ctx.texto or ""))


async def _executar(ctx, acao: str, a: dict) -> Resultado:
    uid = ctx.uid
    texto = a.get("texto") or ""
    async with ctx.cx() as cx:
        if acao == "listar":
            r = await cx.fn("f_mem_list", uid, a.get("filtro") or "")
            return Resultado(texto=(r or {}).get("text") or "Nada anotado.", dados=r)
        if acao == "esquecer":
            r = await cx.fn("f_mem_forget", uid, a.get("referencia") or texto or "")
            return Resultado(ok=True, texto=(r or {}).get("text") or "Não achei o que esquecer.", dados=r)
        if acao in ("ligar", "desligar"):
            r = await cx.fn("f_mem_set_switch", uid, a.get("interruptor") or "memoria", acao == "ligar")
            if not (r or {}).get("ok"):
                return Resultado(ok=False, erro="interruptor inválido: use memoria, sugestoes ou oferta")
            return Resultado(texto=r.get("text") or "Feito.", dados=r)
        if not texto:
            return Resultado(ok=False, erro="falta o texto a anotar")
        if RE_SAUDE.search(texto) and not _pedido_explicito(ctx) and not ctx.est.confirmada:
            return Resultado(ok=False, erro="isso parece dado de saúde e o usuário não pediu para anotar. Não anote; "
                                            "se for útil guardar, pergunte antes.")
        if acao == "criterio":
            r = await cx.fn("f_crit_add", uid, texto, "pedido" if ctx.est.confirmada is False else "confirmado")
            if not (r or {}).get("ok"):
                return Resultado(ok=False, erro=(r or {}).get("text") or "não consegui anotar o critério")
            return Resultado(texto=r["text"], dados=r)
        r = await cx.fn("f_mem_add", uid, texto, a.get("tipo") or "fato", "ia")
    if (r or {}).get("disabled"):
        return Resultado(ok=False, erro="a memória está desligada pelo usuário; não anote")
    if not (r or {}).get("ok"):
        return Resultado(ok=False, erro="não consegui anotar")
    return Resultado(texto=r.get("text") or "Anotei.", dados=r)


FERRAMENTA = Ferramenta(
    nome="memoria",
    descricao="Memória duradoura sobre o usuário. Fatos (hábito, preferência, relação) e CRITÉRIOS de decisão "
              "(\"não marco reunião sexta à tarde\", \"jantar fora até R$ 150\"), que valem para toda recomendação.",
    acoes={
        "listar": Acao("listar", CONSULTA, "mostra o que está anotado"),
        "anotar": Acao("anotar", CRIA, "anota um fato dito pelo usuário", resumo=lambda a: f"Anotar: {a.get('texto')}"),
        "criterio_pedido": Acao("criterio_pedido", CRIA, "critério que o USUÁRIO ditou agora", resumo=lambda a: f"Anotar o critério: {a.get('texto')}"),
        "criterio_sugerido": Acao("criterio_sugerido", ALTERA, "critério que VOCÊ percebeu por um padrão (vira proposta)",
                                  resumo=lambda a: f"Anotar o critério: {a.get('texto')}"),
        "esquecer": Acao("esquecer", CRIA, "apaga um fato ou critério (por #id ou trecho) a pedido do usuário"),
        "ligar": Acao("ligar", CRIA, "liga memória, sugestões ou oferta de salvar"),
        "desligar": Acao("desligar", CRIA, "desliga memória, sugestões ou oferta de salvar"),
    },
    parametros={
        "texto": S("string", "o fato ou critério, em uma frase"),
        "tipo": S("string", "", ["habito", "preferencia", "fato", "relacao"]),
        "referencia": S("string", "#id ou trecho do que esquecer"),
        "filtro": S("string", "pessoas, lugares, memoria, ou um texto"),
        "interruptor": S("string", "", ["memoria", "sugestoes", "oferta"]),
    },
    executar=lambda ctx, acao, a: _executar(ctx, "criterio" if acao.startswith("criterio") else acao, a),
)
