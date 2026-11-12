"""Canal Telegram. Unico lugar do servico que fala a API do Telegram."""
from __future__ import annotations

import httpx

from ..tipos import Arquivo, Botao, Mensagem, Saida

LIMITE_TEXTO = 3900


class CanalTelegram:
    nome = "telegram"

    def __init__(self, token: str, cliente: httpx.AsyncClient | None = None):
        self._token = token
        self._http = cliente or httpx.AsyncClient(timeout=30.0)
        self._api = f"https://api.telegram.org/bot{token}"
        self._file = f"https://api.telegram.org/file/bot{token}"

    # ---------- entrada ----------
    def receber(self, bruto: dict) -> Mensagem | None:
        uid = str(bruto.get("update_id") or "")
        cb = bruto.get("callback_query")
        if cb:
            de = cb.get("from") or {}
            m = cb.get("message") or {}
            return Mensagem(canal=self.nome, id_externo=str(de.get("id") or ""), chat_id=str((m.get("chat") or {}).get("id") or de.get("id") or ""),
                            tipo="botao", acao_id=str(cb.get("data") or ""), msg_id=str(m.get("message_id") or ""),
                            update_id=uid, nome_exibicao=str(de.get("first_name") or ""))
        m = bruto.get("message")
        if not m:
            return None
        de = m.get("from") or {}
        chat = m.get("chat") or {}
        if chat.get("type") not in (None, "private"):
            return None                      # o assessor so conversa em chat privado
        base = dict(canal=self.nome, id_externo=str(de.get("id") or ""), chat_id=str(chat.get("id") or ""),
                    update_id=uid, msg_id=str(m.get("message_id") or ""), nome_exibicao=str(de.get("first_name") or ""),
                    grupo_midia=str(m.get("media_group_id") or ""))
        legenda = str(m.get("caption") or "")
        if m.get("text") is not None:
            t = str(m["text"])
            return Mensagem(tipo="comando" if t.startswith("/") else "texto", texto=t, **base)
        if m.get("voice") or m.get("audio"):
            a = m.get("voice") or m.get("audio")
            return Mensagem(tipo="audio", texto=legenda,
                            arquivo=Arquivo(a["file_id"], "audio", a.get("mime_type") or "audio/ogg", a.get("file_name") or "audio.ogg", int(a.get("file_size") or 0)), **base)
        if m.get("photo"):
            p = max(m["photo"], key=lambda x: x.get("file_size") or 0)
            return Mensagem(tipo="foto", texto=legenda,
                            arquivo=Arquivo(p["file_id"], "photo", "image/jpeg", "foto.jpg", int(p.get("file_size") or 0)), **base)
        for chave, tipo in (("document", "document"), ("video", "video")):
            if m.get(chave):
                d = m[chave]
                return Mensagem(tipo="documento", texto=legenda,
                                arquivo=Arquivo(d["file_id"], tipo, d.get("mime_type") or "", d.get("file_name") or "", int(d.get("file_size") or 0)), **base)
        return None

    # ---------- saida ----------
    async def _post(self, metodo: str, **dados) -> dict:
        r = await self._http.post(f"{self._api}/{metodo}", json=dados)
        try:
            return r.json()
        except ValueError:
            return {"ok": False, "description": r.text[:200]}

    @staticmethod
    def _teclado(botoes: list[list[Botao]]) -> dict | None:
        if not botoes:
            return None
        return {"inline_keyboard": [[{"text": b.rotulo, "callback_data": b.acao_id[:64]} for b in linha] for linha in botoes]}

    async def enviar(self, chat_id: str, saida: Saida) -> str:
        texto = saida.texto if len(saida.texto) <= LIMITE_TEXTO else saida.texto[:LIMITE_TEXTO] + "..."
        teclado = self._teclado(saida.botoes)
        if saida.anexo:
            nome, dados, mime = saida.anexo
            r = await self._http.post(f"{self._api}/sendDocument", data={"chat_id": chat_id, "caption": texto[:1000]},
                                      files={"document": (nome, dados, mime)})
            d = r.json()
        elif saida.arquivo:
            metodo, campo = {"photo": ("sendPhoto", "photo"), "video": ("sendVideo", "video"),
                             "audio": ("sendAudio", "audio")}.get(saida.arquivo.tipo, ("sendDocument", "document"))
            dados = {"chat_id": chat_id, campo: saida.arquivo.file_id, "caption": texto[:1000]}
            if teclado:
                dados["reply_markup"] = teclado
            d = await self._post(metodo, **dados)
        else:
            dados = {"chat_id": chat_id, "text": texto or "Ok."}
            if teclado:
                dados["reply_markup"] = teclado
            d = await self._post("sendMessage", **dados)
        return str(((d or {}).get("result") or {}).get("message_id") or "")

    async def indicar_digitando(self, chat_id: str) -> None:
        await self._post("sendChatAction", chat_id=chat_id, action="typing")

    async def baixar(self, arquivo: Arquivo) -> bytes:
        d = await self._post("getFile", file_id=arquivo.file_id)
        caminho = ((d or {}).get("result") or {}).get("file_path")
        if not caminho:
            return b""
        r = await self._http.get(f"{self._file}/{caminho}")
        return r.content if r.status_code == 200 else b""

    async def encerrar_botoes(self, chat_id: str, msg_id: str) -> None:
        if msg_id:
            await self._post("editMessageReplyMarkup", chat_id=chat_id, message_id=int(msg_id), reply_markup={"inline_keyboard": []})

    async def responder_clique(self, callback_id: str) -> None:
        await self._post("answerCallbackQuery", callback_query_id=callback_id)
