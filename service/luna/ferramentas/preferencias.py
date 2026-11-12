"""Ferramenta preferencias: ajustes por frase (f_set_prefs), dose de avisos e revisao da semana."""
from __future__ import annotations

from ..tipos import Resultado
from .base import CONSULTA, CRIA, Acao, Ferramenta, S
from .util import hora_ok

DIAS = {"domingo": 0, "segunda": 1, "terca": 2, "quarta": 3, "quinta": 4, "sexta": 5, "sabado": 6}
NOMES = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]


async def _executar(ctx, acao: str, a: dict) -> Resultado:
    uid = ctx.uid
    async with ctx.cx() as cx:
        if acao == "ver":
            cmd = await cx.fn("f_command_data", uid)
            p = await cx.linha("SELECT modo, regras_silenciadas FROM agente.insight_prefs WHERE user_id = %s", uid)
            u = await cx.linha("SELECT revisao_dia, to_char(revisao_hora,'HH24:MI') AS h FROM agente.users WHERE id = %s", uid)
            t = str((cmd or {}).get("config") or "")
            t += f"\nAvisos do assessor: modo {(p or {}).get('modo') or 'normal'}."
            t += f"\nRevisão da semana: {NOMES[u['revisao_dia']]} às {u['h']}."
            return Resultado(texto=t.strip(), dados=cmd)
        if acao == "avisos":
            r = await cx.fn("f_insight_mode", uid, a.get("modo_avisos") or "")
            return Resultado(ok=bool((r or {}).get("ok")), texto=(r or {}).get("text") or "", erro=(r or {}).get("text") or "")
        if acao == "revisao_semanal":
            dia, hora = a.get("revisao_dia"), a.get("revisao_hora")
            if dia is None and not hora:
                return Resultado(ok=False, erro="diga o dia e/ou a hora da revisão da semana")
            if hora and not hora_ok(hora):
                return Resultado(ok=False, erro="hora inválida (HH:MM)")
            await cx.exec("UPDATE agente.users SET revisao_dia = coalesce(%s, revisao_dia), revisao_hora = coalesce(%s::time, revisao_hora) WHERE id = %s",
                          DIAS.get(dia) if dia else None, hora, uid)
            u = await cx.linha("SELECT revisao_dia, to_char(revisao_hora,'HH24:MI') AS h FROM agente.users WHERE id = %s", uid)
            return Resultado(texto=f"Combinado: revisão da semana {NOMES[u['revisao_dia']]} às {u['h']}.")
        # ajustar
        p = {"lead": a.get("aviso_antes_min"), "summary": a.get("resumo_manha"), "supply_days": a.get("estoque_avisar_dias"),
             "nickname": a.get("apelido"), "no_emoji": a.get("sem_emoji"), "timezone": a.get("fuso"),
             "evening": a.get("resumo_noite"), "work_start": a.get("expediente_inicio"), "work_end": a.get("expediente_fim")}
        p = {k: v for k, v in p.items() if v is not None}
        if not p:
            return Resultado(ok=False, erro="nenhum ajuste informado")
        r = await cx.fn("f_set_prefs", uid, p)
    return Resultado(texto=(r or {}).get("text") or "Não consegui salvar agora. Tente de novo.", dados=r)


FERRAMENTA = Ferramenta(
    nome="preferencias",
    descricao="Ajustes do usuário: apelido, emojis, fuso, resumos da manhã e do fim do dia, aviso padrão antes dos compromissos, "
              "expediente, quantidade de avisos do assessor e dia/hora da revisão da semana.",
    acoes={
        "ver": Acao("ver", CONSULTA, "mostra os ajustes atuais"),
        "ajustar": Acao("ajustar", CRIA, "muda ajustes que o usuário pediu"),
        "avisos": Acao("avisos", CRIA, "dose de avisos do assessor: quieto, normal, atento; ou 'todos' para religar avisos silenciados"),
        "revisao_semanal": Acao("revisao_semanal", CRIA, "dia e hora da revisão da semana"),
    },
    parametros={
        "apelido": S("string"),
        "sem_emoji": S("boolean"),
        "fuso": S("string", "ex.: America/Sao_Paulo"),
        "resumo_manha": S("string", "HH:MM, 'on' ou 'off'"),
        "resumo_noite": S("string", "HH:MM, 'on' ou 'off'"),
        "aviso_antes_min": S("integer", "aviso padrão antes dos compromissos, em minutos"),
        "estoque_avisar_dias": S("integer"),
        "expediente_inicio": S("string", "HH:MM"),
        "expediente_fim": S("string", "HH:MM"),
        "modo_avisos": S("string", "", ["quieto", "normal", "atento", "todos"]),
        "revisao_dia": S("string", "", list(DIAS.keys())),
        "revisao_hora": S("string", "HH:MM"),
    },
    executar=_executar,
)
