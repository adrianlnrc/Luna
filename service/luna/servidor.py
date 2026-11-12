"""Servidor HTTP (FastAPI).

  POST /telegram/webhook      entrada do Telegram (valida o secret_token, enfileira e responde 200)
  POST /v1/assessor           chamada do n8n nas etapas 2 e 3: o servico so le e devolve propostas
  GET  /oauth/google/callback retorno da conexao com o Google
  GET  /health
"""
from __future__ import annotations

import asyncio
import hmac
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

from .agendador import Agendador
from .agente import laco
from .app import Luna
from .config import Config
from .fabrica import montar
from .nucleo import Nucleo
from .tipos import Saida

log = logging.getLogger("luna")
FILA = "entrada"


class PedidoAssessor(BaseModel):
    user_id: int
    mensagem: str
    agenda: list[dict] | None = None     # compromissos do periodo, lidos pelo n8n (a agenda ainda mora la)


def criar_app(nucleo: Nucleo | None = None, com_agendador: bool = True) -> FastAPI:
    cfg = nucleo.cfg if nucleo else Config.do_ambiente()
    n = nucleo or montar(cfg)
    luna = Luna(n)
    parar = asyncio.Event()

    async def trabalhador() -> None:
        """Tira da fila e processa. O item so sai da lista de processamento depois de concluido."""
        await n.estado.recuperar(FILA)      # o que ficou pela metade num reinicio volta para a fila
        while not parar.is_set():
            bruto = await n.estado.desenfileirar(FILA, 1.0)
            if bruto is None:
                continue

            async def um(b=bruto):
                try:
                    m = n.canal.receber(b)
                    if m:
                        await luna.receber(m)
                except Exception:
                    log.exception("trabalhador")
                finally:
                    await n.estado.confirmar(FILA, b)
            asyncio.create_task(um())       # a ordem por pessoa e garantida pela trava em Luna.receber

    @asynccontextmanager
    async def vida(app: FastAPI):
        await n.banco.abrir()
        tarefas = [asyncio.create_task(trabalhador())]
        if com_agendador:
            tarefas.append(asyncio.create_task(Agendador(n).rodar(parar)))
        yield
        parar.set()
        for t in tarefas:
            t.cancel()
        await n.banco.fechar()

    app = FastAPI(title="Luna Assessor", lifespan=vida)
    app.state.nucleo, app.state.luna = n, luna

    @app.get("/health")
    async def health():
        return {"ok": True}

    @app.post("/telegram/webhook")
    async def webhook(req: Request, x_telegram_bot_api_secret_token: str | None = Header(default=None)):
        if not cfg.telegram_secret or not hmac.compare_digest(x_telegram_bot_api_secret_token or "", cfg.telegram_secret):
            raise HTTPException(401, "secret invalido")
        await n.estado.enfileirar(FILA, await req.json())
        return {"ok": True}

    @app.post("/v1/assessor")
    async def assessor(p: PedidoAssessor, x_luna_secret: str | None = Header(default=None)):
        """Etapas 2 e 3: o n8n recebe o Telegram e chama aqui so na intencao `assessor`.
        O servico roda como origem 'revisao' de escrita: nada grava; toda acao volta como proposta."""
        if not cfg.service_secret or not hmac.compare_digest(x_luna_secret or "", cfg.service_secret):
            raise HTTPException(401, "segredo invalido")
        u = await n.usuario(p.user_id)
        if not u or u.status != "ativo":
            raise HTTPException(404, "usuario")
        if p.agenda is not None and hasattr(n.google, "por_evento"):
            n.google.conectar(u.id)
            n.google._ev[u.id] = {str(e.get("id")): e for e in p.agenda}
        r = await laco.executar(n, u, p.mensagem, origem="pergunta", canal="n8n", so_propor=True)
        async with n.banco.usuario(u.id) as cx:
            props = await cx.linhas("SELECT id, ferramenta, acao, args, resumo FROM agente.pending_actions WHERE run_id = %s ORDER BY id", r.run_id)
        return {"texto": r.saidas[0].texto if r.saidas else "", "run_id": r.run_id, "custo_brl": r.custo_brl,
                "passos": r.passos, "ferramentas": r.usadas, "propostas": props, "limite": r.limite}

    @app.get("/oauth/google/callback", response_class=HTMLResponse)
    async def oauth(code: str = "", state: str = "", error: str = ""):
        if not n.oauth:
            raise HTTPException(404)
        if error or not code or not state:
            return HTMLResponse("<p>Conexão cancelada. Pode fechar esta página e pedir o link de novo no chat.</p>", 400)
        try:
            uid = await n.oauth.retorno(code, state)
        except Exception as e:
            log.warning("oauth: %s", e)
            return HTMLResponse("<p>Não consegui concluir a conexão. Peça um novo link no chat.</p>", 400)
        if not uid:
            return HTMLResponse("<p>Este link já foi usado ou expirou. Peça um novo no chat com /conectar.</p>", 400)
        async with n.banco.servico() as cx:
            chat = await cx.valor("SELECT telegram_id FROM agente.users WHERE id = %s", uid)
        try:
            await n.canal.enviar(str(chat), Saida("Google conectado! Já posso ver e marcar seus compromissos. Tente: \"o que tenho amanhã?\""))
        except Exception:
            pass
        return HTMLResponse("<p>Pronto! Sua agenda está conectada. Pode voltar para o chat.</p>")

    return app


def app() -> FastAPI:   # uvicorn luna.servidor:app --factory
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    return criar_app()
