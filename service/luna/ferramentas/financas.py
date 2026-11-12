"""Ferramenta financas: invoucro de agente.f_fin (mesmo JSON que o roteador do n8n monta em fin_json)."""
from __future__ import annotations

import csv
import io

from ..tipos import Resultado
from .base import ALTERA, CONSULTA, CRIA, Acao, Ferramenta, L, S
from .util import data_ok, do_banco, fonte

# acao da ferramenta -> action de f_fin
CONSULTAS = {
    "resumo": ("summary", "resumo do período (gastos, receitas, saldo, por categoria)"),
    "comparar": ("compare", "compara com o mês anterior"),
    "maiores": ("top", "maiores despesas"),
    "por_dia": ("by_day", "gastos por dia"),
    "orcamento_ver": ("budget_status", "orçamentos por categoria e quanto já foi"),
    "categorias": ("category_list", "lista as categorias"),
    "quem_me_deve": ("owed", "valores a receber de pessoas"),
    "limite_ver": ("limit_status", "limite geral do mês e quanto ainda pode gastar"),
    "planejamento": ("plan_status", "renda menos gasto, comprometido e metas"),
    "metas": ("goal_status", "progresso das metas de economia"),
    "cartoes": ("card_list", "lista os cartões"),
    "fatura": ("card_status", "fatura aberta/fechada e limite disponível de um cartão"),
    "total_categoria": ("category_total", "total de uma categoria num mês"),
    "total_forma": ("method_total", "total por forma de pagamento"),
    "sobra_do_mes": ("left_to_close", "quanto sobrou para fechar o mês"),
    "comprometido": ("committed", "quanto já está comprometido num mês"),
    "relatorio": ("report", "gera arquivo com os lançamentos (formato csv ou xlsx)"),
}
CRIAM = {
    "lancar": ("add", "registra gasto ou receita (valor, descrição; parcelas; conta fixa com dia_fixo; no cartão; a pagar com pago=false)"),
    "dar_baixa": ("pay", "marca uma conta como paga"),
    "meta_criar": ("goal_create", "cria meta de economia (descricao, valor, data limite)"),
    "meta_guardar": ("goal_deposit", "registra valor guardado numa meta"),
    "meta_retirar": ("goal_withdraw", "registra retirada de uma meta"),
    "categoria_criar": ("category_create", "cria categoria"),
    "cartao_criar": ("card_create", "cadastra cartão (fechamento, vencimento, limite)"),
}
ALTERAM = {
    "corrigir": ("correct", "corrige um lançamento (valor, categoria, data)", False),
    "apagar": ("remove", "apaga um lançamento", True),
    "orcamento_definir": ("budget_set", "define orçamento de uma categoria", False),
    "limite_definir": ("limit_set", "define o limite geral do mês", False),
    "limite_tirar": ("limit_clear", "tira o limite geral", False),
    "renda_definir": ("income_set", "define a renda prevista do mês", False),
    "fechamento_definir": ("closing_set", "muda o dia de fechamento do mês financeiro", False),
    "meta_editar": ("goal_edit", "edita uma meta", False),
    "meta_apagar": ("goal_remove", "apaga uma meta", True),
    "cartao_editar": ("card_edit", "edita um cartão", False),
    "cartao_apagar": ("card_remove", "apaga um cartão", True),
}
MAPA = {k: v[0] for k, v in {**CONSULTAS, **CRIAM, **ALTERAM}.items()}


def _brl(v) -> str:
    try:
        s = f"{float(v):,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    except (TypeError, ValueError):
        return str(v)
    return "R$ " + s


def _resumo(acao: str):
    def f(a: dict) -> str:
        partes = []
        if a.get("descricao"):
            partes.append(str(a["descricao"]))
        if a.get("valor") is not None:
            partes.append(_brl(a["valor"]))
        for k in ("categoria", "cartao", "data", "mes"):
            if a.get(k):
                partes.append(f"{k} {a[k]}")
        if a.get("dia") is not None:
            partes.append(f"dia {a['dia']}")
        titulo = {
            "corrigir": "Corrigir lançamento", "apagar": "Apagar lançamento", "orcamento_definir": "Definir orçamento",
            "limite_definir": "Definir limite geral do mês", "limite_tirar": "Tirar o limite geral",
            "renda_definir": "Definir renda prevista", "fechamento_definir": "Mudar o dia de fechamento do mês",
            "meta_editar": "Editar meta", "meta_apagar": "Apagar meta", "cartao_editar": "Editar cartão",
            "cartao_apagar": "Apagar cartão", "lancar": "Lançar " + ("receita" if a.get("tipo") == "receita" else "gasto"),
            "dar_baixa": "Dar baixa em", "meta_criar": "Criar meta", "meta_guardar": "Guardar na meta",
            "meta_retirar": "Retirar da meta", "categoria_criar": "Criar categoria", "cartao_criar": "Cadastrar cartão",
        }.get(acao, acao)
        return titulo + (": " + ", ".join(partes) if partes else "")
    return f


def _pedido(ctx, acao: str, a: dict) -> dict:
    valor = a.get("valor")
    return {
        "action": MAPA[acao], "kind": "income" if a.get("tipo") == "receita" else "expense",
        "amount": valor, "budget_amount": valor, "title": a.get("descricao") or "",
        "category": a.get("categoria") or "", "category_stated": bool(a.get("categoria")),
        "method": a.get("forma") or "", "installments": a.get("parcelas") or 1,
        "paid": False if a.get("pago") is False else True,
        "date": a["data"] if data_ok(a.get("data")) else "", "recurring_day": a.get("dia_fixo"),
        "person": a.get("pessoa") or "", "period": a.get("periodo") or "current", "keywords": a.get("palavras") or "",
        "closing_day": a.get("dia"), "card": a.get("cartao") or "",
        "card_closing_day": a.get("cartao_fechamento"), "card_due_day": a.get("cartao_vencimento"),
        "card_limit": a.get("cartao_limite"), "month": a.get("mes") or "", "alert_days": None,
        "report_format": a.get("formato") or "",
        "items": [{"title": str(i.get("descricao") or ""), "amount": float(i.get("valor") or 0), "category": i.get("categoria")}
                  for i in (a.get("itens") or []) if isinstance(i, dict) and float(i.get("valor") or 0) > 0],
        "source": fonte(ctx), "reply": "",
    }


async def _relatorio(ctx, r: dict) -> Resultado:
    rep = r.get("report") or {}
    async with ctx.cx() as cx:
        d = await cx.fn("f_report_data", ctx.uid, {"period": rep.get("period") or "current", "month": rep.get("month") or "",
                                                   "keywords": rep.get("keywords") or ""})
    linhas = (d or {}).get("lines") or []
    if not (d or {}).get("count"):
        return Resultado(texto=f"Não há lançamentos {(d or {}).get('label') or 'no período'} para o relatório.")
    cols = list(linhas[0].keys()) if linhas else []
    formato = (rep.get("format") or "csv").lower()
    nota = ""
    if formato == "pdf":
        formato, nota = "xlsx", " (PDF ainda não sai por aqui; mandei em planilha)"
    if formato == "xlsx":
        from openpyxl import Workbook
        wb = Workbook()
        ws = wb.active
        ws.title = "Lançamentos"
        ws.append(cols)
        for ln in linhas:
            ws.append([ln.get(c) for c in cols])
        buf = io.BytesIO()
        wb.save(buf)
        anexo = ("relatorio.xlsx", buf.getvalue(), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    else:
        buf2 = io.StringIO()
        w = csv.writer(buf2, delimiter=";")
        w.writerow(cols)
        for ln in linhas:
            w.writerow([str(ln.get(c, "")).replace(".", ",") if isinstance(ln.get(c), (int, float)) else ln.get(c, "") for c in cols])
        anexo = ("relatorio.csv", ("﻿" + buf2.getvalue()).encode("utf-8"), "text/csv")
    return Resultado(texto=f"Relatório {d.get('label')}: {d.get('count')} lançamento(s){nota}.", anexo=anexo, dados=d)


async def _executar(ctx, acao: str, args: dict) -> Resultado:
    if acao == "lancar" and args.get("valor") is None and not args.get("itens"):
        return Resultado(ok=False, erro="falta o valor do lançamento; pergunte ao usuário")
    async with ctx.cx() as cx:
        r = await cx.fn("f_fin", ctx.uid, _pedido(ctx, acao, args))
    if acao == "relatorio" and isinstance(r, dict) and r.get("report"):
        return await _relatorio(ctx, r)
    return do_banco(r, "Não consegui registrar agora. Tente de novo.")


ACOES = {}
for nome, (_, desc) in CONSULTAS.items():
    ACOES[nome] = Acao(nome, CONSULTA, desc)
for nome, (_, desc) in CRIAM.items():
    ACOES[nome] = Acao(nome, CRIA, desc, resumo=_resumo(nome))
for nome, (_, desc, nativa) in ALTERAM.items():
    ACOES[nome] = Acao(nome, ALTERA, desc, nativa=nativa, resumo=_resumo(nome))

FERRAMENTA = Ferramenta(
    nome="financas",
    descricao="Dinheiro do usuário: lançamentos, contas a pagar e fixas, parcelas, orçamento por categoria, limite geral, "
              "metas de economia, cartões e faturas, relatórios. Cada pessoa tem as próprias finanças.",
    acoes=ACOES,
    parametros={
        "tipo": S("string", "gasto ou receita", ["gasto", "receita"]),
        "valor": S("number", "valor em reais"),
        "descricao": S("string", "descrição do lançamento, nome da meta ou da conta"),
        "categoria": S("string", "categoria, só se o usuário disse"),
        "forma": S("string", "forma de pagamento", ["pix", "debito", "credito", "dinheiro", "boleto"]),
        "parcelas": S("integer", "número de parcelas"),
        "pago": S("boolean", "false quando é conta a pagar"),
        "data": S("string", "AAAA-MM-DD (data do lançamento, prazo da meta)"),
        "dia_fixo": S("integer", "dia do mês de uma conta fixa (\"todo dia 5\")"),
        "pessoa": S("string", "quem deve ou a quem deve"),
        "periodo": S("string", "período da consulta", ["current", "previous", "today", "yesterday", "week"]),
        "mes": S("string", "mês específico AAAA-MM"),
        "palavras": S("string", "palavras para filtrar a consulta"),
        "dia": S("integer", "dia de fechamento do mês financeiro"),
        "cartao": S("string", "nome do cartão"),
        "cartao_fechamento": S("integer"), "cartao_vencimento": S("integer"), "cartao_limite": S("number"),
        "formato": S("string", "formato do relatório", ["csv", "xlsx", "pdf"]),
        "itens": {"type": ["array", "null"], "description": "itens de um recibo (foto)", "items": {
            "type": "object", "properties": {"descricao": {"type": "string"}, "valor": {"type": "number"},
                                             "categoria": {"type": ["string", "null"]}},
            "required": ["descricao", "valor", "categoria"], "additionalProperties": False}},
    },
    executar=_executar,
)
