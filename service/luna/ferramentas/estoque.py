"""Ferramenta estoque: itens de uso continuo (remedios e suplementos). Dado de saude: exige aceite (PRD RF-14)."""
from __future__ import annotations

from ..tipos import Resultado
from .base import ALTERA, CONSULTA, CRIA, Acao, Ferramenta, S
from .util import data_ok, hora_ok


def _rem(r: dict) -> str:
    return " (remédio)" if r.get("kind") == "remedio" else ""


async def _executar(ctx, acao: str, a: dict) -> Resultado:
    uid, item = ctx.uid, (a.get("item") or "")
    async with ctx.cx() as cx:
        if acao == "situacao":
            linhas = await cx.linhas(
                "SELECT item, kind, units_left, to_char(runs_out_on,'DD/MM') AS acaba, to_char(take_time,'HH24:MI') AS hora "
                "FROM agente.supplies_status WHERE user_id = %s AND status = 'active' ORDER BY runs_out_on NULLS LAST, item", uid)
            if not linhas:
                return Resultado(texto="Você não tem itens de uso contínuo cadastrados.")
            return Resultado(texto="Itens de uso contínuo:\n" + "\n".join(
                f"- {l['item']}: " + (f"restam {round(l['units_left'])}, acaba em {l['acaba']}" if l["units_left"] is not None else "sem contagem")
                + (f", tomar às {l['hora']}" if l["hora"] else "") for l in linhas), dados=linhas)

        if not item:
            return Resultado(ok=False, erro="diga o nome do item")

        if acao == "cadastrar":
            r = await cx.valor(
                "SELECT agente.f_create_supply(%s, %s, %s::int, %s::numeric, %s::date, %s::int, %s, %s::time, %s::int) AS r",
                uid, item, a.get("quantidade"), a.get("por_dia"), a["inicio"] if data_ok(a.get("inicio")) else None,
                a.get("avisar_dias"), a.get("tipo"), a["hora_tomar"] if hora_ok(a.get("hora_tomar")) else None, a.get("cartela")) or {}
            t = f"Anotado: {r.get('item')}{_rem(r)}."
            if r.get("take_time"):
                t += f"\nLembro de tomar todo dia às {r['take_time']} e repito a cada 10 minutos até você tocar Tomei."
            if r.get("needs_total") and r.get("ask_total"):
                t += "\nQuantos comprimidos tem na cartela agora? (Pode mandar uma foto.)"
            elif not r.get("needs_total"):
                t += (f"\nRestam {round(float(r['units_left']))} e acaba em {r['runs_out_on']}. "
                      f"O aviso de compra entra no resumo da manhã a partir de {r['alert_on']}.")
                if not r.get("take_time"):
                    t += f"\nQuer lembrete na hora de tomar? Diga: me lembre de tomar {r.get('item')} às 8h."
            return Resultado(texto=t, dados=r)

        if acao == "comprei":
            r = await cx.fn("f_supply_bought", uid, item) or {}
            return Resultado(texto=(f"Anotado! Recomecei a contagem de {r['item']}"
                                    + (f": {r['units_total']} unidades" if r.get("units_total") else "") + ". Paro de avisar da compra.")
                             if r.get("found") else "Não achei esse item. Me diga o nome, por exemplo: comprei a losartana.", dados=r)

        if acao == "tomei":
            r = await cx.fn("f_supply_taken", uid, item) or {}
            if not r.get("found"):
                t = "Não achei esse item. Para cadastrar e já ligar o lembrete, diga: me lembre de tomar losartana todo dia às 8h."
            elif not r.get("tracking"):
                t = (f"Anotei. Mas {r['item']} ainda não tem lembrete de tomar, então a contagem segue por dias. "
                     f"Para eu controlar cada dose, diga: me lembre de tomar {r['item']} às 8h.")
            elif r.get("units_left") is None:
                t = f"Anotado: tomou {r['item']}. Quantos comprimidos tem na cartela agora? Assim eu aviso quando for comprar."
            else:
                t = f"Anotado: tomou {r['item']}. Restam {round(float(r['units_left']))} (acaba em {r['runs_out_on']})."
            return Resultado(texto=t, dados=r)

        if acao in ("lembrete_de_tomar", "parar_lembrete"):
            parar = acao == "parar_lembrete"
            if not parar and not hora_ok(a.get("hora_tomar")):
                return Resultado(ok=False, erro="falta a hora de tomar (HH:MM); pergunte ao usuário")
            r = await cx.valor("SELECT agente.f_supply_schedule(%s, %s, %s, %s, %s) AS r",
                               uid, item, None if parar else a["hora_tomar"], parar, a.get("tipo")) or {}
            if not r.get("found"):
                t = "Não achei esse item para parar o lembrete. Me diga o nome."
            elif r.get("cleared"):
                t = f"Parei os lembretes de tomar {r['item']}. A contagem volta a seguir por dias."
            else:
                t = (f"Anotado: {r['item']}{_rem(r)}. Lembro de tomar todo dia às {r['take_time']} "
                     "e repito a cada 10 minutos até você tocar Tomei.")
                if r.get("needs_total") and r.get("ask_total"):
                    t += "\nQuantos comprimidos tem na cartela agora? (Pode mandar uma foto.) Assim eu aviso quando for comprar."
                elif not r.get("needs_total"):
                    t += f"\nRestam {round(float(r['units_left']))} e acaba em {r['runs_out_on']}."
            return Resultado(texto=t, dados=r)

        # ajustar | renomear | apagar
        sa = {"renomear": "rename", "apagar": "delete"}.get(acao)
        r = await cx.valor("SELECT agente.f_supply_manage(%s, %s, %s::int, %s::int, %s, %s) AS r",
                           uid, item, a.get("restam"), a.get("pausa_dias"), sa, a.get("novo_nome")) or {}
    if r.get("action") == "rename":
        if r.get("need_name"):
            t = "Qual o novo nome do remédio?"
        elif not r.get("found"):
            t = "Não achei um item para renomear."
        elif r.get("conflict"):
            t = f"Já existe um item chamado {r['item']}. Quer apagar o outro?"
        else:
            t = f"Pronto: {r['old_item']} agora se chama {r['item']}" + (f" (lembrete diário às {r['take_time']} mantido)" if r.get("take_time") else "") + "."
        return Resultado(texto=t, dados=r)
    if r.get("action") == "delete":
        if not r.get("found"):
            return Resultado(texto="Não achei esse remédio. Me diga o nome, por exemplo: apaga o remédio sertralina.", dados=r)
        return Resultado(texto=f"Apagar {r['item']}" + (f" e o lembrete de tomar às {r['take_time']}" if r.get("take_time") else "") + "?",
                         kb="sup_del", rid=r.get("sid") or 0, dados=r)
    return Resultado(texto=(f"Ajustado: {r['item']} - restam {round(float(r['units_left']))}, acaba em {r['runs_out_on']} (aviso em {r['alert_on']})."
                            if r.get("found") else "Não achei esse item. Me diga o nome, por exemplo: tenho 12 na cartela de losartana."), dados=r)


FERRAMENTA = Ferramenta(
    nome="estoque",
    descricao="Itens de uso contínuo (remédios, vitaminas, suplementos): contagem, aviso de compra e lembrete de tomar.",
    saude=True,
    acoes={
        "situacao": Acao("situacao", CONSULTA, "quanto resta de cada item e quando acaba"),
        "cadastrar": Acao("cadastrar", CRIA, "cadastra item (quantidade, consumo por dia, hora de tomar)"),
        "comprei": Acao("comprei", CRIA, "comprou: recomeça a contagem"),
        "tomei": Acao("tomei", CRIA, "registra dose tomada"),
        "lembrete_de_tomar": Acao("lembrete_de_tomar", CRIA, "liga lembrete diário na hora de tomar"),
        "ajustar": Acao("ajustar", ALTERA, "corrige quantidade (\"tenho 12\") ou pausa (\"pausei 3 dias\")",
                        resumo=lambda a: f"Ajustar {a.get('item')}" + (f": restam {a.get('restam')}" if a.get("restam") is not None else "")
                        + (f", pausa de {a.get('pausa_dias')} dia(s)" if a.get("pausa_dias") else "")),
        "parar_lembrete": Acao("parar_lembrete", ALTERA, "para o lembrete de tomar",
                               resumo=lambda a: f"Parar o lembrete de tomar {a.get('item')}"),
        "renomear": Acao("renomear", ALTERA, "troca o nome do item",
                         resumo=lambda a: f"Renomear {a.get('item')} para {a.get('novo_nome')}"),
        "apagar": Acao("apagar", ALTERA, "apaga o item", nativa=True),
    },
    parametros={
        "item": S("string", "nome do item"),
        "tipo": S("string", "", ["remedio", "suplemento"]),
        "quantidade": S("integer", "unidades que tem agora ou na cartela"),
        "por_dia": S("number", "consumo por dia"),
        "inicio": S("string", "AAAA-MM-DD em que começou"),
        "avisar_dias": S("integer", "avisar quando faltarem X dias"),
        "hora_tomar": S("string", "HH:MM"),
        "cartela": S("integer", "tamanho da cartela"),
        "restam": S("integer", "quantas unidades restam"),
        "pausa_dias": S("integer"),
        "novo_nome": S("string"),
    },
    executar=_executar,
)
