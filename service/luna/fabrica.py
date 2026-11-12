"""Monta o Nucleo a partir da configuracao. O que nao estiver configurado cai na versao em memoria,
para o servico subir localmente sem nenhuma conta externa."""
from __future__ import annotations

import logging

from .busca import BuscaFalsa, BuscaHttp
from .canais.memoria import CanalMemoria
from .canais.telegram import CanalTelegram
from .config import Config
from .db import Banco
from .estado import EstadoMemoria, EstadoRedis
from .ferramentas import montar_registro
from .google.base import GoogleFalso
from .nucleo import Nucleo

log = logging.getLogger("luna")


def montar(cfg: Config, provedor=None, canal=None) -> Nucleo:
    banco = Banco(cfg.db_app, cfg.db_sched)
    if provedor is None:
        if cfg.openai_api_key:
            from .provedor.openai import ProvedorOpenAI
            provedor = ProvedorOpenAI(cfg.openai_api_key, cfg.openai_base_url)
        else:
            from .provedor.regras import ProvedorRegras
            provedor = ProvedorRegras()
            log.warning("sem LUNA_OPENAI_API_KEY: usando o provedor local de regras (so para demonstracao)")
    if canal is None:
        canal = CanalTelegram(cfg.telegram_token) if cfg.telegram_token else CanalMemoria()
    estado = EstadoRedis(cfg.redis_url) if cfg.redis_url else EstadoMemoria()
    busca = BuscaHttp(cfg.busca_api_key, cfg.busca_url) if cfg.busca_api_key else BuscaFalsa()
    n = Nucleo(cfg=cfg, banco=banco, provedor=provedor, canal=canal, registro=montar_registro(), estado=estado, busca=busca)
    if cfg.google_client_id and cfg.google_client_secret and cfg.token_key:
        from .google.http import GoogleHttp
        from .google.oauth import OAuthGoogle
        n.oauth = OAuthGoogle(banco, cfg.google_client_id, cfg.google_client_secret, cfg.public_url, cfg.token_key)
        n.google = GoogleHttp(n.oauth)
    else:
        n.google = GoogleFalso()
    return n
