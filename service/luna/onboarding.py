"""Cadastro, aceite e primeiro uso (PRD RF-14). Piloto por convite; sem aceite da politica nenhuma ferramenta roda."""
from __future__ import annotations

import re
from typing import TYPE_CHECKING

from .tipos import Botao, Mensagem, Saida, Usuario

if TYPE_CHECKING:
    from .nucleo import Nucleo

RE_HORA = re.compile(r"^([01]?\d|2[0-3])[:h]([0-5]\d)?$")


def _politica(nucleo: "Nucleo") -> str:
    link = f"\nPolítica completa: {nucleo.cfg.politica_url}" if nucleo.cfg.politica_url else ""
    return ("Antes de começar, preciso do seu aceite.\n\n"
            "• Guardo o que você me pedir (lembretes, gastos, listas, documentos) só na sua conta.\n"
            "• Suas mensagens passam por um provedor de IA para eu entender o pedido; elas não são usadas para treinar modelos.\n"
            "• Áudios são transcritos e apagados; de arquivos guardo só a referência.\n"
            "• Você pode exportar (/exportar) ou apagar tudo (/apagar_meus_dados) quando quiser." + link)


async def desconhecido(nucleo: "Nucleo", m: Mensagem) -> list[Saida]:
    """Quem ainda nao tem conta: so entra com convite. Nenhuma ferramenta fica ao alcance."""
    codigo = ""
    t = (m.texto or "").strip()
    if t.lower().startswith("/start"):
        codigo = t[6:].strip()
    elif re.fullmatch(r"[A-Za-z0-9-]{4,24}", t):
        codigo = t
    exige = nucleo.cfg.exige_convite
    if exige and not codigo:
        return [Saida("Oi! Eu sou a Luna, uma assessora pessoal. Estou em piloto por convite.\n"
                      "Se você tem um código, mande: /start SEU-CODIGO")]
    async with nucleo.banco.anonimo() as cx:
        r = await cx.fn("f_signup", m.canal, m.id_externo, m.nome_exibicao or "", codigo, exige)
    if not r or not r.get("ok"):
        motivo = (r or {}).get("motivo")
        if motivo == "convite":
            return [Saida("Esse código de convite não vale (ou já foi usado). Confira e mande de novo: /start SEU-CODIGO")]
        return [Saida("Não consegui criar seu cadastro agora. Tente de novo em instantes.")]
    return [Saida("Oi! Eu sou a Luna, sua assessora pessoal. Cuido de lembretes, agenda, dinheiro, documentos e listas, "
                  "e aviso antes de dar problema.\n\n" + _politica(nucleo),
                  [[Botao("Aceito", "ob:aceite:ok"), Botao("Não aceito", "ob:aceite:no")]])]


async def _passo(nucleo: "Nucleo", uid: int, passo: str) -> None:
    async with nucleo.banco.usuario(uid) as cx:
        await cx.exec("UPDATE agente.users SET onboarding_step = %s, onboarded_at = CASE WHEN %s = 'done' THEN now() ELSE onboarded_at END WHERE id = %s",
                      passo, passo, uid)


def _pergunta_nome(u: Usuario) -> Saida:
    return Saida("Como você quer que eu te chame?", [[Botao(f"Pode ser {u.nome}"[:30], "ob:nome:ok")]])


def _pergunta_resumo() -> Saida:
    return Saida("Todo dia de manhã eu mando um resumo do seu dia. A que horas?",
                 [[Botao(h, f"ob:sum:{h}") for h in ("07:00", "07:30", "08:00", "09:00")]])


TUTORIAL = ("Tudo pronto! Fale comigo do jeito do dia a dia, por texto ou áudio. Para começar, tente uma destas:\n"
            "• \"me lembra amanhã às 9h de ligar pro contador\"\n"
            "• \"gastei 42 no mercado\"\n"
            "• \"lista de mercado: arroz, café\"\n\n"
            "Depois eu te mostro como conectar sua agenda do Google. /menu mostra tudo o que eu faço.")


async def conduzir(nucleo: "Nucleo", u: Usuario, m: Mensagem) -> list[Saida]:
    """Um passo do cadastro: aceite -> nome -> resumo -> done."""
    passo = u.onboarding
    acao = m.acao_id if m.tipo == "botao" else ""
    texto = (m.texto or "").strip()

    if passo == "aceite":
        if acao == "ob:aceite:ok":
            async with nucleo.banco.usuario(u.id) as cx:
                await cx.fn("f_consent_set", u.id, "politica", nucleo.cfg.politica_versao, True)
            await _passo(nucleo, u.id, "nome")
            return [Saida("Obrigada!"), _pergunta_nome(u)]
        if acao == "ob:aceite:no":
            return [Saida("Sem o aceite eu não posso guardar nada seu, então não consigo ajudar. "
                          "Se mudar de ideia, é só tocar em Aceito na mensagem acima. Para apagar seu cadastro: /apagar_meus_dados")]
        return [Saida(_politica(nucleo), [[Botao("Aceito", "ob:aceite:ok"), Botao("Não aceito", "ob:aceite:no")]])]

    if passo == "nome":
        if acao != "ob:nome:ok":
            if m.tipo != "texto" or not texto or texto.startswith("/"):
                return [_pergunta_nome(u)]
            nome = re.sub(r"\s+", " ", texto)[:40]
            async with nucleo.banco.usuario(u.id) as cx:
                await cx.exec("UPDATE agente.users SET name = %s WHERE id = %s", nome, u.id)
        await _passo(nucleo, u.id, "resumo")
        return [_pergunta_resumo()]

    if passo == "resumo":
        hora = ""
        if acao.startswith("ob:sum:"):
            hora = acao[7:]
        elif m.tipo == "texto":
            mt = RE_HORA.match(texto.lower().replace(" ", ""))
            if mt:
                hora = f"{int(mt.group(1)):02d}:{mt.group(2) or '00'}"
        if not hora:
            return [_pergunta_resumo()]
        async with nucleo.banco.usuario(u.id) as cx:
            await cx.exec("UPDATE agente.users SET summary_time = %s::time WHERE id = %s", hora, u.id)
        await _passo(nucleo, u.id, "done")
        return [Saida(f"Combinado, resumo às {hora}.\n\n" + TUTORIAL)]

    # passo desconhecido (conta criada fora do servico e nunca concluida): recomeca pelo aceite
    await _passo(nucleo, u.id, "aceite")
    return [Saida(_politica(nucleo), [[Botao("Aceito", "ob:aceite:ok"), Botao("Não aceito", "ob:aceite:no")]])]


async def oferta_google(nucleo: "Nucleo", u: Usuario) -> Saida | None:
    """Depois do primeiro uso bem-sucedido, oferece conectar a agenda (uma vez)."""
    if u.google:
        return None
    async with nucleo.banco.usuario(u.id) as cx:
        n = await cx.valor("SELECT count(*) FROM agente.assessor_runs WHERE user_id = %s AND gravacoes > 0", u.id)
    if n != 1:
        return None
    return Saida("Funcionou! Se quiser, eu também cuido da sua agenda do Google (compromissos, convites, horário livre). "
                 "Peço só permissão para eventos e tarefas.", [[Botao("Conectar o Google", "gg:conectar"), Botao("Agora não", "gg:nao")]])
