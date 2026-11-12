"""Configuracao lida do ambiente. Nenhum segredo fica no repositorio."""
from __future__ import annotations

import os
from dataclasses import dataclass, field


def _b(v: str | None, padrao: bool) -> bool:
    if v is None or v == "":
        return padrao
    return v.strip().lower() in ("1", "true", "sim", "yes", "on")


@dataclass
class Config:
    # banco: duas conexoes, uma por papel (db/041_rls.sql)
    db_app: str = "postgresql://luna_app@localhost/AgenteTelegram"
    db_sched: str = "postgresql://luna_sched@localhost/AgenteTelegram"
    redis_url: str = ""                       # vazio = estado em memoria (desenvolvimento e testes)
    # canal
    telegram_token: str = ""
    telegram_secret: str = ""                 # secret_token do webhook
    # IA
    openai_api_key: str = ""
    openai_base_url: str = "https://api.openai.com/v1"
    # busca na web (API propria do servico)
    busca_api_key: str = ""
    busca_url: str = "https://api.tavily.com/search"
    # Google
    google_client_id: str = ""
    google_client_secret: str = ""
    public_url: str = "http://localhost:8000"  # base para o retorno do OAuth
    token_key: str = ""                       # chave Fernet dos tokens do Google
    # chamada n8n -> servico (etapas 2 e 3)
    service_secret: str = ""
    # produto
    politica_versao: str = "1"
    politica_url: str = ""
    exige_convite: bool = True
    # limites do laco (PRD RF-03)
    max_passos: int = 5
    max_buscas: int = 2
    max_gravacoes: int = 5
    tempo_total_s: float = 45.0
    historico_turnos: int = 6
    historico_ttl_s: int = 1800

    @classmethod
    def do_ambiente(cls) -> "Config":
        e = os.environ.get
        c = cls()
        c.db_app = e("LUNA_DB_APP", c.db_app)
        c.db_sched = e("LUNA_DB_SCHED", c.db_sched)
        c.redis_url = e("LUNA_REDIS_URL", c.redis_url)
        c.telegram_token = e("LUNA_TELEGRAM_TOKEN", "")
        c.telegram_secret = e("LUNA_TELEGRAM_SECRET", "")
        c.openai_api_key = e("LUNA_OPENAI_API_KEY", "")
        c.openai_base_url = e("LUNA_OPENAI_BASE_URL", c.openai_base_url)
        c.busca_api_key = e("LUNA_BUSCA_API_KEY", "")
        c.busca_url = e("LUNA_BUSCA_URL", c.busca_url)
        c.google_client_id = e("LUNA_GOOGLE_CLIENT_ID", "")
        c.google_client_secret = e("LUNA_GOOGLE_CLIENT_SECRET", "")
        c.public_url = e("LUNA_PUBLIC_URL", c.public_url).rstrip("/")
        c.token_key = e("LUNA_TOKEN_KEY", "")
        c.service_secret = e("LUNA_SERVICE_SECRET", "")
        c.politica_versao = e("LUNA_POLITICA_VERSAO", c.politica_versao)
        c.politica_url = e("LUNA_POLITICA_URL", "")
        c.exige_convite = _b(e("LUNA_EXIGE_CONVITE"), True)
        return c
