"""Ferramenta lembretes: criar, listar, cancelar e ligar a um compromisso. Invoucro das funcoes f_reminder_*."""
from __future__ import annotations

from datetime import timedelta

from ..tipos import Resultado
from .base import ALTERA, CONSULTA, CRIA, Acao, Ferramenta, S
from .util import data_ok, do_banco, fonte, minutos, quando, rotulo


def _resumo_criar(a: dict) -> str:
    return (f"Criar lembrete: {a.get('titulo')}" + (f" em {a.get('data')}" if a.get("data") else "")
            + (f" às {a.get('hora')}" if a.get("hora") else "")
            + (f", repete {a.get('repete')}" if a.get("repete") else ""))


async def _executar(ctx, acao: str, a: dict) -> Resultado:
    uid = ctx.uid
    if acao == "listar":
        ini = ctx.agora.replace(hour=0, minute=0, second=0, microsecond=0)
        dias = max(1, min(int(a.get("dias") or 7), 60))
        async with ctx.cx() as cx:
            r = await cx.fn("f_agenda_db", uid, ini, ini + timedelta(days=dias))
        lem = (r or {}).get("reminders") or []
        if not lem:
            return Resultado(texto=f"Nenhum lembrete pendente nos próximos {dias} dias.", dados=r)
        return Resultado(texto="Lembretes pendentes:\n" + "\n".join(f"- {x['due']} {x['title']}" for x in lem), dados=r)

    if acao == "historico":
        async with ctx.cx() as cx:
            return do_banco(await cx.fn("f_misc", uid, {"kind": "reminder_history", "title": a.get("titulo") or ""}))

    if acao == "cancelar":
        if not a.get("titulo"):
            return Resultado(ok=False, erro="diga qual lembrete (título)")
        async with ctx.cx() as cx:
            return do_banco(await cx.fn("f_reminder_cancel", uid, a["titulo"]))

    if acao == "ligar_a_compromisso":
        async with ctx.cx() as cx:
            return do_banco(await cx.fn("f_reminder_link", uid, {
                "title": a.get("titulo") or "", "link_event": a.get("compromisso") or "", "person": a.get("pessoa") or "",
                "lead_minutes": a.get("antecedencia_min") if (a.get("antecedencia_min") or 0) > 0 else None, "source": fonte(ctx)}))

    # criar
    if not a.get("titulo"):
        return Resultado(ok=False, erro="falta o título do lembrete")
    dt, erro = quando(ctx, a.get("data"), a.get("hora"))
    if erro:
        return Resultado(ok=False, erro=erro)
    if dt <= ctx.agora:
        return Resultado(ok=False, erro="esse horário já passou; pergunte para quando")
    lead = a.get("antecedencia_min")
    rep = {"freq": {"diario": "daily", "semanal": "weekly", "mensal": "monthly", "anual": "yearly"}.get(a.get("repete") or "", ""),
           "until": a["repete_ate"] if data_ok(a.get("repete_ate")) else "",
           "count": a.get("repete_vezes") if (a.get("repete_vezes") or 0) > 0 else ""}
    async with ctx.cx() as cx:
        r = await cx.valor(
            "SELECT agente.f_reminder_create_ex(%s, %s, %s, false, %s, %s, %s::jsonb) AS r",
            uid, a["titulo"], dt, int(lead) if lead and lead > 0 else None, fonte(ctx), __import__("json").dumps(rep))
    r = r or {}
    rot = rotulo(ctx, dt)
    if r.get("duplicate"):
        return Resultado(texto=f'Já tinha esse lembrete: "{a["titulo"]}" - {rot}.', dados=r)
    txt = f'Lembrete criado: "{a["titulo"]}" - {rot}.' + (f" Repete {r['repeat_text']}." if r.get("repeat_text") else "")
    if lead and lead > 0:
        txt += f" Aviso {minutos(lead)} antes."
    kb = "none"
    if r.get("ask_lead"):
        txt += '\nQuer que eu te lembre antes? (Dica: diga "sempre me avise 30 min antes" e eu não pergunto mais.)'
        kb = "lead"
    return Resultado(texto=txt, kb=kb, rid=r.get("reminder_id") or 0, dados=r)


FERRAMENTA = Ferramenta(
    nome="lembretes",
    descricao="Lembretes do usuário (avisos no chat, com ou sem repetição). Para compromisso com hora marcada na agenda use `agenda`.",
    acoes={
        "listar": Acao("listar", CONSULTA, "lembretes pendentes dos próximos dias"),
        "historico": Acao("historico", CONSULTA, "se e quando um lembrete foi avisado"),
        "criar": Acao("criar", CRIA, "cria lembrete; exige data e hora (pergunte se faltar a hora)", resumo=_resumo_criar),
        "ligar_a_compromisso": Acao("ligar_a_compromisso", CRIA, "lembrete preso a um compromisso e a uma pessoa (\"levar X pra Maria na festa\")"),
        "cancelar": Acao("cancelar", ALTERA, "cancela um lembrete ou para a repetição",
                         resumo=lambda a: f"Cancelar o lembrete \"{a.get('titulo')}\""),
    },
    parametros={
        "titulo": S("string", "o que lembrar"),
        "data": S("string", "AAAA-MM-DD"),
        "hora": S("string", "HH:MM"),
        "antecedencia_min": S("integer", "aviso antes, em minutos (só se o usuário pediu)"),
        "repete": S("string", "repetição", ["diario", "semanal", "mensal", "anual"]),
        "repete_ate": S("string", "AAAA-MM-DD"),
        "repete_vezes": S("integer"),
        "compromisso": S("string", "nome do compromisso a que o lembrete se liga"),
        "pessoa": S("string"),
        "dias": S("integer", "horizonte da listagem (padrão 7)"),
    },
    executar=_executar,
)
