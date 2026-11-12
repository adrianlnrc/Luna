"""Ferramentas do agente, uma por dominio (PRD RF-05)."""
from __future__ import annotations

from .base import Registro


def montar_registro() -> Registro:
    from . import agenda, contatos, documentos, estoque, extras, financas, lembretes, listas_notas, memoria, preferencias, projetos, retrato, tarefas
    r = Registro()
    for f in (retrato.FERRAMENTA, agenda.FERRAMENTA, lembretes.FERRAMENTA, tarefas.FERRAMENTA, financas.FERRAMENTA,
              estoque.FERRAMENTA, documentos.FERRAMENTA, listas_notas.FERRAMENTA, projetos.FERRAMENTA,
              contatos.FERRAMENTA, memoria.FERRAMENTA, extras.PESQUISA, preferencias.FERRAMENTA,
              extras.RECENTES, extras.CUSTO):
        r.registrar(f)
    return r
