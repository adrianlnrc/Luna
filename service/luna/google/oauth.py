"""Google por usuario (PRD RF-13): conexao por link, tokens cifrados, renovacao e revogacao.

O state e de uso unico (oauth_states). A chave de cifra (Fernet) vem do ambiente e nunca vai para o banco.
"""
from __future__ import annotations

import json
import secrets
from datetime import datetime, timedelta, timezone
from typing import TYPE_CHECKING
from urllib.parse import urlencode

import httpx
from cryptography.fernet import Fernet, InvalidToken

from .base import ErroGoogle

if TYPE_CHECKING:
    from ..db import Banco

ESCOPOS = ["https://www.googleapis.com/auth/calendar.events", "https://www.googleapis.com/auth/tasks"]
URL_AUTH = "https://accounts.google.com/o/oauth2/v2/auth"
URL_TOKEN = "https://oauth2.googleapis.com/token"
URL_REVOKE = "https://oauth2.googleapis.com/revoke"


class OAuthGoogle:
    def __init__(self, banco: "Banco", client_id: str, client_secret: str, public_url: str, chave: str,
                 cliente: httpx.AsyncClient | None = None):
        self._banco = banco
        self._id, self._secret = client_id, client_secret
        self._retorno = public_url.rstrip("/") + "/oauth/google/callback"
        self._fernet = Fernet(chave.encode() if isinstance(chave, str) else chave)
        self._http = cliente or httpx.AsyncClient(timeout=20.0)

    # ---------- cifra ----------
    def _cifrar(self, d: dict) -> str:
        return self._fernet.encrypt(json.dumps(d).encode()).decode()

    def _decifrar(self, s: str) -> dict:
        try:
            return json.loads(self._fernet.decrypt(s.encode()))
        except (InvalidToken, ValueError) as e:
            raise ErroGoogle("token ilegivel", desconectado=True) from e

    # ---------- conexao ----------
    async def link(self, user_id: int) -> str:
        state = secrets.token_urlsafe(32)
        async with self._banco.usuario(user_id) as cx:
            await cx.exec("INSERT INTO agente.oauth_states (state, user_id) VALUES (%s, %s)", state, user_id)
        return URL_AUTH + "?" + urlencode({
            "client_id": self._id, "redirect_uri": self._retorno, "response_type": "code", "scope": " ".join(ESCOPOS),
            "access_type": "offline", "prompt": "consent", "state": state})

    async def retorno(self, code: str, state: str) -> int | None:
        """Volta do Google. Devolve o usuario conectado, ou None se o state nao vale (reutilizado, vencido, inventado)."""
        async with self._banco.anonimo() as cx:
            user_id = await cx.fn("f_oauth_state_use", state)
        if not user_id:
            return None
        r = await self._http.post(URL_TOKEN, data={"code": code, "client_id": self._id, "client_secret": self._secret,
                                                   "redirect_uri": self._retorno, "grant_type": "authorization_code"})
        if r.status_code >= 400:
            raise ErroGoogle(f"o Google recusou a conexao (HTTP {r.status_code})")
        d = r.json()
        if not d.get("refresh_token"):
            raise ErroGoogle("o Google nao devolveu a autorizacao permanente; tente conectar de novo")
        await self._guardar(user_id, d["access_token"], d["refresh_token"], int(d.get("expires_in") or 3600), d.get("scope") or " ".join(ESCOPOS))
        return int(user_id)

    async def _guardar(self, user_id: int, access: str, refresh: str, expira_s: int, escopos: str, renovado: bool = False) -> None:
        cifrado = self._cifrar({"access_token": access, "refresh_token": refresh})
        expira = datetime.now(timezone.utc) + timedelta(seconds=max(expira_s - 60, 60))
        async with self._banco.usuario(user_id) as cx:
            await cx.exec(
                "INSERT INTO agente.oauth_tokens (user_id, provedor, escopos, token_cifrado, expira_em, renovado_em) "
                "VALUES (%s, 'google', %s, %s, %s, CASE WHEN %s THEN now() END) "
                "ON CONFLICT (user_id, provedor) DO UPDATE SET escopos = EXCLUDED.escopos, token_cifrado = EXCLUDED.token_cifrado, "
                "expira_em = EXCLUDED.expira_em, renovado_em = EXCLUDED.renovado_em, revogado_em = NULL",
                user_id, escopos, cifrado, expira, renovado)
            await cx.exec("UPDATE agente.users SET calendar_key = 'oauth' WHERE id = %s", user_id)

    async def conectado(self, user_id: int) -> bool:
        async with self._banco.usuario(user_id) as cx:
            return bool(await cx.valor("SELECT 1 FROM agente.oauth_tokens WHERE user_id = %s AND provedor = 'google' AND revogado_em IS NULL", user_id))

    # ---------- uso ----------
    async def token(self, user_id: int) -> str:
        """Access token valido do usuario; renova quando vence. Falha de renovacao desconecta (o usuario recebe o link de novo)."""
        async with self._banco.usuario(user_id) as cx:
            t = await cx.linha("SELECT token_cifrado, expira_em, escopos FROM agente.oauth_tokens "
                               "WHERE user_id = %s AND provedor = 'google' AND revogado_em IS NULL", user_id)
        if not t:
            raise ErroGoogle("agenda desconectada", desconectado=True)
        d = self._decifrar(t["token_cifrado"])
        if t["expira_em"] and t["expira_em"] > datetime.now(timezone.utc):
            return d["access_token"]
        r = await self._http.post(URL_TOKEN, data={"client_id": self._id, "client_secret": self._secret,
                                                   "refresh_token": d["refresh_token"], "grant_type": "refresh_token"})
        if r.status_code >= 400:
            await self._marcar_desconectado(user_id)
            raise ErroGoogle("a autorizacao do Google venceu", desconectado=True)
        n = r.json()
        await self._guardar(user_id, n["access_token"], n.get("refresh_token") or d["refresh_token"],
                            int(n.get("expires_in") or 3600), t["escopos"], renovado=True)
        return n["access_token"]

    async def _marcar_desconectado(self, user_id: int) -> None:
        async with self._banco.usuario(user_id) as cx:
            await cx.exec("UPDATE agente.oauth_tokens SET revogado_em = now() WHERE user_id = %s AND provedor = 'google'", user_id)
            await cx.exec("UPDATE agente.users SET calendar_key = NULL WHERE id = %s", user_id)

    async def desconectar(self, user_id: int) -> bool:
        """Revoga no Google e apaga os tokens."""
        async with self._banco.usuario(user_id) as cx:
            t = await cx.linha("SELECT token_cifrado FROM agente.oauth_tokens WHERE user_id = %s AND provedor = 'google'", user_id)
        if t:
            try:
                d = self._decifrar(t["token_cifrado"])
                await self._http.post(URL_REVOKE, data={"token": d.get("refresh_token") or d.get("access_token")})
            except Exception:
                pass   # mesmo sem resposta do Google, os tokens saem do nosso banco
        async with self._banco.usuario(user_id) as cx:
            await cx.exec("DELETE FROM agente.oauth_tokens WHERE user_id = %s AND provedor = 'google'", user_id)
            await cx.exec("UPDATE agente.users SET calendar_key = NULL WHERE id = %s", user_id)
        return bool(t)
