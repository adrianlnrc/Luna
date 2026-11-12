"""Interface do Google (Agenda e Tarefas) e implementacao em memoria para testes e uso local.

Formato de evento (o mesmo que as funcoes SQL de agenda esperam):
  {id, title, start, end, all_day, self_status, recurring_id, organizer, organizer_self, attendees, location}
start/end em ISO 8601 com fuso.
"""
from __future__ import annotations

import itertools
from datetime import datetime
from typing import Protocol


class ErroGoogle(Exception):
    """Falha ao falar com o Google. desconectado=True quando o usuario precisa reconectar."""

    def __init__(self, msg: str, desconectado: bool = False):
        super().__init__(msg)
        self.desconectado = desconectado


class Google(Protocol):
    async def conectado(self, user_id: int) -> bool: ...
    async def eventos(self, user_id: int, ini: datetime, fim: datetime) -> list[dict]: ...
    async def criar_evento(self, user_id: int, dados: dict) -> dict: ...
    async def atualizar_evento(self, user_id: int, event_id: str, start: str, end: str, avisar: bool) -> dict: ...
    async def apagar_evento(self, user_id: int, event_id: str, avisar: bool) -> dict: ...
    async def responder_convite(self, user_id: int, event_id: str, resposta: str) -> dict: ...
    async def tarefas(self, user_id: int, concluidas: bool = False) -> list[dict]: ...
    async def criar_tarefa(self, user_id: int, titulo: str, prazo: str | None = None, notas: str | None = None) -> dict: ...
    async def concluir_tarefa(self, user_id: int, task_id: str) -> dict: ...
    async def apagar_tarefa(self, user_id: int, task_id: str) -> dict: ...


def _dt(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


class GoogleFalso:
    """Agenda e tarefas em memoria, por usuario. Tambem serve para rodar o agente localmente sem conta Google."""

    def __init__(self) -> None:
        self._ev: dict[int, dict[str, dict]] = {}
        self._tf: dict[int, dict[str, dict]] = {}
        self._on: set[int] = set()
        self._seq = itertools.count(1)
        self.falhar: str = ""          # mensagem de erro a simular
        self.desconectar: bool = False
        self.chamadas: list[tuple] = []

    def conectar(self, user_id: int) -> None:
        self._on.add(user_id)

    def _checar(self, user_id: int) -> None:
        if self.desconectar or user_id not in self._on:
            raise ErroGoogle("agenda desconectada", desconectado=True)
        if self.falhar:
            raise ErroGoogle(self.falhar)

    async def conectado(self, user_id: int) -> bool:
        return user_id in self._on and not self.desconectar

    def por_evento(self, user_id: int, titulo: str, start: str, end: str, **extra) -> str:
        eid = extra.pop("id", None) or f"ev{next(self._seq)}"
        self._ev.setdefault(user_id, {})[eid] = {
            "id": eid, "title": titulo, "start": start, "end": end, "all_day": False, "self_status": "accepted",
            "recurring_id": "", "organizer": "", "organizer_self": True, "attendees": 0, "location": "", **extra}
        return eid

    async def eventos(self, user_id: int, ini: datetime, fim: datetime) -> list[dict]:
        self.chamadas.append(("eventos", user_id))
        self._checar(user_id)
        out = [e for e in self._ev.get(user_id, {}).values() if _dt(e["start"]) < fim and _dt(e["end"]) > ini]
        return sorted(out, key=lambda e: _dt(e["start"]))

    async def criar_evento(self, user_id: int, dados: dict) -> dict:
        self.chamadas.append(("criar_evento", user_id, dados))
        self._checar(user_id)
        conv = [c for c in str(dados.get("attendees") or "").split(",") if c.strip()]
        eid = self.por_evento(user_id, dados.get("summary") or "", dados["start"], dados["end"],
                              location=dados.get("location") or "", attendees=len(conv),
                              convidados=conv, repeat_freq=dados.get("repeat_freq") or "")
        meet = f"https://meet.google.com/fake-{eid}" if str(dados.get("meet")).lower() == "true" else ""
        return {"ok": True, "event_id": eid, "meet_link": meet, "html_link": f"https://calendar.google.com/event?eid={eid}"}

    async def atualizar_evento(self, user_id: int, event_id: str, start: str, end: str, avisar: bool) -> dict:
        self.chamadas.append(("atualizar_evento", user_id, event_id, start, end, avisar))
        self._checar(user_id)
        e = self._ev.get(user_id, {}).get(event_id)
        if not e:
            return {"ok": False, "error": "evento nao encontrado"}
        e["start"], e["end"] = start, end
        return {"ok": True, "event_id": event_id}

    async def apagar_evento(self, user_id: int, event_id: str, avisar: bool) -> dict:
        self.chamadas.append(("apagar_evento", user_id, event_id, avisar))
        self._checar(user_id)
        if self._ev.get(user_id, {}).pop(event_id, None) is None:
            return {"ok": False, "error": "evento nao encontrado"}
        return {"ok": True, "event_id": event_id}

    async def responder_convite(self, user_id: int, event_id: str, resposta: str) -> dict:
        self.chamadas.append(("responder_convite", user_id, event_id, resposta))
        self._checar(user_id)
        e = self._ev.get(user_id, {}).get(event_id)
        if not e:
            return {"ok": False, "error": "evento nao encontrado"}
        e["self_status"] = resposta
        return {"ok": True, "event_id": event_id}

    async def tarefas(self, user_id: int, concluidas: bool = False) -> list[dict]:
        self._checar(user_id)
        return [t for t in self._tf.get(user_id, {}).values() if concluidas or not t["done"]]

    async def criar_tarefa(self, user_id: int, titulo: str, prazo: str | None = None, notas: str | None = None) -> dict:
        self.chamadas.append(("criar_tarefa", user_id, titulo, prazo))
        self._checar(user_id)
        tid = f"tk{next(self._seq)}"
        self._tf.setdefault(user_id, {})[tid] = {"id": tid, "title": titulo, "due": prazo, "notes": notas or "", "done": False}
        return {"ok": True, "task_id": tid}

    async def concluir_tarefa(self, user_id: int, task_id: str) -> dict:
        self._checar(user_id)
        t = self._tf.get(user_id, {}).get(task_id)
        if not t:
            return {"ok": False, "error": "tarefa nao encontrada"}
        t["done"] = True
        return {"ok": True, "task_id": task_id}

    async def apagar_tarefa(self, user_id: int, task_id: str) -> dict:
        self._checar(user_id)
        if self._tf.get(user_id, {}).pop(task_id, None) is None:
            return {"ok": False, "error": "tarefa nao encontrada"}
        return {"ok": True, "task_id": task_id}
