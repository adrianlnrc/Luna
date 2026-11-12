"""Comandos (PRD RF-18). Nenhum chama o modelo."""
from __future__ import annotations

import json
import secrets
from typing import TYPE_CHECKING

from .teclados import botoes
from .tipos import Botao, Saida, Usuario

if TYPE_CHECKING:
    from .nucleo import Nucleo

COMANDOS = ["/start", "/menu", "/ajuda", "/config", "/contatos", "/locais", "/memoria", "/custo", "/exportar",
            "/apagar_meus_dados", "/conectar", "/desconectar"]


async def link_google(nucleo: "Nucleo", u: Usuario) -> Saida:
    if not nucleo.oauth:
        return Saida("A conexão com o Google ainda não está disponível neste ambiente.")
    return Saida("Para conectar sua agenda, abra este link e autorize (só eventos e tarefas):\n" + await nucleo.oauth.link(u.id))


async def executar(nucleo: "Nucleo", u: Usuario, texto: str) -> list[Saida]:
    partes = texto.strip().split(maxsplit=1)
    cmd = partes[0].split("@")[0].lower()
    resto = partes[1].strip() if len(partes) > 1 else ""
    uid = u.id

    if cmd in ("/start", "/menu", "/ajuda"):
        async with nucleo.banco.usuario(uid) as cx:
            r = await cx.fn("f_menu", uid, "") or {}
        return [Saida(r.get("text") or "Fale comigo do jeito do dia a dia.", botoes(r.get("kb") or "none", r.get("rid") or 0))]

    if cmd == "/config":
        async with nucleo.banco.usuario(uid) as cx:
            d = await cx.fn("f_command_data", uid) or {}
            p = await cx.linha("SELECT modo FROM agente.insight_prefs WHERE user_id = %s", uid)
            rv = await cx.linha("SELECT revisao_dia, to_char(revisao_hora,'HH24:MI') AS h FROM agente.users WHERE id = %s", uid)
        dias = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]
        t = str(d.get("config") or "Suas preferências.")
        t += f"\n\nAvisos do assessor: modo {(p or {}).get('modo') or 'normal'} (diga \"modo quieto\", \"normal\" ou \"atento\")."
        t += f"\nRevisão da semana: {dias[rv['revisao_dia']]} às {rv['h']}."
        b = [[Botao("Desconectar o Google", "gg:desconectar")]] if u.google else [[Botao("Conectar o Google", "gg:conectar")]]
        return [Saida(t, b)]

    if cmd in ("/contatos", "/locais", "/memoria"):
        fn = {"/contatos": "f_list_pessoas", "/locais": "f_list_lugares"}.get(cmd)
        async with nucleo.banco.usuario(uid) as cx:
            r = await cx.fn(fn, uid) if fn else await cx.fn("f_mem_list", uid, resto)
        return [Saida((r or {}).get("text") or "Nada por aqui ainda.")]

    if cmd == "/custo":
        async with nucleo.banco.usuario(uid) as cx:
            linha = await cx.fn("f_value_line", uid)
            if u.papel == "dono":
                return [Saida(str(await cx.fn("f_ai_cost_text", uid)) + "\n\nFranquia: " + str(linha))]
        return [Saida("Seu uso neste mês: " + str(linha) + ".")]

    if cmd == "/exportar":
        async with nucleo.banco.usuario(uid) as cx:
            d = await cx.fn("f_user_export", uid)
        dados = json.dumps(d, ensure_ascii=False, indent=1, default=str).encode("utf-8")
        return [Saida("Aqui estão todos os seus dados.", anexo=("meus-dados-luna.json", dados, "application/json"))]

    if cmd == "/apagar_meus_dados":
        return [Saida("Isso apaga TUDO o que eu guardo sobre você (lembretes, finanças, documentos, listas, memória), "
                      "desconecta o Google e encerra sua conta. Não dá para desfazer.\n\nQuer continuar?",
                      [[Botao("Quero apagar tudo", "lg:1"), Botao("Cancelar", "lg:no")]])]

    if cmd == "/conectar":
        return [await link_google(nucleo, u)]

    if cmd == "/desconectar":
        return await desconectar_google(nucleo, u)

    return [Saida("Não conheço esse comando. Veja /menu.")]


async def desconectar_google(nucleo: "Nucleo", u: Usuario) -> list[Saida]:
    if nucleo.oauth:
        await nucleo.oauth.desconectar(u.id)
    else:
        async with nucleo.banco.usuario(u.id) as cx:
            await cx.exec("UPDATE agente.users SET calendar_key = NULL WHERE id = %s", u.id)
    return [Saida("Google desconectado: revoguei o acesso e apaguei a autorização. Lembretes, finanças e o resto continuam funcionando.")]


async def apagar_passo(nucleo: "Nucleo", u: Usuario, dado: str) -> list[Saida]:
    """Exclusao em dois passos (PRD RF-15)."""
    if dado == "lg:no":
        await nucleo.estado.apagar(f"purge:{u.id}")
        return [Saida("Ok, não apaguei nada.")]
    if dado == "lg:1":
        chave = secrets.token_hex(4)
        await nucleo.estado.por(f"purge:{u.id}", chave, 300)
        return [Saida("Última confirmação: apagar definitivamente todos os seus dados e encerrar a conta?",
                      [[Botao("Sim, apagar definitivamente", f"lg:2:{chave}"), Botao("Cancelar", "lg:no")]])]
    if dado.startswith("lg:2:"):
        esperado = await nucleo.estado.pegar(f"purge:{u.id}")
        if not esperado or dado[5:] != esperado:
            return [Saida("Essa confirmação expirou. Se ainda quiser apagar, mande /apagar_meus_dados de novo.")]
        await nucleo.estado.apagar(f"purge:{u.id}")
        if nucleo.oauth:
            try:
                await nucleo.oauth.desconectar(u.id)
            except Exception:
                pass
        async with nucleo.banco.usuario(u.id) as cx:
            r = await cx.fn("f_user_purge", u.id)
        await nucleo.estado.apagar(f"hist:{u.id}")
        if not (r or {}).get("ok"):
            return [Saida("Não consegui apagar agora. Tente de novo em instantes.")]
        return [Saida("Pronto: apaguei todos os seus dados e encerrei sua conta. Se quiser voltar um dia, é só pedir um novo convite.")]
    return [Saida("Não entendi.")]
