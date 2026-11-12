"""Teclados do banco: o campo kb das funcoes SQL vira botoes. GERADO a partir de tools/n8n-gen/modified.json
(nos "Enviar com ..."). Enquanto um dominio nao migrar, os cliques seguem para agente.f_callback (PRD RF-01)."""
from __future__ import annotations

from .tipos import Botao

TECLADOS: dict[str, list[list[tuple[str, str]]]] = {
    'lead': [[('Nao', 'lead:{rid}:0'), ('15 min', 'lead:{rid}:15'), ('1 hora', 'lead:{rid}:60'), ('1 dia', 'lead:{rid}:1440')]],
    'snooze': [[('Mesmo horario', 'snzs:{rid}'), ('Outro horario', 'snzo:{rid}')]],
    'summary_time': [[('07:00', 'sum:07:00'), ('07:30', 'sum:07:30'), ('08:00', 'sum:08:00'), ('09:00', 'sum:09:00')]],
    'fin_undo': [[('Desfazer', 'fundo:{rid}')]],
    'fin_confirm': [[('Confirmar', 'fok:{rid}'), ('Cancelar', 'fno:{rid}')]],
    'fin_delete': [[('Sim, apagar', 'fdel:{rid}'), ('Nao', 'fkeep:{rid}')]],
    'ag_confirm': [[('Confirmar', 'agok:{rid}'), ('Cancelar', 'agno:{rid}')]],
    'ag_pick2': [[('1', 'agpk:{rid}:1'), ('2', 'agpk:{rid}:2')]],
    'ag_pick3': [[('1', 'agpk:{rid}:1'), ('2', 'agpk:{rid}:2'), ('3', 'agpk:{rid}:3')]],
    'ag_scope': [[('Só este', 'agsc:{rid}:1'), ('A série', 'agsc:{rid}:a')]],
    'ag_conflict': [[('Marcar mesmo assim', 'agfy:{rid}'), ('Outro horário', 'agfo:{rid}')]],
    'ag_invite': [[('Aceitar', 'agrs:{rid}'), ('Recusar', 'agrn:{rid}')]],
    'ex_card_del': [[('Sim, apagar', 'exdel:{rid}'), ('Nao', 'exkeep:{rid}')]],
    'ct_confirm': [[('Confirmar', 'ctok:{rid}'), ('Cancelar', 'ctno:{rid}')]],
    'dc_del': [[('Sim, apagar', 'dcdel:{rid}'), ('Nao', 'dckeep:{rid}')]],
    'dc_fdel': [[('Sim, apagar a pasta', 'dcfdel:{rid}'), ('Nao', 'dckeep:{rid}')]],
    'ls_confirm': [[('Confirmar', 'lsok:{rid}'), ('Cancelar', 'lsno:{rid}')]],
    'pj_tasks': [[('Gravar tarefas', 'pjok:{rid}'), ('Cancelar', 'pjno:{rid}')]],
    'pj_del': [[('Sim, apagar', 'pjdel:{rid}'), ('Nao', 'pjkeep:{rid}')]],
    'menu': [[('Lembretes e agenda', 'mn:lemb'), ('Tarefas e listas', 'mn:tar')], [('Dinheiro', 'mn:din'), ('Remédios', 'mn:rem')], [('Projetos', 'mn:proj'), ('Documentos', 'mn:doc')], [('Pessoas e memória', 'mn:pess'), ('Fotos, áudio e pesquisa', 'mn:foto')], [('Ajustes', 'mn:aj')]],
    'place_ask': [[('Marcar sem endereco', 'plskip:{rid}'), ('Nao perguntar mais', 'plnever:{rid}')]],
    'sup_del': [[('Sim, apagar', 'spdel:{rid}'), ('Nao', 'spkeep:{rid}')]],
    'fin_recibo': [[('Desfazer', 'fundo:{rid}'), ('Editar', 'fedit:{rid}')]],
    'agimp': [[('Criar tudo', 'aiok:{rid}'), ('Cancelar', 'aino:{rid}')]],
    'multi_undo': [[('Desfazer tudo', 'mu:{rid}')]],
    'menu_area': [[('Ver mais', 'mn:mais{rid}'), ('Voltar ao menu', 'mn:inicio')]],
    'menu_mais': [[('Voltar à área', 'mn:a{rid}'), ('Menu', 'mn:inicio')]],
}


def botoes(kb: str, rid) -> list[list[Botao]]:
    """Botoes de um teclado do banco, com o rid no lugar."""
    linhas = TECLADOS.get(kb or "none")
    if not linhas:
        return []
    return [[Botao(rot, acao.replace("{rid}", str(rid))) for rot, acao in linha] for linha in linhas]
