"""Google Agenda e Tarefas pela API REST, com o token de cada usuario."""
from __future__ import annotations

from datetime import datetime

import httpx

from .base import ErroGoogle
from .oauth import OAuthGoogle

CAL = "https://www.googleapis.com/calendar/v3/calendars/primary/events"
TAREFAS = "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks"
FREQ = {"daily": "DAILY", "weekly": "WEEKLY", "monthly": "MONTHLY"}


def _evento(e: dict) -> dict:
    ini, fim = e.get("start") or {}, e.get("end") or {}
    dia_todo = "date" in ini and "dateTime" not in ini
    conv = e.get("attendees") or []
    eu = next((a for a in conv if a.get("self")), None)
    meet = next((p.get("uri") for p in ((e.get("conferenceData") or {}).get("entryPoints") or []) if p.get("entryPointType") == "video"), "")
    return {
        "id": e.get("id"), "title": e.get("summary") or "(sem título)",
        "start": ini.get("dateTime") or (ini.get("date", "") + "T00:00:00+00:00"),
        "end": fim.get("dateTime") or (fim.get("date", "") + "T00:00:00+00:00"),
        "all_day": dia_todo, "self_status": (eu or {}).get("responseStatus") or "accepted",
        "recurring_id": e.get("recurringEventId") or "", "organizer": (e.get("organizer") or {}).get("email") or "",
        "organizer_self": bool((e.get("organizer") or {}).get("self")), "attendees": len(conv),
        "location": e.get("location") or "", "meet_link": meet or e.get("hangoutLink") or "",
    }


class GoogleHttp:
    def __init__(self, oauth: OAuthGoogle, cliente: httpx.AsyncClient | None = None):
        self._oauth = oauth
        self._http = cliente or httpx.AsyncClient(timeout=20.0)

    async def conectado(self, user_id: int) -> bool:
        return await self._oauth.conectado(user_id)

    async def _req(self, user_id: int, metodo: str, url: str, **kw) -> dict:
        token = await self._oauth.token(user_id)
        r = await self._http.request(metodo, url, headers={"Authorization": "Bearer " + token}, **kw)
        if r.status_code == 401:
            raise ErroGoogle("autorizacao recusada pelo Google", desconectado=True)
        if r.status_code >= 400:
            try:
                msg = (r.json().get("error") or {}).get("message") or r.text[:120]
            except ValueError:
                msg = r.text[:120]
            raise ErroGoogle(f"HTTP {r.status_code}: {msg}"[:140])
        return r.json() if r.content else {}

    # ---------- agenda ----------
    async def eventos(self, user_id: int, ini: datetime, fim: datetime) -> list[dict]:
        d = await self._req(user_id, "GET", CAL, params={"timeMin": ini.isoformat(), "timeMax": fim.isoformat(),
                                                         "singleEvents": "true", "orderBy": "startTime", "maxResults": "250"})
        return [_evento(e) for e in d.get("items") or [] if e.get("status") != "cancelled"]

    async def criar_evento(self, user_id: int, dados: dict) -> dict:
        corpo: dict = {"summary": dados.get("summary") or "", "start": {"dateTime": dados["start"]}, "end": {"dateTime": dados["end"]}}
        if dados.get("location"):
            corpo["location"] = dados["location"]
        conv = [c.strip() for c in str(dados.get("attendees") or "").split(",") if c.strip()]
        if conv:
            corpo["attendees"] = [{"email": c} for c in conv]
        freq = FREQ.get(dados.get("repeat_freq") or "")
        if freq:
            regra = "RRULE:FREQ=" + freq
            if dados.get("repeat_until"):
                regra += ";UNTIL=" + str(dados["repeat_until"]).replace("-", "") + "T235959Z"
            elif str(dados.get("repeat_count") or "").isdigit():
                regra += ";COUNT=" + str(dados["repeat_count"])
            corpo["recurrence"] = [regra]
        if dados.get("no_reminders"):
            corpo["reminders"] = {"useDefault": False, "overrides": []}
        params = {"sendUpdates": "all" if conv else "none"}
        if str(dados.get("meet")).lower() == "true":
            corpo["conferenceData"] = {"createRequest": {"requestId": f"luna-{user_id}-{abs(hash(dados['start'])) % 10**8}"}}
            params["conferenceDataVersion"] = "1"
        e = await self._req(user_id, "POST", CAL, params=params, json=corpo)
        ev = _evento(e)
        return {"ok": True, "event_id": ev["id"], "meet_link": ev["meet_link"], "html_link": e.get("htmlLink") or ""}

    async def atualizar_evento(self, user_id: int, event_id: str, start: str, end: str, avisar: bool) -> dict:
        await self._req(user_id, "PATCH", f"{CAL}/{event_id}", params={"sendUpdates": "all" if avisar else "none"},
                        json={"start": {"dateTime": start}, "end": {"dateTime": end}})
        return {"ok": True, "event_id": event_id}

    async def apagar_evento(self, user_id: int, event_id: str, avisar: bool) -> dict:
        await self._req(user_id, "DELETE", f"{CAL}/{event_id}", params={"sendUpdates": "all" if avisar else "none"})
        return {"ok": True, "event_id": event_id}

    async def responder_convite(self, user_id: int, event_id: str, resposta: str) -> dict:
        e = await self._req(user_id, "GET", f"{CAL}/{event_id}")
        conv = e.get("attendees") or []
        for a in conv:
            if a.get("self"):
                a["responseStatus"] = resposta
        await self._req(user_id, "PATCH", f"{CAL}/{event_id}", params={"sendUpdates": "all"}, json={"attendees": conv})
        return {"ok": True, "event_id": event_id}

    # ---------- tarefas ----------
    async def tarefas(self, user_id: int, concluidas: bool = False) -> list[dict]:
        d = await self._req(user_id, "GET", TAREFAS, params={"showCompleted": "true" if concluidas else "false",
                                                             "showHidden": "true" if concluidas else "false", "maxResults": "100"})
        return [{"id": t.get("id"), "title": t.get("title") or "", "due": (t.get("due") or "")[:10] or None,
                 "notes": t.get("notes") or "", "done": t.get("status") == "completed"} for t in d.get("items") or []]

    async def criar_tarefa(self, user_id: int, titulo: str, prazo: str | None = None, notas: str | None = None) -> dict:
        corpo: dict = {"title": titulo}
        if prazo:
            corpo["due"] = prazo + "T00:00:00.000Z"
        if notas:
            corpo["notes"] = notas
        t = await self._req(user_id, "POST", TAREFAS, json=corpo)
        return {"ok": True, "task_id": t.get("id")}

    async def concluir_tarefa(self, user_id: int, task_id: str) -> dict:
        await self._req(user_id, "PATCH", f"{TAREFAS}/{task_id}", json={"status": "completed"})
        return {"ok": True, "task_id": task_id}

    async def apagar_tarefa(self, user_id: int, task_id: str) -> dict:
        await self._req(user_id, "DELETE", f"{TAREFAS}/{task_id}")
        return {"ok": True, "task_id": task_id}
