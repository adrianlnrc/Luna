"""Ferramenta agenda: compromissos no Google Agenda do usuario. As regras (conflito, serie, convites, lembretes ligados)
continuam nas funcoes SQL de agenda; aqui buscamos os eventos e cumprimos os pedidos ao Google."""
from __future__ import annotations

import re
import unicodedata
from datetime import date, datetime, time, timedelta

from ..chamadas import executar_cal
from ..tipos import Resultado
from .base import ALTERA, CONSULTA, CRIA, TERCEIROS, Acao, Ferramenta, L, S
from .util import data_ok, do_banco, fonte, hora_ok, quando

SEM_GOOGLE = ("Seu Google Agenda ainda não está conectado, então não consigo ver nem marcar compromissos. "
              "Conecte em /config (leva um minuto).")
REPETE = {"diario": "daily", "semanal": "weekly", "mensal": "monthly"}


def _norm(s: str) -> str:
    s = unicodedata.normalize("NFD", (s or "").lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn").strip()


def _local_e_nome(loc: str | None) -> bool:
    t = (loc or "").strip()
    if not t or len(t) > 40 or re.search(r"\d", t):
        return False
    return not re.search(r"(^|[^a-z])(online|zoom|meet|teams|remoto|telefone)([^a-z]|$)", _norm(t))


def _janela(ctx, a: dict, dias_padrao: int = 1) -> tuple[datetime, datetime, str]:
    hoje = ctx.agora.date()
    ini_d = date.fromisoformat(a["data_inicio"]) if data_ok(a.get("data_inicio")) else (
        date.fromisoformat(a["data"]) if data_ok(a.get("data")) else hoje)
    fim_d = date.fromisoformat(a["data_fim"]) if data_ok(a.get("data_fim")) else ini_d + timedelta(days=dias_padrao - 1)
    if fim_d < ini_d:
        ini_d, fim_d = fim_d, ini_d
    ini = datetime.combine(ini_d, time(0, 0), tzinfo=ctx.usuario.tz)
    fim = datetime.combine(fim_d, time(0, 0), tzinfo=ctx.usuario.tz) + timedelta(days=1)
    rot = ini.strftime("%d/%m") if ini_d == fim_d else f"{ini.strftime('%d/%m')} a {fim_d.strftime('%d/%m')}"
    return ini, fim, rot


async def _listar(ctx, a: dict) -> Resultado:
    ini, fim, rot = _janela(ctx, a)
    evs: list[dict] = []
    aviso = ""
    if ctx.usuario.google:
        evs = await ctx.nucleo.google.eventos(ctx.uid, ini, fim)
    else:
        aviso = "\n\n(Google Agenda não conectado: mostro só os lembretes. Conecte em /config.)"
    async with ctx.cx() as cx:
        r = await cx.fn("f_agenda_db", ctx.uid, ini, fim) or {}
    linhas = []
    for e in evs:
        qd = "dia todo" if e.get("all_day") else datetime.fromisoformat(e["start"].replace("Z", "+00:00")).astimezone(ctx.usuario.tz).strftime("%d/%m %H:%M")
        linhas.append(f"- {qd}  {e['title']}" + (f" ({e['location']})" if e.get("location") else ""))
    lem = [f"- {x['due']}  {x['title']}" for x in r.get("reminders") or []]
    est = [f"- {s['item']}: restam {round(float(s['units_left']))}, acaba em {s['runs_out_on']}" for s in r.get("supplies") or []]
    partes = [f"Sua agenda ({rot}):",
              "Compromissos:\n" + "\n".join(linhas) if linhas else "Compromissos: nenhum.",
              "Lembretes:\n" + "\n".join(lem) if lem else "Lembretes: nenhum."]
    if est:
        partes.append('Hora de comprar (diga "comprei" quando comprar):\n' + "\n".join(est))
    return Resultado(texto="\n\n".join(partes) + aviso, dados={"eventos": evs, **r})


async def _gerir(ctx, act: str, a: dict) -> Resultado:
    """mover | cancelar | horario livre | promover lembrete: f_agenda_manage decide, com os eventos do periodo."""
    if not ctx.usuario.google:
        return Resultado(texto=SEM_GOOGLE)
    agora = ctx.agora
    mg: dict = {"act": act, "title": a.get("titulo") or "", "calendar_key": "oauth"}
    ini = agora.replace(hour=0, minute=0, second=0, microsecond=0)
    fim = ini + timedelta(days=60)
    if act == "promote":
        ini, fim = agora, agora + timedelta(minutes=60)
        if a.get("duracao_min"):
            mg["duration_minutes"] = a["duracao_min"]
    elif act == "free":
        ini, fim, _ = _janela(ctx, a)
        if fim > ini + timedelta(days=7):
            fim = ini + timedelta(days=7)
        mg["part"] = a.get("periodo_do_dia") or ""
        mg["min_minutes"] = a.get("duracao_min") or 30
    elif act == "cancel":
        if data_ok(a.get("data")) or data_ok(a.get("data_inicio")):
            ini, fim, _ = _janela(ctx, {"data_inicio": a.get("data_inicio") or a.get("data"), "data_fim": a.get("data_fim")})
    else:  # move
        if data_ok(a.get("data_inicio")):
            ini, fim, _ = _janela(ctx, {"data_inicio": a["data_inicio"], "data_fim": a.get("data_fim")})
        if not hora_ok(a.get("nova_hora")):
            return Resultado(ok=False, erro=f"para que horário mover \"{a.get('titulo') or 'o compromisso'}\"? Pergunte ao usuário.")
        hh = a["nova_hora"] if len(a["nova_hora"]) == 5 else "0" + a["nova_hora"]
        mg["new_time"] = hh
        if a.get("duracao_min"):
            mg["duration_minutes"] = a["duracao_min"]
        if data_ok(a.get("nova_data")):
            nd = datetime.combine(date.fromisoformat(a["nova_data"]), time(int(hh[:2]), int(hh[3:])), tzinfo=ctx.usuario.tz)
            if nd <= agora:
                return Resultado(ok=False, erro="esse horário novo já passou; pergunte para quando mover")
            mg["new_start"] = nd.isoformat()
            ini = min(ini, nd.replace(hour=0, minute=0))
            fim = max(fim, nd.replace(hour=0, minute=0) + timedelta(days=1))
    mg["win_start"], mg["win_end"] = ini.isoformat(), fim.isoformat()
    try:
        evs = await ctx.nucleo.google.eventos(ctx.uid, ini, fim)
        mg.update(ok=True, error=None, events=evs)
    except Exception as e:
        mg.update(ok=False, error=str(e)[:120], events=[])
    async with ctx.cx() as cx:
        return do_banco(await cx.fn("f_agenda_manage", ctx.uid, mg))


async def _criar(ctx, a: dict, com_convite: bool) -> Resultado:
    if not ctx.usuario.google:
        return Resultado(texto=SEM_GOOGLE)
    if not a.get("titulo"):
        return Resultado(ok=False, erro="falta o título do compromisso")
    dt, erro = quando(ctx, a.get("data"), a.get("hora"))
    if erro:
        return Resultado(ok=False, erro=erro)
    if dt <= ctx.agora and not ctx.est.confirmada:
        return Resultado(ok=False, erro="esse horário já passou; pergunte para quando")
    fim = dt + timedelta(minutes=int(a.get("duracao_min") or 60))
    freq = REPETE.get(a.get("repete") or "", "")
    ate = a["repete_ate"] if freq and data_ok(a.get("repete_ate")) else ""
    vezes = str(int(a["repete_vezes"])) if freq and not ate and (a.get("repete_vezes") or 0) > 0 else ""
    lead = str(int(a["antecedencia_min"])) if a.get("antecedencia_min") is not None else ""
    local = a.get("local") or ""
    convidados = [c for c in (a.get("convidados") or []) if c.strip()]

    lugar_desconhecido = False
    if _local_e_nome(local):
        async with ctx.cx() as cx:
            lugar_desconhecido = await cx.fn("f_find_lugar", ctx.uid, local) is None

    if com_convite or lugar_desconhecido:
        # caminho com confirmacao no banco: convite, Meet ou pergunta de endereco
        async with ctx.cx() as cx:
            return do_banco(await cx.fn("f_invite_prepare", ctx.uid, {
                "summary": a["titulo"], "start": dt.isoformat(), "end": fim.isoformat(), "location": local,
                "meet": bool(a.get("meet")), "invitees": convidados, "repeat_freq": freq, "repeat_until": ate,
                "repeat_count": int(vezes) if vezes else None, "lead_str": lead, "source": fonte(ctx)}),
                "Não consegui preparar o compromisso agora. Tente de novo.")

    cal = {"op": "create", "summary": a["titulo"], "start": dt.isoformat(), "end": fim.isoformat(), "location": local,
           "attendees": "", "meet": "false", "repeat_freq": freq, "repeat_until": ate, "repeat_count": vezes,
           "force": "true" if a.get("mesmo_com_conflito") else "false"}
    res = await executar_cal(ctx.nucleo, ctx.uid, cal)
    req = {"title": a["titulo"], "due_iso": dt.isoformat(), "end_iso": fim.isoformat(), "location": local, "lead_str": lead,
           "source": fonte(ctx), "calendar_key": "oauth", "repeat_freq": freq, "repeat_until": ate, "repeat_count": vezes}
    async with ctx.cx() as cx:
        r = await cx.fn("f_agenda_after_create", ctx.uid, req, res)
        if res.get("ok") and not res.get("conflict") and res.get("event_id") and ctx.lote:
            await cx.exec(
                "INSERT INTO agente.recent_actions (user_id, batch_id, kind, ref_text, calendar_key, label) VALUES (%s, %s, 'event', %s, 'oauth', %s)",
                ctx.uid, ctx.lote, res["event_id"], f"compromisso {a['titulo']}"[:120])
    out = do_banco(r, "Não consegui registrar o compromisso agora. Tente de novo.")
    out.ok = bool(res.get("ok"))
    if not out.ok:
        out.erro = out.texto
    return out


async def _importar_foto(ctx, a: dict) -> Resultado:
    from ..midia import ler_agenda_de_papel
    if not ctx.usuario.google:
        return Resultado(texto=SEM_GOOGLE)
    if not ctx.arquivo or ctx.arquivo.tipo != "photo":
        return Resultado(texto="Para importar a sua agenda, mande a foto da página inteira, bem iluminada e sem reflexo. "
                               "Eu leio e mostro tudo antes de criar.")
    x = await ler_agenda_de_papel(ctx)
    async with ctx.cx() as cx:
        return do_banco(await cx.fn("f_agimp_create", ctx.uid, x))


async def _importar_editar(ctx, a: dict) -> Resultado:
    hm = lambda v: (v if len(v) == 5 else "0" + v) if hora_ok(v) else ""
    act = {"corrigir": "edit", "tirar": "remove", "confirmar": "confirm", "cancelar": "cancel"}.get(a.get("importacao_acao") or "", "edit")
    async with ctx.cx() as cx:
        r = await cx.fn("f_agimp_edit", ctx.uid, {"act": act, "n": a.get("item_n"), "title": a.get("titulo") or "",
                                                 "date": a["data"] if data_ok(a.get("data")) else "",
                                                 "time": hm(a.get("hora")), "end": hm(a.get("hora_fim"))})
    r = r or {}
    if r.get("imp"):
        from ..chamadas import concluir_importacao
        return await concluir_importacao(ctx.nucleo, ctx.usuario, r["imp"])
    return do_banco(r)


async def _executar(ctx, acao: str, a: dict) -> Resultado:
    if acao == "listar":
        return await _listar(ctx, a)
    if acao == "horario_livre":
        return await _gerir(ctx, "free", a)
    if acao == "mover":
        return await _gerir(ctx, "move", a)
    if acao == "cancelar":
        return await _gerir(ctx, "cancel", a)
    if acao == "lembrete_vira_compromisso":
        return await _gerir(ctx, "promote", a)
    if acao == "criar":
        return await _criar(ctx, a, False)
    if acao == "convidar":
        return await _criar(ctx, a, True)
    if acao == "importar_foto":
        return await _importar_foto(ctx, a)
    if acao == "importar_editar":
        return await _importar_editar(ctx, a)
    if acao == "link":
        async with ctx.cx() as cx:
            return do_banco(await cx.fn("f_misc", ctx.uid, {"kind": "calendar_link", "title": ""}))
    return Resultado(ok=False, erro="acao desconhecida")


def _r_criar(a: dict) -> str:
    return (f"Marcar \"{a.get('titulo')}\" em {a.get('data') or 'hoje'} às {a.get('hora')}"
            + (f" ({a.get('duracao_min')} min)" if a.get("duracao_min") else "")
            + (f" em {a.get('local')}" if a.get("local") else "")
            + (f", convidando {', '.join(a.get('convidados') or [])}" if a.get("convidados") else "")
            + (" com link do Meet" if a.get("meet") else ""))


FERRAMENTA = Ferramenta(
    nome="agenda",
    descricao="Compromissos no Google Agenda do usuário: ver, achar horário livre, marcar, convidar pessoas, mover e cancelar. "
              "Também importa a foto de uma agenda de papel.",
    google=True,
    acoes={
        "listar": Acao("listar", CONSULTA, "compromissos e lembretes de um dia ou período"),
        "horario_livre": Acao("horario_livre", CONSULTA, "horários livres dentro do expediente"),
        "link": Acao("link", CONSULTA, "link para abrir a agenda"),
        "criar": Acao("criar", CRIA, "marca compromisso SEM convidados; exige data e hora", resumo=_r_criar),
        "importar_foto": Acao("importar_foto", CRIA, "lê a foto de uma agenda de papel e mostra um rascunho para confirmar", nativa=True),
        "importar_editar": Acao("importar_editar", CRIA, "corrige, tira, confirma ou cancela itens do rascunho da importação", nativa=True),
        "lembrete_vira_compromisso": Acao("lembrete_vira_compromisso", ALTERA, "transforma um lembrete em compromisso", nativa=True),
        "mover": Acao("mover", ALTERA, "muda dia e/ou hora de um compromisso", nativa=True),
        "cancelar": Acao("cancelar", ALTERA, "cancela um compromisso", nativa=True),
        "convidar": Acao("convidar", TERCEIROS, "marca compromisso COM convidados ou link do Meet (o convite só sai após confirmar)", nativa=True),
    },
    parametros={
        "titulo": S("string", "nome do compromisso"),
        "data": S("string", "AAAA-MM-DD"),
        "hora": S("string", "HH:MM"),
        "duracao_min": S("integer", "duração em minutos (padrão 60)"),
        "local": S("string"),
        "antecedencia_min": S("integer", "aviso antes, só se o usuário pediu"),
        "repete": S("string", "", ["diario", "semanal", "mensal"]),
        "repete_ate": S("string", "AAAA-MM-DD"),
        "repete_vezes": S("integer"),
        "convidados": L("string", "nomes de contatos ou grupos, ou e-mails"),
        "meet": S("boolean", "criar link do Meet"),
        "mesmo_com_conflito": S("boolean", "só true se o usuário já disse para marcar mesmo com conflito"),
        "data_inicio": S("string", "início do período de busca AAAA-MM-DD"),
        "data_fim": S("string", "fim do período AAAA-MM-DD"),
        "periodo_do_dia": S("string", "", ["manha", "tarde", "noite"]),
        "nova_data": S("string", "AAAA-MM-DD"),
        "nova_hora": S("string", "HH:MM"),
        "importacao_acao": S("string", "", ["corrigir", "tirar", "confirmar", "cancelar"]),
        "item_n": S("integer", "número do item no rascunho"),
        "hora_fim": S("string", "HH:MM"),
    },
    executar=_executar,
)
