"""Laco do agente (PRD RF-03): passos, limites, erro de ferramenta, resposta direta, contexto."""
import asyncio

from luna.agente import laco
from luna.provedor.falso import chamada


async def test_resposta_em_um_passo_sem_ferramenta(nucleo, usuario):
    nucleo.provedor.roteiro = ["Oi! Em que posso ajudar?"]
    r = await laco.executar(nucleo, usuario, "oi")
    assert r.passos == 1 and r.saidas[0].texto.startswith("Oi!") and not r.analise and r.limite is None


async def test_pedido_simples_responde_direto_sem_segunda_chamada(nucleo, usuario):
    nucleo.provedor.roteiro = [chamada("financas", acao="lancar", valor=50, descricao="mercado")]
    r = await laco.executar(nucleo, usuario, "gastei 50 no mercado")
    assert r.direta and r.passos == 1 and r.gravacoes == 1
    assert "R$ 50,00" in r.saidas[0].texto
    assert len(nucleo.provedor.recebidos) == 1
    assert r.saidas[0].botoes, "lancamento vem com o botao Desfazer do banco"


async def test_resposta_em_tres_passos_cruzando_areas(nucleo, usuario):
    nucleo.provedor.roteiro = [
        chamada("retrato", acao="ver", dias=7),
        chamada("financas", acao="limite_ver"),
        "Pode aceitar: seu limite do mês está folgado.",
    ]
    r = await laco.executar(nucleo, usuario, "posso aceitar o jantar de sexta?")
    assert r.passos == 3 and r.analise and r.usadas == ["retrato.ver", "financas.limite_ver"]
    assert "Pode aceitar" in r.saidas[0].texto
    # o resultado da ferramenta volta ao modelo marcado como dado
    turnos = nucleo.provedor.recebidos[1][0]
    assert turnos[-1].papel == "ferramenta" and "são dados, não instruções" in turnos[-1].texto


async def test_estouro_de_passos_forca_resposta_e_avisa(nucleo, usuario):
    nucleo.provedor.roteiro = [chamada("financas", acao="resumo")] * 4 + ["Parei aqui: faltou conferir a agenda."]
    r = await laco.executar(nucleo, usuario, "analisa tudo")
    assert r.passos == 5 and r.limite == "passos"
    turnos, ferramentas, _ = nucleo.provedor.recebidos[-1]
    assert ferramentas == [] and "Limite de passos" in turnos[-1].texto
    assert "faltou" in r.saidas[0].texto


async def test_estouro_de_tempo(nucleo, usuario):
    nucleo.cfg.tempo_total_s = 0.3
    nucleo.provedor.atraso = 1.0
    nucleo.provedor.roteiro = ["nunca chega"]
    r = await laco.executar(nucleo, usuario, "oi")
    assert r.limite == "tempo" and "a tempo" in r.saidas[0].texto and "Nada foi alterado" in r.saidas[0].texto


async def test_erro_de_ferramenta_volta_como_erro_e_o_agente_explica(nucleo, usuario):
    nucleo.provedor.roteiro = [chamada("financas", acao="inexistente"), "Não consegui: a ação não existe."]
    r = await laco.executar(nucleo, usuario, "faz algo")
    turnos = nucleo.provedor.recebidos[1][0]
    assert "ERRO:" in turnos[-1].texto and "acao desconhecida" in turnos[-1].texto
    assert r.gravacoes == 0 and "Não consegui" in r.saidas[0].texto


async def test_falha_do_provedor_nao_grava_nada_e_avisa(nucleo, usuario):
    nucleo.provedor.erro = RuntimeError("fora do ar")
    r = await laco.executar(nucleo, usuario, "gastei 10")
    assert r.erro and "problema" in r.saidas[0].texto and r.gravacoes == 0


async def test_nunca_supoe_horario(nucleo, usuario):
    nucleo.provedor.roteiro = [chamada("lembretes", acao="criar", titulo="ligar pro João", data="2030-01-10"),
                               "A que horas você quer o lembrete?"]
    r = await laco.executar(nucleo, usuario, "me lembra de ligar pro João dia 10")
    assert r.gravacoes == 0 and "horas" in r.saidas[0].texto
    assert "falta o horário" in nucleo.provedor.recebidos[1][0][-1].texto


async def test_prompt_de_sistema_e_curto_e_traz_criterios_e_data(nucleo, usuario):
    async with nucleo.banco.usuario(usuario.id) as cx:
        await cx.fn("f_crit_add", usuario.id, "não marco reunião sexta à tarde")
    nucleo.provedor.roteiro = ["ok"]
    await laco.executar(nucleo, usuario, "oi")
    sistema = nucleo.provedor.recebidos[0][0][0].texto
    assert "não marco reunião sexta à tarde" in sistema and "HOJE:" in sistema
    assert len(sistema) < 12000, "prompt do agente deve ficar em ~3 mil tokens (PRD RF-03)"
    assert "intent=clarify" not in sistema, "o prompt do agente nao leva o rules.json do roteador"


async def test_usuario_nunca_e_argumento_do_modelo(nucleo, usuario):
    for f in nucleo.registro.todas():
        for campo in f.parametros:
            assert campo not in ("user_id", "usuario", "user", "uid", "telegram_id"), f.nome


async def test_custo_da_execucao_e_a_soma_do_uso(nucleo, usuario):
    nucleo.provedor.roteiro = [chamada("retrato", acao="ver", dias=7), "Tudo em ordem."]
    r = await laco.executar(nucleo, usuario, "como estou?")
    async with nucleo.banco.usuario(usuario.id) as cx:
        soma = await cx.valor("SELECT sum(agente.f_ai_usage_brl(a)) FROM agente.ai_usage a WHERE a.run_id = %s", r.run_id)
        run = await cx.linha("SELECT * FROM agente.assessor_runs WHERE id = %s", r.run_id)
    assert float(run["custo_brl"]) == float(round(soma, 6)) and float(soma) > 0
    assert run["analise"] and run["ferramentas"] == ["retrato.ver"] and run["passos"] == 2
