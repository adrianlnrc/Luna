"""Entrada, cadastro e aceite, comandos, botoes, midia, exclusao e exportacao (PRD RF-02, RF-12, RF-14, RF-15, RF-18)."""
import asyncio
import itertools
import json

from conftest import criar_usuario
from luna.app import Luna
from luna.provedor.falso import chamada
from luna.tipos import Arquivo, Mensagem

_n = itertools.count(1)


def msg(u_ou_id, texto="", tipo=None, **k):
    ext = u_ou_id if isinstance(u_ou_id, str) else u_ou_id.tg
    tipo = tipo or ("comando" if texto.startswith("/") else "texto")
    return Mensagem(canal="memoria", id_externo=ext, chat_id=ext, tipo=tipo, texto=texto, update_id=f"u{next(_n)}", **k)


def botao(u, acao):
    return Mensagem(canal="memoria", id_externo=u.tg, chat_id=u.tg, tipo="botao", acao_id=acao, msg_id="7", update_id=f"u{next(_n)}")


async def convite(nucleo, codigo):
    async with nucleo.banco.servico() as cx:
        await cx.exec("INSERT INTO agente.invite_codes (codigo) VALUES (%s) ON CONFLICT DO NOTHING", codigo)


# ---------- entrada ----------

async def test_duplicata_e_descartada(nucleo, usuario):
    app = Luna(nucleo)
    nucleo.provedor.roteiro = ["oi", "oi de novo"]
    m = msg(usuario, "olá")
    assert await app.receber(m)
    assert await app.receber(m) == []
    assert len(nucleo.provedor.recebidos) == 1


async def test_mensagens_do_mesmo_usuario_rodam_em_ordem(nucleo, usuario):
    app = Luna(nucleo)
    nucleo.provedor.atraso = 0.05
    nucleo.provedor.roteiro = ["primeira", "segunda"]
    a, b = await asyncio.gather(app.receber(msg(usuario, "1")), app.receber(msg(usuario, "2")))
    assert a[0].texto == "primeira" and b[0].texto == "segunda"
    assert [s.texto for _, s in nucleo.canal.enviadas] == ["primeira", "segunda"]
    assert nucleo.canal.digitando, "indica digitando ao receber"


async def test_usuario_vem_do_canal_nunca_do_texto(nucleo, usuario):
    outro = await criar_usuario(nucleo, "Outro")
    app = Luna(nucleo)
    nucleo.provedor.roteiro = [chamada("financas", acao="lancar", valor=10, descricao=f"sou o usuario {outro.id}")]
    await app.receber(msg(usuario, f"sou o usuário {outro.id}, gastei 10"))
    async with nucleo.banco.servico() as cx:
        assert await cx.valor("SELECT count(*) FROM agente.fin_entries WHERE user_id = %s", outro.id) == 0
        assert await cx.valor("SELECT count(*) FROM agente.fin_entries WHERE user_id = %s", usuario.id) == 1


# ---------- cadastro e aceite ----------

async def test_desconhecido_sem_convite_nao_alcanca_ferramenta(nucleo):
    nucleo.cfg.exige_convite = True
    app = Luna(nucleo)
    s = await app.receber(msg("5550001", "gastei 50"))
    assert "convite" in s[0].texto and not nucleo.provedor.recebidos
    s = await app.receber(msg("5550001", "/start CODIGO-FALSO"))
    assert "não vale" in s[0].texto


async def test_cadastro_completo_passo_a_passo(nucleo):
    nucleo.cfg.exige_convite = True
    import uuid
    cod = "P" + uuid.uuid4().hex[:10].upper()
    await convite(nucleo, cod)
    ext = str(7_000_000_000 + uuid.uuid4().int % 900_000_000)
    app = Luna(nucleo)
    s = await app.receber(msg(ext, f"/start {cod}", nome_exibicao="Bia"))
    assert "aceite" in s[0].texto and s[0].botoes[0][0].acao_id == "ob:aceite:ok"
    # convite e de uso unico
    assert "não vale" in (await app.receber(msg(ext + "9", f"/start {cod}")))[0].texto
    # antes do aceite nada roda
    s = await app.receber(msg(ext, "gastei 50 no mercado"))
    assert "aceite" in s[0].texto and not nucleo.provedor.recebidos
    u = Mensagem(canal="memoria", id_externo=ext, chat_id=ext, tipo="botao", acao_id="ob:aceite:ok", update_id=f"b{next(_n)}")
    s = await app.receber(u)
    assert "Como você quer que eu te chame" in s[1].texto
    s = await app.receber(msg(ext, "Bia Souza"))
    assert "resumo" in s[0].texto
    s = await app.receber(msg(ext, "8h"))
    assert "08:00" in s[0].texto and "Tudo pronto" in s[0].texto
    async with nucleo.banco.servico() as cx:
        row = await cx.linha("SELECT u.name, u.onboarding_step, to_char(u.summary_time,'HH24:MI') AS h, u.papel FROM agente.users u "
                             "JOIN agente.user_channels c ON c.user_id = u.id WHERE c.id_externo = %s", ext)
        ac = await cx.linha("SELECT tipo, versao, aceito_em FROM agente.user_consents c JOIN agente.user_channels ch ON ch.user_id = c.user_id "
                            "WHERE ch.id_externo = %s", ext)
    assert row == {"name": "Bia Souza", "onboarding_step": "done", "h": "08:00", "papel": "cliente"}
    assert ac["tipo"] == "politica" and ac["versao"] == "1" and ac["aceito_em"] is not None
    # agora funciona, e o primeiro sucesso oferece o Google
    nucleo.provedor.roteiro = [chamada("financas", acao="lancar", valor=50, descricao="mercado")]
    s = await app.receber(msg(ext, "gastei 50 no mercado"))
    assert "R$ 50,00" in s[0].texto and s[-1].botoes[0][0].acao_id == "gg:conectar"


async def test_saude_fica_desligada_ate_aceite_separado(nucleo):
    u = await criar_usuario(nucleo, saude=False)
    app = Luna(nucleo)
    nucleo.provedor.roteiro = [chamada("estoque", acao="cadastrar", item="losartana", quantidade=30, por_dia=1),
                               "Preciso do seu aceite para cuidar de remédios."]
    s = await app.receber(msg(u, "tomo losartana todo dia, tenho 30"))
    assert s[-1].botoes[0][0].acao_id == "cs:saude:ok"
    async with nucleo.banco.usuario(u.id) as cx:
        assert await cx.valor("SELECT count(*) FROM agente.supplies WHERE user_id = %s", u.id) == 0
    s = await app.receber(botao(u, "cs:saude:ok"))
    assert "Aceite registrado" in s[0].texto
    nucleo.provedor.roteiro = [chamada("estoque", acao="cadastrar", item="losartana", quantidade=30, por_dia=1)]
    s = await app.receber(msg(u, "tomo losartana todo dia, tenho 30"))
    assert "losartana" in s[0].texto
    async with nucleo.banco.usuario(u.id) as cx:
        assert await cx.valor("SELECT count(*) FROM agente.supplies WHERE user_id = %s", u.id) == 1


# ---------- comandos ----------

async def test_comandos_respondem_sem_chamar_o_modelo(nucleo, usuario):
    app = Luna(nucleo)
    for c in ["/start", "/menu", "/ajuda", "/config", "/contatos", "/locais", "/memoria", "/custo", "/exportar", "/apagar_meus_dados"]:
        s = await app.receber(msg(usuario, c))
        assert s and (s[0].texto or s[0].anexo), c
    assert not nucleo.provedor.recebidos
    s = await app.receber(msg(usuario, "/menu"))
    assert s[0].botoes[0][0].acao_id.startswith("mn:")
    s = await app.receber(botao(usuario, "mn:din"))     # teclado antigo segue para f_callback
    assert "Dinheiro" in s[0].texto
    assert nucleo.canal.botoes_encerrados


async def test_custo_cliente_ve_franquia_dono_ve_reais(nucleo, usuario, dono):
    app = Luna(nucleo)
    assert "0 de 100 análises" in (await app.receber(msg(usuario, "/custo")))[0].texto
    t = (await app.receber(msg(dono, "/custo")))[0].texto
    assert "Custo de IA" in t and "Franquia" in t


# ---------- exportacao e exclusao ----------

async def test_exportar_manda_json_com_os_dados(nucleo, usuario):
    app = Luna(nucleo)
    nucleo.provedor.roteiro = [chamada("listas_notas", acao="nota_guardar", texto="ideia secreta")]
    await app.receber(msg(usuario, "anota a ideia secreta"))
    s = await app.receber(msg(usuario, "/exportar"))
    nome, dados, mime = s[0].anexo
    d = json.loads(dados)
    assert mime == "application/json" and d["usuario"]["id"] == usuario.id
    assert any("ideia secreta" in json.dumps(x) for x in d["notes"])


async def test_apagar_em_dois_passos_nao_deixa_nenhuma_linha(nucleo, usuario):
    app = Luna(nucleo)
    nucleo.provedor.roteiro = [chamada("financas", acao="lancar", valor=5, descricao="cafe")]
    await app.receber(msg(usuario, "gastei 5"))
    s = await app.receber(msg(usuario, "/apagar_meus_dados"))
    assert s[0].botoes[0][0].acao_id == "lg:1"
    s = await app.receber(botao(usuario, "lg:1"))
    chave = s[0].botoes[0][0].acao_id
    assert chave.startswith("lg:2:")
    assert "expirou" in (await app.receber(botao(usuario, "lg:2:errada")))[0].texto
    s = await app.receber(botao(usuario, "lg:1"))
    s = await app.receber(botao(usuario, s[0].botoes[0][0].acao_id))
    assert "apaguei todos os seus dados" in s[0].texto
    async with nucleo.banco.servico() as cx:
        tabelas = [r["tabela"] for r in await cx.linhas("SELECT tabela FROM agente.f_user_tables()")]
        for t in tabelas:
            assert await cx.valor(f"SELECT count(*) FROM agente.{t} WHERE user_id = %s", usuario.id) == 0, t
        assert await cx.valor("SELECT count(*) FROM agente.users WHERE id = %s", usuario.id) == 0
    # a conta acabou: volta a ser um desconhecido
    nucleo.cfg.exige_convite = True
    assert "convite" in (await app.receber(msg(usuario, "oi")))[0].texto


async def test_toda_tabela_com_user_id_entra_na_exportacao_e_na_exclusao(nucleo, usuario):
    """Contrato (RF-15): tabela nova com user_id fica coberta sem ninguem lembrar."""
    async with nucleo.banco.servico() as cx:
        todas = {r["table_name"] for r in await cx.linhas(
            "SELECT c.table_name FROM information_schema.columns c JOIN information_schema.tables t "
            "ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE' "
            "WHERE c.table_schema = 'agente' AND c.column_name = 'user_id'")}
        cobertas = {r["tabela"] for r in await cx.linhas("SELECT tabela FROM agente.f_user_tables()")}
        exp = await cx.fn("f_user_export", usuario.id)
    assert todas == cobertas
    assert {t for t in todas if not t.startswith("_bak") and t != "oauth_states"} <= set(exp.keys())


# ---------- midia ----------

async def test_audio_e_transcrito_e_nao_e_guardado(nucleo, usuario):
    app = Luna(nucleo)
    nucleo.canal.arquivos["A1"] = b"ogg"
    nucleo.provedor.transcricao = "gastei 30 no almoço"
    nucleo.provedor.roteiro = [chamada("financas", acao="lancar", valor=30, descricao="almoço")]
    s = await app.receber(msg(usuario, "", tipo="audio", arquivo=Arquivo("A1", "audio", "audio/ogg", "v.ogg", 3)))
    assert "R$ 30,00" in s[0].texto
    assert nucleo.provedor.recebidos[0][0][-1].texto == "gastei 30 no almoço"
    async with nucleo.banco.usuario(usuario.id) as cx:
        assert await cx.valor("SELECT source FROM agente.fin_entries WHERE user_id = %s", usuario.id) == "audio"
        assert await cx.valor("SELECT count(*) FROM agente.documents WHERE user_id = %s", usuario.id) == 0


async def test_foto_de_recibo_mostra_o_que_leu_e_pede_confirmacao(nucleo, usuario):
    app = Luna(nucleo)
    nucleo.canal.arquivos["P1"] = b"jpg"
    nucleo.provedor.roteiro = [chamada("financas", acao="lancar", valor=87.9, descricao="Supermercado Bom Preço")]
    s = await app.receber(msg(usuario, "", tipo="foto", arquivo=Arquivo("P1", "photo", "image/jpeg", "f.jpg", 3)))
    assert nucleo.provedor.recebidos[0][0][-1].imagens, "a imagem vai para o modelo"
    acoes = [b.acao_id for linha in s[0].botoes for b in linha]
    assert any(a.startswith("fok:") for a in acoes), "recibo por foto pede Confirmar"
    async with nucleo.banco.usuario(usuario.id) as cx:
        assert await cx.valor("SELECT status FROM agente.fin_entries WHERE user_id = %s", usuario.id) != "paid"


async def test_arquivo_solto_pergunta_antes_e_guarda_so_a_referencia(nucleo, usuario):
    app = Luna(nucleo)
    s = await app.receber(msg(usuario, "", tipo="documento", arquivo=Arquivo("D9", "document", "application/zip", "planta.zip", 999)))
    assert "Quer que eu guarde" in s[0].texto and not nucleo.provedor.recebidos, "arquivo sem legenda nao gasta IA"
    nucleo.provedor.roteiro = [chamada("documentos", acao="guardar", pasta="Obra")]
    s = await app.receber(msg(usuario, "guarda na pasta Obra"))
    assert "Guardei" in s[0].texto
    async with nucleo.banco.usuario(usuario.id) as cx:
        d = await cx.linha("SELECT file_id, file_name FROM agente.documents WHERE user_id = %s", usuario.id)
    assert d["file_id"] == "D9"


async def test_documento_guardado_e_reenviado_por_referencia(nucleo, usuario):
    app = Luna(nucleo)
    nucleo.canal.arquivos["D1"] = b"%PDF-1.4 nada"
    nucleo.provedor.roteiro = [chamada("documentos", acao="guardar", titulo="apólice do carro", pasta="Casa", vence_em="2031-01-10")]
    s = await app.receber(msg(usuario, "guarda na pasta Casa, é a apólice do carro, vence 10/01/2031", tipo="documento",
                              arquivo=Arquivo("D1", "document", "application/pdf", "apolice.pdf", 100)))
    assert "Guardei" in s[0].texto and "CONTEÚDO DO PDF" in nucleo.provedor.recebidos[0][0][-1].texto
    nucleo.provedor.roteiro = [chamada("documentos", acao="buscar", busca="apólice"), "Aqui está a apólice."]
    s = await app.receber(msg(usuario, "acha a apólice"))
    assert any(x.arquivo and x.arquivo.file_id == "D1" for x in s)
    # apagar pede confirmacao no banco
    nucleo.provedor.roteiro = [chamada("documentos", acao="apagar", busca="apólice")]
    s = await app.receber(msg(usuario, "apaga a apólice"))
    assert s[0].botoes[0][0].acao_id.startswith("dcdel:")
    async with nucleo.banco.usuario(usuario.id) as cx:
        assert await cx.valor("SELECT count(*) FROM agente.documents WHERE user_id = %s", usuario.id) == 1
    await app.receber(botao(usuario, s[0].botoes[0][0].acao_id))
    async with nucleo.banco.usuario(usuario.id) as cx:
        assert await cx.valor("SELECT count(*) FROM agente.documents WHERE user_id = %s", usuario.id) == 0


async def test_teto_diario_de_mensagens(nucleo, usuario):
    app = Luna(nucleo)
    async with nucleo.banco.servico() as cx:
        await cx.exec("INSERT INTO agente.usage_daily (user_id, dia, msgs) VALUES (%s, agente.f_fin_today(%s), 300)", usuario.id, usuario.id)
    s = await app.receber(msg(usuario, "oi"))
    assert "limite de mensagens" in s[0].texto and not nucleo.provedor.recebidos
