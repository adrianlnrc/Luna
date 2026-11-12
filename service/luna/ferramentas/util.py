"""Ajudas comuns das ferramentas: datas no fuso do usuario e conversao do retorno das funcoes SQL."""
from __future__ import annotations

import re
from datetime import date, datetime, time, timedelta
from typing import Any

from ..tipos import Resultado

RE_DATA = re.compile(r"^\d{4}-\d{2}-\d{2}$")
RE_HORA = re.compile(r"^([01]?\d|2[0-3]):([0-5]\d)$")
DIAS_CURTOS = ["seg", "ter", "qua", "qui", "sex", "sáb", "dom"]


def data_ok(s: str | None) -> bool:
    if not s or not RE_DATA.match(s):
        return False
    try:
        date.fromisoformat(s)
        return True
    except ValueError:
        return False


def hora_ok(s: str | None) -> bool:
    return bool(s and RE_HORA.match(s))


def quando(ctx, data: str | None, hora: str | None) -> tuple[datetime | None, str]:
    """Junta data e hora no fuso do usuario. Devolve (datetime, erro). Nunca supoe horario."""
    if not hora_ok(hora):
        return None, "falta o horário (HH:MM). Pergunte ao usuário a que horas; não suponha."
    if data is None:
        d = ctx.agora.date()
    elif data_ok(data):
        d = date.fromisoformat(data)
    else:
        return None, "data inválida: use AAAA-MM-DD"
    h, m = map(int, hora.split(":"))
    dt = datetime.combine(d, time(h, m), tzinfo=ctx.usuario.tz)
    if data is None and dt <= ctx.agora:
        dt += timedelta(days=1)          # "às 9h" dito às 10h quer dizer amanhã
    return dt, ""


def rotulo(ctx, dt: datetime) -> str:
    """'hoje às 15:00', 'amanhã às 09:00', 'sex 20/11 às 16:00'."""
    loc = dt.astimezone(ctx.usuario.tz)
    hoje = ctx.agora.date()
    hh = loc.strftime("%H:%M")
    if loc.date() == hoje:
        return f"hoje às {hh}"
    if loc.date() == hoje + timedelta(days=1):
        return f"amanhã às {hh}"
    return f"{DIAS_CURTOS[loc.weekday()]} {loc.strftime('%d/%m')} às {hh}"


def do_banco(r: Any, padrao: str = "Não consegui fazer isso agora. Tente de novo.") -> Resultado:
    """Converte o jsonb {text, kb, rid, ...} das funcoes SQL em Resultado."""
    if not isinstance(r, dict):
        return Resultado(ok=False, erro=padrao)
    return Resultado(ok=True, texto=str(r.get("text") or padrao), kb=str(r.get("kb") or "none"), rid=r.get("rid") or 0, dados=r)


def minutos(lead: int | None) -> str:
    lm = int(lead or 0)
    if lm >= 1440 and lm % 1440 == 0:
        return f"{lm // 1440} dia(s)"
    if lm >= 60 and lm % 60 == 0:
        return f"{lm // 60}h"
    return f"{lm} min"


def fonte(ctx) -> str:
    return {"photo": "photo", "audio": "audio"}.get(ctx.fonte, "text")
