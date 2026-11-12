"""Politica de autonomia (PRD RF-06). A decisao e tomada aqui, em codigo: o texto do modelo nao muda o nivel."""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum

from ..ferramentas.base import ALTERA, CONSULTA, CRIA, TERCEIROS, Acao


class Decisao(str, Enum):
    EXECUTAR = "executar"      # roda agora
    PROPOR = "propor"          # vira proposta com Confirmar/Cancelar (pending_actions)
    NATIVA = "nativa"          # roda no banco, que cria a propria pendencia e devolve botoes
    RECUSAR = "recusar"        # nao roda (limite da execucao)


@dataclass
class EstadoExec:
    """O que a politica precisa saber da execucao em curso."""
    origem: str = "pergunta"            # pergunta | vigia | revisao
    contaminada: bool = False           # ja houve pesquisa web nesta execucao
    pedido_usado: bool = False          # a primeira gravacao que corresponde a mensagem ja foi feita
    gravacoes: int = 0                  # gravacoes executadas
    propostas: int = 0
    max_gravacoes: int = 5
    confirmada: bool = False            # execucao de uma proposta que o usuario confirmou


@dataclass
class Veredito:
    decisao: Decisao
    motivo: str = ""
    origem_proposta: str = "agente"     # pedido | agente | vigia | revisao (vai para pending_actions.origem)


def decidir(acao: Acao, est: EstadoExec) -> Veredito:
    # consultar e livre
    if acao.nivel == CONSULTA:
        return Veredito(Decisao.EXECUTAR)

    # proposta que o usuario confirmou: executa exatamente o que foi gravado
    if est.confirmada:
        return Veredito(Decisao.EXECUTAR, "confirmada")

    # teto de gravacoes + propostas por execucao
    if est.gravacoes + est.propostas >= est.max_gravacoes:
        return Veredito(Decisao.RECUSAR, f"limite de {est.max_gravacoes} gravacoes por execucao")

    origem = est.origem if est.origem in ("vigia", "revisao") else "agente"

    # o banco ja pede confirmacao para esta acao: chamar e propor
    if acao.nativa:
        return Veredito(Decisao.NATIVA, "confirmacao no banco", origem)

    # Vigia e revisao da semana nunca executam (regra 4)
    if est.origem in ("vigia", "revisao"):
        return Veredito(Decisao.PROPOR, "origem " + est.origem, origem)

    # depois de ler a web, toda gravacao vira proposta (regra 2)
    if est.contaminada:
        return Veredito(Decisao.PROPOR, "execucao leu conteudo da web", "agente")

    # terceiros e dinheiro: sempre proposta, sem ajuste para desligar
    if acao.nivel >= TERCEIROS:
        return Veredito(Decisao.PROPOR, "envolve terceiros", "pedido" if not est.pedido_usado else "agente")

    # alterar ou apagar: proposta
    if acao.nivel == ALTERA:
        return Veredito(Decisao.PROPOR, "altera ou apaga", "pedido" if not est.pedido_usado else "agente")

    # criar algo reversivel: so a primeira gravacao conta como pedido (regra 1)
    if acao.nivel == CRIA:
        if not est.pedido_usado:
            return Veredito(Decisao.EXECUTAR, "pedido")
        return Veredito(Decisao.PROPOR, "ideia do agente", "agente")

    return Veredito(Decisao.PROPOR, "nivel desconhecido", origem)
