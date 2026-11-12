"""Agendador (PRD RF-09): envios vencidos, resumos com o bloco "Atencao", avisos imediatos, revisao da semana,
convites recebidos e manutencao. Porta do workflow "Agente | Disparador" do n8n.

Usa o papel de servico do banco (enxerga todos os usuarios) so para descobrir quem tem algo a receber;
o trabalho de cada pessoa roda em nome dela.

ATENCAO: enquanto o Disparador do n8n estiver ligado, nao ligue este agendador para os mesmos usuarios
(as duas pontas enviariam o mesmo lembrete).
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta
from typing import TYPE_CHECKING
from zoneinfo import ZoneInfo

from .agente import laco
from .google.base import ErroGoogle
from .tipos import Botao, Saida, Usuario

if TYPE_CHECKING:
    from .nucleo import Nucleo

log = logging.getLogger("luna.agendador")


def _brl(v) -> str:
    s = f"{float(v):,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return "R$ " + s


def botoes_aviso(aviso: dict) -> list[list[Botao]]:
    linha = []
    if aviso.get("acao"):
        linha.append(Botao(str((aviso["acao"] or {}).get("rotulo") or "Fazer")[:24], f"in:{aviso['id']}:ok"))
    linha.append(Botao("Agora não", f"in:{aviso['id']}:dp"))
    return [linha, [Botao("Não me avise mais disso", f"in:{aviso['id']}:mu")]]


class Agendador:
    def __init__(self, nucleo: "Nucleo"):
        self.n = nucleo

    async def _eventos(self, uid: int, ini: datetime, fim: datetime) -> list[dict]:
        try:
            if await self.n.google.conectado(uid):
                return await self.n.google.eventos(uid, ini, fim)
        except ErroGoogle:
            pass
        except Exception:
            log.exception("eventos")
        return []

    # ---------- 1) lembretes, pre-avisos, doses e estoque ----------
    async def envios(self) -> int:
        async with self.n.banco.servico() as cx:
            lista = await cx.fn("f_claim_due") or []
        for x in lista:
            t, b = "", []
            tipo = x.get("type")
            if tipo == "reminder":
                t = f"Lembrete: {x.get('title')} ({x.get('due')})"
            elif tipo == "repeat":
                t = f"Ainda pendente: {x.get('title')} ({x.get('due')})"
            elif tipo == "pre_alert":
                t = f"Daqui a {x.get('offset_minutes')} min: {x.get('title')} ({x.get('due')})"
            elif tipo == "dose":
                t = f"Hora de tomar: {x.get('item')}"
                b = [[Botao("Tomei", f"took:{x.get('dose_id') or 0}"), Botao("Pular hoje", f"skipd:{x.get('dose_id') or 0}")]]
            elif tipo == "supply":
                t = f"Sua {x.get('item')} acaba em {x.get('days_left')} dia(s). Quer que eu lembre de comprar?"
                b = [[Botao("Comprei", f"bought:{x.get('supply_id') or 0}"), Botao("Lembrar amanhã", f"later:{x.get('supply_id') or 0}")]]
            if tipo in ("reminder", "repeat"):
                rid = x.get("reminder_id") or 0
                b = [[Botao("Feito", f"done:{rid}"), Botao("Adiar 1h", f"snz1h:{rid}"), Botao("Adiar amanhã", f"snzt:{rid}")]]
            if t:
                await self.n.canal.enviar(str(x["chat_id"]), Saida(t, b))
        return len(lista)

    # ---------- 2) resumos da manha e do fim do dia ----------
    async def resumos(self) -> int:
        async with self.n.banco.servico() as cx:
            cand = await cx.fn("f_summary_candidates") or []
        for u in cand:
            try:
                for s in await self.montar_resumo(u):
                    await self.n.canal.enviar(str(u["chat_id"]), s)
            except Exception:
                log.exception("resumo do usuario %s", u.get("user_id"))
        return len(cand)

    async def montar_resumo(self, u: dict) -> list[Saida]:
        uid, noite = int(u["user_id"]), u.get("kind") == "evening"
        tz = ZoneInfo(u.get("timezone") or "America/Sao_Paulo")
        hoje = self.n.agora().astimezone(tz).replace(hour=0, minute=0, second=0, microsecond=0)
        base = hoje + timedelta(days=1) if noite else hoje
        eventos = await self._eventos(uid, base, base + timedelta(days=1))
        tarefas: list[dict] = []
        try:
            if await self.n.google.conectado(uid):
                tarefas = await self.n.google.tarefas(uid)
        except Exception:
            tarefas = []
        async with self.n.banco.usuario(uid) as cx:
            if not noite:   # tarefas agendadas pela importacao de agenda que vencem hoje viram tarefas no Google
                due = (await cx.fn("f_agimp_tasks_due", uid) or {}).get("items") or []
                feitas = []
                for it in due:
                    try:
                        if (await self.n.google.criar_tarefa(uid, it["title"], it.get("due"))).get("ok"):
                            feitas.append(it["id"])
                            tarefas.append({"title": it["title"], "due": it.get("due")})
                    except Exception:
                        pass
                if feitas:
                    await cx.fn("f_agimp_tasks_mark", uid, feitas)
            d = await cx.fn("f_summary_data", uid) or {}
            pj = await cx.linhas(
                "SELECT t.title, to_char(t.due_date,'YYYY-MM-DD') AS due, p.name AS project FROM agente.project_tasks t "
                "JOIN agente.projects p ON p.id = t.project_id WHERE t.user_id = %s AND NOT t.done AND t.google_task_id IS NULL", uid)
            dica = await cx.fn("f_tip", uid)
            novo = await cx.valor("SELECT created_at > now() - interval '21 days' FROM agente.users WHERE id = %s", uid)
            await cx.fn("f_insights_expire", uid)
            await cx.fn("f_runs_expire", uid)
        tarefas = tarefas + [dict(x) for x in pj]
        hoje_iso, amanha_iso = hoje.strftime("%Y-%m-%d"), (hoje + timedelta(days=1)).strftime("%Y-%m-%d")
        nome_t = lambda t: f"{t['title']} ({t['project']})" if t.get("project") else t["title"]
        linhas_ev = []
        for e in eventos:
            qd = "dia todo" if e.get("all_day") else datetime.fromisoformat(e["start"].replace("Z", "+00:00")).astimezone(tz).strftime("%H:%M")
            linhas_ev.append(f"- {qd}  {e['title']}" + (f" ({e['location']})" if e.get("location") else ""))
        atras = sum(1 for t in tarefas if t.get("due") and t["due"] < hoje_iso)
        sem_prazo = sum(1 for t in tarefas if not t.get("due"))
        contas = []
        for b in d.get("bills") or []:
            qd = (f"ATRASADA desde {b['due']}" if b.get("late") else "vence hoje" if b.get("today")
                  else "vence amanhã" if b.get("tomorrow") else f"vence {b['due']}")
            contas.append((b, f"- {b['description']} {_brl(b['amount'])} {qd}"))
        partes: list[str] = []
        if noite:
            partes.append(f"Boa noite, {u['name']}! Fechando o dia ({hoje.strftime('%d/%m')}):")
            pend = [f"- Tarefa: {nome_t(t)}" for t in tarefas if t.get("due") == hoje_iso]
            if atras:
                pend.append(f"- {atras} tarefa{'s' if atras > 1 else ''} atrasada{'s' if atras > 1 else ''} (diga minhas tarefas para ver)")
            pend += [f"- Lembrete das {r['time']}: {r['title']}" for r in d.get("overdue_today") or []]
            pend += [l for b, l in contas if b.get("late") or b.get("today")]
            partes.append("Pendências de hoje:\n" + "\n".join(pend) + '\n(diga "já paguei" ou "feito" para dar baixa)' if pend else "Hoje ficou tudo em dia.")
            partes.append(f"Amanhã ({base.strftime('%d/%m')}):")
            partes.append("Compromissos:\n" + "\n".join(linhas_ev) if linhas_ev else "Compromissos: nenhum.")
            ta = [f"- {nome_t(t)}" for t in tarefas if t.get("due") == amanha_iso]
            if ta:
                partes.append("Tarefas:\n" + "\n".join(ta))
            la = [f"- {r['time']}  {r['title']}" for r in d.get("tomorrow_reminders") or []]
            partes.append("Lembretes:\n" + "\n".join(la) if la else "Lembretes: nenhum.")
            ca = [l for b, l in contas if b.get("tomorrow")]
            if ca:
                partes.append("Contas a pagar amanhã:\n" + "\n".join(ca))
        else:
            partes.append(f"Bom dia, {u['name']}! Seu dia ({base.strftime('%d/%m')}):")
            partes.append("Compromissos:\n" + "\n".join(linhas_ev) if linhas_ev else "Compromissos: nenhum.")
            lt = [f"- {nome_t(t)}" for t in tarefas if t.get("due") == hoje_iso]
            cont = []
            if atras:
                cont.append(f"{atras} atrasada{'s' if atras > 1 else ''}")
            if sem_prazo:
                cont.append(f"{sem_prazo} sem prazo")
            if cont:
                lt.append("- e " + " e ".join(cont) + " (diga minhas tarefas para ver)")
            partes.append("Tarefas:\n" + "\n".join(lt) if lt else "Tarefas: nenhuma.")
            lem = [f"- {r['time']}  {r['title']}" for r in d.get("today_reminders") or []]
            partes.append("Lembretes:\n" + "\n".join(lem) if lem else "Lembretes: nenhum.")
            if contas:
                partes.append("Contas a pagar:\n" + "\n".join(l for _, l in contas) + '\n  (diga "já paguei" quando quitar)')
            din = []
            if d.get("yesterday_spent"):
                din.append(f"- Ontem você gastou {_brl(d['yesterday_spent'])}")
            for b in d.get("budget_alerts") or []:
                din.append(f"- {b['name']} passou do orçamento ({_brl(b['spent'])} de {_brl(b['budget'])})" if b["pct"] >= 100
                           else f"- {b['name']} em {b['pct']}% do orçamento ({_brl(b['spent'])} de {_brl(b['budget'])})")
            if din:
                partes.append("Dinheiro:\n" + "\n".join(din))
            est = [f"{s['item']} (restam {round(float(s['units_left']))})" for s in d.get("supplies") or []]
            if est:
                partes.append("Hora de comprar: " + ", ".join(est) + ' (diga "comprei" quando comprar)')
        extras = str(d.get("extras_text") or "")
        if dica and not novo:   # a dica de uso so aparece nas primeiras 3 semanas de cada pessoa (PRD RF-09)
            extras = extras.replace(str(dica), "").strip()
        if extras:
            partes.append(extras)
        saidas = [Saida("\n\n".join(partes))]
        if not noite:           # bloco "Atencao": o canal principal do Vigia, sem mensagem nova por dia
            saidas += await self.avisos(uid, "resumo", tz)
        return saidas

    # ---------- 3) Vigia ----------
    async def avisos(self, uid: int, via: str, tz: ZoneInfo | None = None) -> list[Saida]:
        tz = tz or ZoneInfo("America/Sao_Paulo")
        agora = self.n.agora().astimezone(tz)
        eventos = await self._eventos(uid, agora - timedelta(hours=1), agora + timedelta(days=8))
        async with self.n.banco.usuario(uid) as cx:
            escolhidos = await cx.fn("f_insights_pick", uid, eventos, via) or []
        saidas = []
        for i, a in enumerate(escolhidos):
            cab = "Atenção: " if via == "resumo" else "Aviso: "
            saidas.append(Saida(cab + a["texto"], botoes_aviso(a)))
        return saidas

    async def imediatos(self) -> int:
        """Avisos que perdem valor se esperarem ate amanha. O teto por dia e o expediente sao checados no banco."""
        async with self.n.banco.servico() as cx:
            us = await cx.linhas("SELECT id, telegram_id, timezone FROM agente.users WHERE onboarding_step = 'done' AND status = 'ativo'")
        n = 0
        for u in us:
            try:
                for s in await self.avisos(u["id"], "imediato", ZoneInfo(u["timezone"])):
                    await self.n.canal.enviar(str(u["telegram_id"]), s)
                    n += 1
            except Exception:
                log.exception("imediato do usuario %s", u["id"])
        return n

    # ---------- 4) revisao da semana ----------
    async def revisoes(self) -> int:
        async with self.n.banco.servico() as cx:
            us = await cx.linhas(
                "UPDATE agente.users u SET last_review_on = (now() AT TIME ZONE u.timezone)::date "
                "WHERE u.onboarding_step = 'done' AND u.status = 'ativo' "
                "AND extract(dow FROM now() AT TIME ZONE u.timezone)::int = u.revisao_dia "
                "AND (now() AT TIME ZONE u.timezone)::time >= u.revisao_hora "
                "AND (now() AT TIME ZONE u.timezone)::time < u.revisao_hora + interval '30 minutes' "
                "AND u.last_review_on IS DISTINCT FROM (now() AT TIME ZONE u.timezone)::date "
                "AND agente.f_consent_ok(u.id, 'politica') RETURNING u.id, u.telegram_id")
        for row in us:
            try:
                for s in await self.revisao(row["id"]):
                    await self.n.canal.enviar(str(row["telegram_id"]), s)
            except Exception:
                log.exception("revisao do usuario %s", row["id"])
        return len(us)

    async def revisao(self, uid: int) -> list[Saida]:
        """Unica iniciativa feita pelo agente: olha a semana que vem cruzando agenda, dinheiro e prazos. So propoe."""
        u = await self.n.usuario(uid)
        if not u:
            return []
        agora = self.n.agora().astimezone(u.tz)
        eventos = await self._eventos(uid, agora, agora + timedelta(days=8))
        async with self.n.banco.usuario(uid) as cx:
            sinais = await cx.fn("f_insights_pick", uid, eventos, "revisao") or []
            recusas = await cx.fn("f_refusal_pattern", uid) or []
        pedido = ("REVISÃO DA SEMANA (iniciativa sua, o usuário não pediu agora). Olhe os próximos 7 dias: chame `retrato` e `agenda` "
                  "e escreva um resumo curto do que merece atenção, cruzando compromissos, dinheiro e prazos. "
                  "No máximo 3 pontos, do mais importante para o menos. Se algo pedir ação, proponha (vira botão de confirmar). "
                  "Se a semana estiver tranquila, diga isso em uma linha.")
        if sinais:
            pedido += "\n\nSinais que as regras do Vigia já encontraram:\n" + "\n".join("- " + s["texto"] for s in sinais)
        if recusas:
            pedido += ("\n\nPadrão de recusas: o usuário recusou várias propostas parecidas ("
                       + "; ".join(f"{r['ferramenta']}.{r['acao']}: {r['recusas']}x" for r in recusas)
                       + "). Se enxergar um critério claro por trás, proponha anotá-lo com memoria.criterio_sugerido.")
        r = await laco.executar(self.n, u, pedido, origem="revisao", usar_historico=False)
        if r.erro:
            return []
        r.saidas[0].texto = "Revisão da semana\n\n" + r.saidas[0].texto
        return r.saidas

    # ---------- 5) convites recebidos ----------
    async def convites(self) -> int:
        async with self.n.banco.servico() as cx:
            us = await cx.linhas("SELECT id, telegram_id, calendar_key FROM agente.users "
                                 "WHERE onboarding_step = 'done' AND status = 'ativo' AND coalesce(calendar_key, '') <> ''")
        n = 0
        for u in us:
            agora = self.n.agora()
            try:
                evs = await self.n.google.eventos(u["id"], agora, agora + timedelta(days=30))
            except Exception:
                continue
            async with self.n.banco.usuario(u["id"]) as cx:
                msgs = await cx.fn("f_agenda_invites", u["id"], u["calendar_key"], evs) or []
            for m in msgs if isinstance(msgs, list) else []:
                if m and m.get("text"):
                    rid = m.get("rid") or 0
                    await self.n.canal.enviar(str(u["telegram_id"]), Saida(m["text"], [[Botao("Aceitar", f"agrs:{rid}"), Botao("Recusar", f"agrn:{rid}")]]))
                    n += 1
        return n

    # ---------- laco ----------
    async def rodar(self, parar: asyncio.Event | None = None) -> None:
        """Um tique por minuto. Cada tarefa falha sozinha, sem derrubar as outras."""
        minuto = 0
        while not (parar and parar.is_set()):
            for nome, fn, cada in (("envios", self.envios, 1), ("resumos", self.resumos, 1), ("revisoes", self.revisoes, 5),
                                   ("imediatos", self.imediatos, 10), ("convites", self.convites, 15)):
                if minuto % cada == 0:
                    try:
                        await fn()
                    except Exception:
                        log.exception("agendador: %s", nome)
            minuto += 1
            try:
                await asyncio.wait_for(parar.wait(), 60) if parar else await asyncio.sleep(60)
            except asyncio.TimeoutError:
                pass
