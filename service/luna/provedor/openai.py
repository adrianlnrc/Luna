"""Provedor OpenAI (API de chat com ferramentas). Primeira implementacao da interface; trocar de provedor nao toca o agente."""
from __future__ import annotations

import base64
import json

import httpx

from .base import Chamada, RespostaModelo, Turno


class ErroProvedor(Exception):
    pass


class ProvedorOpenAI:
    nome = "openai"

    def __init__(self, api_key: str, base_url: str = "https://api.openai.com/v1",
                 cliente: httpx.AsyncClient | None = None, timeout: float = 40.0):
        self._key = api_key
        self._base = base_url.rstrip("/")
        self._http = cliente or httpx.AsyncClient(timeout=timeout)

    def _msg(self, t: Turno) -> dict:
        if t.papel == "sistema":
            return {"role": "system", "content": t.texto}
        if t.papel == "ferramenta":
            return {"role": "tool", "tool_call_id": t.chamada_id, "content": t.texto}
        if t.papel == "assistente":
            m: dict = {"role": "assistant", "content": t.texto or None}
            if t.chamadas:
                m["tool_calls"] = [{"id": c.id, "type": "function",
                                    "function": {"name": c.nome, "arguments": json.dumps(c.args, ensure_ascii=False)}}
                                   for c in t.chamadas]
            return m
        if t.imagens:
            partes: list[dict] = [{"type": "text", "text": t.texto or ""}]
            for dados, mime in t.imagens:
                b64 = base64.b64encode(dados).decode()
                partes.append({"type": "image_url", "image_url": {"url": f"data:{mime or 'image/jpeg'};base64,{b64}"}})
            return {"role": "user", "content": partes}
        return {"role": "user", "content": t.texto}

    async def responder(self, turnos: list[Turno], ferramentas: list[dict], modelo: str,
                        esquema: dict | None = None) -> RespostaModelo:
        corpo: dict = {"model": modelo, "messages": [self._msg(t) for t in turnos]}
        if ferramentas:
            corpo["tools"] = [{"type": "function", "function": {"name": f["name"], "description": f["description"],
                                                                 "parameters": f["parameters"], "strict": True}}
                              for f in ferramentas]
        if esquema:
            corpo["response_format"] = {"type": "json_schema",
                                        "json_schema": {"name": "saida", "strict": True, "schema": esquema}}
        try:
            r = await self._http.post(self._base + "/chat/completions", json=corpo,
                                      headers={"Authorization": "Bearer " + self._key})
        except httpx.HTTPError as e:
            raise ErroProvedor(f"falha de rede: {type(e).__name__}") from e
        if r.status_code >= 400:
            raise ErroProvedor(f"HTTP {r.status_code}: {r.text[:200]}")
        d = r.json()
        msg = (d.get("choices") or [{}])[0].get("message") or {}
        chamadas = []
        for tc in msg.get("tool_calls") or []:
            fn = tc.get("function") or {}
            try:
                args = json.loads(fn.get("arguments") or "{}")
            except json.JSONDecodeError:
                args = {}
            chamadas.append(Chamada(id=tc.get("id") or "", nome=fn.get("name") or "", args=args if isinstance(args, dict) else {}))
        uso = d.get("usage") or {}
        texto = msg.get("content") or ""
        estimado = not uso
        return RespostaModelo(
            texto=texto, chamadas=chamadas, modelo=d.get("model") or modelo, estimado=estimado,
            tokens_in=int(uso.get("prompt_tokens") or len(json.dumps(corpo)) // 4),
            tokens_out=int(uso.get("completion_tokens") or len(json.dumps(msg)) // 4))

    async def transcrever(self, audio: bytes, nome: str, modelo: str) -> tuple[str, int]:
        try:
            r = await self._http.post(self._base + "/audio/transcriptions",
                                      headers={"Authorization": "Bearer " + self._key},
                                      data={"model": modelo, "language": "pt"},
                                      files={"file": (nome or "audio.ogg", audio)})
        except httpx.HTTPError as e:
            raise ErroProvedor(f"falha de rede: {type(e).__name__}") from e
        if r.status_code >= 400:
            raise ErroProvedor(f"HTTP {r.status_code}: {r.text[:200]}")
        d = r.json()
        return str(d.get("text") or "").strip(), int(d.get("duration") or 0)
