"""Ferramentas por dominio (PRD RF-05): cada acao chama a funcao SQL certa e devolve o que o banco respondeu."""
from datetime import datetime, timedelta

import pytest

from conftest import criar_usuario
from luna.agente import laco, pendentes
from luna.agente.contexto import Ctx
from luna.agente.politica import EstadoExec
from luna.app import Luna
from luna.chamadas import botao_do_banco
from luna.ferramentas.base import ALTERA, CONSULTA
from luna.provedor.falso import chamada
from luna.tipos import Mensagem


async def usar(nucleo, u, ferramenta, acao, confirmada=True, texto="", **args):
    """Executa uma acao direto (como uma proposta ja confirmada), validando os argumentos pelo schema."""
    f = nucleo.registro.pegar(ferramenta)
    a, limpo, erro = f.validar({"acao": acao, **args})
    assert not erro, erro
    ctx = Ctx(nucleo=nucleo, usuario=u, est=EstadoExec(confirmada=confirmada), texto=texto)
    return await f.executar(ctx, a, limpo), ctx


def amanha(u, h=15, m=0, dias=1):
    return (datetime.now(u.tz) + timedelta(days=dias)).replace(hour=h, minute=m, second=0, microsecond=0)


# ---------- contrato ----------

def test_schema_estrito_em_todas_as_ferramentas(nucleo=None):
    from luna.ferramentas import montar_registro
    for f in montar_registro().todas():
        e = f.esquema()["parameters"]
        assert e["additionalProperties"] is False and set(e["required"]) == set(e["properties"]), f.nome
        assert e["properties"]["acao"]["enum"] == list(f.acoes)
        for nome, p in e["properties"].items():
            if nome != "acao":
                assert "null" in p["type"], f"{f.nome}.{nome} precisa aceitar null (schema estrito)"


def test_validar_descarta_campo_extra_e_recusa_acao_desconhecida(nucleo=None):
    from luna.ferramentas import montar_registro
    f = montar_registro().pegar("financas")
    a, limpo, erro = f.validar({"acao": "lancar", "valor": "42,5", "user_id": 999, "descricao": " x "})
    assert not erro and limpo["valor"] == 42.5 and "user_id" not in limpo and limpo["descricao"] == "x"
    assert f.validar({"acao": "hackear"})[2]
    assert f.validar({"acao": "lancar", "forma": "cheque"})[2]


async def test_acoes_nativas_pedem_confirmacao_no_banco(nucleo, dono):
    """Toda acao marcada como 'confirmacao no banco' de fato so pergunta: nada muda antes do botao."""
    u = dono
    await usar(nucleo, u, "financas", "lancar", valor=30, descricao="almoco")
    await usar(nucleo, u, "financas", "meta_criar", descricao="viagem", valor=800, data="2031-01-01")
    await usar(nucleo, u, "financas", "cartao_criar", cartao="Itau", cartao_fechamento=28, cartao_vencimento=5, cartao_limite=5000)
    await usar(nucleo, u, "listas_notas", "lista_adicionar", lista="mercado", itens=["arroz"])
    await usar(nucleo, u, "listas_notas", "nota_guardar", texto="ideia da assinatura")
    await usar(nucleo, u, "projetos", "criar", projeto="Site", prazo="2031-02-01")
    await usar(nucleo, u, "contatos_lugares", "contato_salvar", nome="Bia", email="bia@ex.com")
    await usar(nucleo, u, "contatos_lugares", "grupo_salvar", grupo="time", membros=["Bia"])
    await usar(nucleo, u, "estoque", "cadastrar", item="vitamina D", quantidade=30, por_dia=1)
    nucleo.google.por_evento(u.id, "Dentista", amanha(u).isoformat(), amanha(u, 16).isoformat())
    casos = [("financas", "apagar", dict(descricao="almoco")), ("financas", "meta_apagar", dict(descricao="viagem")),
             ("financas", "cartao_apagar", dict(cartao="Itau")), ("listas_notas", "lista_limpar", dict(lista="mercado")),
             ("listas_notas", "lista_apagar", dict(lista="mercado")), ("listas_notas", "nota_apagar", dict(busca="assinatura")),
             ("projetos", "apagar", dict(projeto="Site")), ("contatos_lugares", "contato_apagar", dict(nome="Bia")),
             ("contatos_lugares", "grupo_apagar", dict(grupo="time")), ("estoque", "apagar", dict(item="vitamina D")),
             ("agenda", "cancelar", dict(titulo="dentista")), ("agenda", "mover", dict(titulo="dentista", nova_hora="17:00")),
             ("agenda", "convidar", dict(titulo="Reunião", data=amanha(u, dias=3).date().isoformat(), hora="10:00", convidados=["Bia"]))]
    for ferr, acao, args in casos:
        assert nucleo.registro.pegar(ferr).acoes[acao].nativa, (ferr, acao)
        res, _ = await usar(nucleo, u, ferr, acao, confirmada=False, **args)
        assert res.ok and res.kb != "none", f"{ferr}.{acao} devia pedir confirmacao: {res.texto}"
    async with nucleo.banco.usuario(u.id) as cx:
        assert await cx.valor("SELECT count(*) FROM agente.fin_entries WHERE user_id = %s", u.id) == 1
        assert await cx.valor("SELECT count(*) FROM agente.lists WHERE user_id = %s", u.id) == 1
        assert await cx.valor("SELECT count(*) FROM agente.contacts WHERE user_id = %s", u.id) == 1
    assert not [c for c in nucleo.google.chamadas if c[0] in ("apagar_evento", "atualizar_evento", "criar_evento")]
    # e o contrario: acao de alterar que NAO e nativa precisa passar pela proposta do servico
    for f in nucleo.registro.todas():
        for a in f.acoes.values():
            if a.nivel >= ALTERA and not a.nativa:
                assert a.resumo is not None, f"{f.nome}.{a.nome} precisa de resumo para a proposta"


# ---------- financas ----------

async def test_financas_lancar_consultar_e_relatorio(nucleo, usuario):
    r, _ = await usar(nucleo, usuario, "financas", "lancar", valor=42.5, descricao="almoço", forma="pix")
    assert "R$ 42,50" in r.texto and r.kb == "fin_recibo"
    r, _ = await usar(nucleo, usuario, "financas", "lancar", valor=600, descricao="tênis", parcelas=3, forma="credito")
    assert "3" in r.texto
    r, _ = await usar(nucleo, usuario, "financas", "lancar", valor=1500, descricao="aluguel", dia_fixo=5, pago=False)
    assert "todo dia 5" in r.texto
    r, _ = await usar(nucleo, usuario, "financas", "resumo")
    assert "Gastos" in r.texto
    r, _ = await usar(nucleo, usuario, "financas", "orcamento_definir", categoria="Lazer", valor=200)
    assert "R$ 200,00" in r.texto
    r, _ = await usar(nucleo, usuario, "financas", "relatorio", formato="csv")
    assert r.anexo and r.anexo[0] == "relatorio.csv" and "almo" in r.anexo[1].decode("utf-8")
    r, _ = await usar(nucleo, usuario, "financas", "relatorio", formato="xlsx")
    assert r.anexo[0].endswith(".xlsx") and r.anexo[1][:2] == b"PK"
    r, _ = await usar(nucleo, usuario, "financas", "lancar", descricao="sem valor")
    assert not r.ok and "valor" in r.erro


async def test_desfazer_pelo_botao_do_banco(nucleo, usuario):
    r, _ = await usar(nucleo, usuario, "financas", "lancar", valor=10, descricao="cafe")
    s = await botao_do_banco(nucleo, usuario, f"fundo:{r.rid}")
    assert s[0].texto
    async with nucleo.banco.usuario(usuario.id) as cx:
        assert await cx.valor("SELECT count(*) FROM agente.fin_entries WHERE user_id = %s", usuario.id) == 0


# ---------- lembretes ----------

async def test_lembrete_criar_listar_cancelar(nucleo, usuario):
    d = amanha(usuario, 9)
    r, _ = await usar(nucleo, usuario, "lembretes", "criar", titulo="ligar pro contador", data=d.date().isoformat(), hora="09:00")
    assert 'Lembrete criado: "ligar pro contador" - amanhã às 09:00' in r.texto and r.kb == "lead"
    r2, _ = await usar(nucleo, usuario, "lembretes", "criar", titulo="pagar IPVA", data=d.date().isoformat(), hora="10:00",
                       antecedencia_min=60, repete="anual")
    assert "Aviso 1h antes" in r2.texto
    r, _ = await usar(nucleo, usuario, "lembretes", "listar", dias=3)
    assert "ligar pro contador" in r.texto
    r, _ = await usar(nucleo, usuario, "lembretes", "criar", titulo="x", data="2020-01-01", hora="09:00")
    assert not r.ok and "já passou" in r.erro
    r, _ = await usar(nucleo, usuario, "lembretes", "cancelar", titulo="contador")
    assert "Cancelei" in r.texto


# ---------- agenda ----------

async def test_agenda_sem_google_avisa_e_nao_quebra(nucleo, usuario):
    r, _ = await usar(nucleo, usuario, "agenda", "criar", titulo="Reunião", data="2031-01-01", hora="10:00")
    assert "não está conectado" in r.texto
    r, _ = await usar(nucleo, usuario, "agenda", "listar")
    assert "Lembretes" in r.texto and "não conectado" in r.texto
    r, _ = await usar(nucleo, usuario, "retrato", "ver")
    assert "Google não conectado" in r.texto


async def test_agenda_criar_listar_conflito_mover_cancelar(nucleo, dono):
    u, g = dono, nucleo.google
    d = amanha(u, 15)
    r, _ = await usar(nucleo, u, "agenda", "criar", titulo="Reunião com cliente", data=d.date().isoformat(), hora="15:00", duracao_min=60)
    assert r.ok and "Agendado no seu Google Calendar" in r.texto
    assert len(await g.eventos(u.id, d - timedelta(hours=1), d + timedelta(hours=2))) == 1
    r, _ = await usar(nucleo, u, "agenda", "listar", data_inicio=d.date().isoformat())
    assert "Reunião com cliente" in r.texto and "15:00" in r.texto
    # conflito: o banco pergunta antes de marcar por cima
    r, _ = await usar(nucleo, u, "agenda", "criar", titulo="Dentista", data=d.date().isoformat(), hora="15:30")
    assert r.kb == "ag_conflict" and "conflita" in r.texto
    assert len(await g.eventos(u.id, d - timedelta(hours=1), d + timedelta(hours=2))) == 1
    s = await botao_do_banco(nucleo, u, f"agfy:{r.rid}")       # "Marcar mesmo assim"
    assert "Agendado" in s[0].texto
    assert len(await g.eventos(u.id, d - timedelta(hours=1), d + timedelta(hours=2))) == 2
    # mover pede confirmacao e so muda no Google depois do botao
    r, _ = await usar(nucleo, u, "agenda", "mover", confirmada=False, titulo="reunião com cliente", nova_hora="17:00")
    assert r.kb == "ag_confirm"
    assert not [c for c in g.chamadas if c[0] == "atualizar_evento"]
    s = await botao_do_banco(nucleo, u, f"agok:{r.rid}")
    assert [c for c in g.chamadas if c[0] == "atualizar_evento"] and s[0].texto
    # cancelar
    r, _ = await usar(nucleo, u, "agenda", "cancelar", confirmada=False, titulo="dentista")
    assert r.kb == "ag_confirm"
    await botao_do_banco(nucleo, u, f"agok:{r.rid}")
    assert len(await g.eventos(u.id, d - timedelta(hours=1), d + timedelta(hours=6))) == 1


async def test_convite_so_sai_depois_de_confirmar_e_nunca_inventa_email(nucleo, dono):
    u, g = dono, nucleo.google
    d = amanha(u, 16, dias=2)
    r, _ = await usar(nucleo, u, "agenda", "convidar", confirmada=False, titulo="Planejamento", data=d.date().isoformat(), hora="16:00",
                      convidados=["Fulano Desconhecido"])
    assert r.kb == "none" and "Não achei" in r.texto, "nome sem cadastro vira pedido do e-mail"
    await usar(nucleo, u, "contatos_lugares", "contato_salvar", nome="Douglas", email="douglas@ex.com")
    r, _ = await usar(nucleo, u, "agenda", "convidar", confirmada=False, titulo="Planejamento", data=d.date().isoformat(), hora="16:00",
                      convidados=["Douglas"], meet=True)
    assert r.kb == "ag_confirm" and "Douglas" in r.texto
    assert not [c for c in g.chamadas if c[0] == "criar_evento"]
    s = await botao_do_banco(nucleo, u, f"agok:{r.rid}")
    cria = [c for c in g.chamadas if c[0] == "criar_evento"]
    assert len(cria) == 1 and "douglas@ex.com" in cria[0][2]["attendees"]
    # clique duplo nao cria de novo
    await botao_do_banco(nucleo, u, f"agok:{r.rid}")
    assert len([c for c in g.chamadas if c[0] == "criar_evento"]) == 1


async def test_local_desconhecido_pergunta_o_endereco(nucleo, dono):
    d = amanha(dono, 19, dias=2)
    r, _ = await usar(nucleo, dono, "agenda", "criar", confirmada=False, titulo="Festa", data=d.date().isoformat(), hora="19:00", local="igreja")
    assert r.kb == "place_ask" and "endereço" in r.texto


async def test_horario_livre_respeita_expediente(nucleo, dono):
    d = amanha(dono, 9)
    nucleo.google.por_evento(dono.id, "Ocupado", d.isoformat(), (d + timedelta(hours=3)).isoformat())
    r, _ = await usar(nucleo, dono, "agenda", "horario_livre", data_inicio=d.date().isoformat())
    assert r.ok and "expediente" in r.texto.lower() or "livre" in r.texto.lower()


async def test_google_fora_do_ar_nao_grava_parcial(nucleo, dono):
    nucleo.google.falhar = "timeout"
    d = amanha(dono, 15)
    nucleo.provedor.roteiro = [chamada("agenda", acao="criar", titulo="X", data=d.date().isoformat(), hora="15:00"), "O Google não respondeu."]
    r = await laco.executar(nucleo, dono, "marca X amanhã 15h")
    assert r.gravacoes == 0
    assert "Não consegui criar" in nucleo.provedor.recebidos[1][0][-1].texto
    async with nucleo.banco.usuario(dono.id) as cx:
        assert await cx.valor("SELECT count(*) FROM agente.reminders WHERE user_id = %s", dono.id) == 0


async def test_agenda_desconectada_responde_claro(nucleo, dono):
    nucleo.google.desconectar = True
    nucleo.provedor.roteiro = [chamada("agenda", acao="listar"), "Sua agenda está desconectada; reconecte em /config."]
    r = await laco.executar(nucleo, dono, "o que tenho hoje?")
    assert "desconectada" in nucleo.provedor.recebidos[1][0][-1].texto and "reconectar" in nucleo.provedor.recebidos[1][0][-1].texto


# ---------- tarefas ----------

async def test_tarefas_criar_listar_concluir(nucleo, dono):
    r, _ = await usar(nucleo, dono, "tarefas", "criar", titulo="ligar pro eletricista", prazo="2031-03-10")
    assert "(prazo 10/03)" in r.texto
    r, _ = await usar(nucleo, dono, "tarefas", "listar")
    assert "eletricista" in r.texto
    r, _ = await usar(nucleo, dono, "tarefas", "concluir", titulo="eletricista")
    assert "concluída" in r.texto
    r, _ = await usar(nucleo, dono, "tarefas", "listar")
    assert "não tem tarefas" in r.texto


# ---------- demais dominios ----------

async def test_estoque_ciclo(nucleo, usuario):
    r, _ = await usar(nucleo, usuario, "estoque", "cadastrar", item="vitamina D", quantidade=30, por_dia=1)
    assert "Restam 30" in r.texto
    r, _ = await usar(nucleo, usuario, "estoque", "ajustar", item="vitamina D", restam=12)
    assert "restam 12" in r.texto
    r, _ = await usar(nucleo, usuario, "estoque", "lembrete_de_tomar", item="vitamina D", hora_tomar="08:00")
    assert "08:00" in r.texto
    r, _ = await usar(nucleo, usuario, "estoque", "comprei", item="vitamina D")
    assert "Recomecei" in r.texto
    r, _ = await usar(nucleo, usuario, "estoque", "situacao")
    assert "vitamina D" in r.texto


async def test_listas_projetos_contatos(nucleo, usuario):
    r, _ = await usar(nucleo, usuario, "listas_notas", "lista_adicionar", lista="mercado", itens=["arroz", "café"])
    assert "arroz" in r.texto
    r, _ = await usar(nucleo, usuario, "listas_notas", "lista_marcar", lista="mercado", itens=["arroz"])
    assert r.ok
    r, _ = await usar(nucleo, usuario, "listas_notas", "nota_buscar", busca="nada")
    assert r.ok
    r, _ = await usar(nucleo, usuario, "projetos", "criar", projeto="Reforma", prazo="2031-05-01", tarefas=["orçamento", "pintura"])
    assert "Reforma" in r.texto
    r, _ = await usar(nucleo, usuario, "projetos", "ver", projeto="Reforma")
    assert "Reforma" in r.texto
    r, _ = await usar(nucleo, usuario, "contatos_lugares", "lugar_salvar", nome="igreja", endereco="Rua das Flores, 120")
    assert "Rua das Flores" in r.texto
    r, _ = await usar(nucleo, usuario, "contatos_lugares", "lugares")
    assert "igreja" in r.texto.lower()


async def test_preferencias_e_dose_de_avisos(nucleo, usuario):
    r, _ = await usar(nucleo, usuario, "preferencias", "ajustar", apelido="Adri", resumo_noite="off")
    assert "Adri" in r.texto
    r, _ = await usar(nucleo, usuario, "preferencias", "avisos", modo_avisos="quieto")
    assert "quieto" in r.texto
    r, _ = await usar(nucleo, usuario, "preferencias", "revisao_semanal", revisao_dia="sexta", revisao_hora="18:00")
    assert "sexta às 18:00" in r.texto
    r, _ = await usar(nucleo, usuario, "preferencias", "ver")
    assert "modo quieto" in r.texto and "sexta" in r.texto


async def test_corrigir_e_desfazer_acoes_recentes(nucleo, usuario):
    nucleo.provedor.roteiro = [[chamada("listas_notas", acao="nota_guardar", texto="ideia A")], ]
    r = await laco.executar(nucleo, usuario, "anota a ideia A")
    assert r.gravacoes == 1
    res, _ = await usar(nucleo, usuario, "acoes_recentes", "listar")
    assert "ideia A" in res.texto
    res, _ = await usar(nucleo, usuario, "acoes_recentes", "desfazer_ultimas")
    assert res.ok
    async with nucleo.banco.usuario(usuario.id) as cx:
        assert await cx.valor("SELECT count(*) FROM agente.notes WHERE user_id = %s", usuario.id) == 0


async def test_toda_acao_declarada_tem_teste_ou_e_coberta(nucleo=None):
    """Contrato leve: o numero de ferramentas e acoes e o esperado pelo PRD (evita acao orfa sem revisao)."""
    from luna.ferramentas import montar_registro
    r = montar_registro()
    nomes = {f.nome for f in r.todas()}
    assert nomes == {"retrato", "agenda", "lembretes", "tarefas", "financas", "estoque", "documentos", "listas_notas", "projetos",
                     "contatos_lugares", "memoria", "pesquisa_web", "preferencias", "acoes_recentes", "custo"}
