"""Avaliacao de paridade com o roteador (PRD RF-19): os casos de tests/natural/casos.json viram
"mensagem -> ferramenta, acao e argumentos esperados". Roda contra qualquer provedor e modelo e devolve
taxa de acerto e custo por caso.

  python -m luna.avaliacao                       # todos os casos, com o provedor configurado
  python -m luna.avaliacao --modelo gpt-6.1-sol  # outro modelo
  python -m luna.avaliacao --grupo financas --detalhe

As ferramentas NAO sao executadas: cada chamada recebe um resultado simulado. Nada e gravado alem do
usuario temporario usado para montar o prompt.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import unicodedata
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any

from .provedor.base import Chamada, Turno

CASOS = Path(__file__).resolve().parents[2] / "tests" / "natural" / "casos.json"

# as 30 intencoes do roteador -> chamadas aceitas no agente. None em acoes = qualquer acao da ferramenta.
INTENCOES: dict[str, list[tuple[str, set[str] | None]]] = {
    "create_reminder": [("lembretes", {"criar", "ligar_a_compromisso"})],
    "create_event": [("agenda", {"criar", "convidar"})],
    "list_agenda": [("agenda", {"listar"}), ("retrato", None)],
    "manage_event": [("agenda", {"mover", "cancelar", "horario_livre", "lembrete_vira_compromisso"}), ("acoes_recentes", {"corrigir"})],
    "create_supply": [("estoque", {"cadastrar", "lembrete_de_tomar"})],
    "supply_bought": [("estoque", {"comprei"})],
    "supply_adjust": [("estoque", {"ajustar", "renomear", "apagar"})],
    "supply_taken": [("estoque", {"tomei"})],
    "supply_schedule": [("estoque", {"lembrete_de_tomar", "parar_lembrete", "cadastrar"})],
    "set_preference": [("preferencias", {"ajustar", "avisos", "revisao_semanal"})],
    "provide_time": [("lembretes", {"criar"}), ("agenda", {"criar"})],
    "create_task": [("tarefas", {"criar"})],
    "list_tasks": [("tarefas", {"listar"})],
    "complete_task": [("tarefas", {"concluir"})],
    "finance": [("financas", None)],
    "cancel_reminder": [("lembretes", {"cancelar"})],
    "contact_manage": [("contatos_lugares", None)],
    "misc_query": [("lembretes", {"historico"}), ("tarefas", {"concluidas"}), ("agenda", {"link"})],
    "document_manage": [("documentos", None)],
    "list_manage": [("listas_notas", {"lista_ver", "listas", "lista_criar", "lista_adicionar", "lista_marcar", "lista_desmarcar",
                                      "lista_tirar_item", "lista_limpar", "lista_apagar"})],
    "project_manage": [("projetos", None)],
    "note_manage": [("listas_notas", {"nota_buscar", "notas", "nota_guardar", "nota_apagar"})],
    "ai_cost": [("custo", None)],
    "research": [("pesquisa_web", None)],
    "agenda_import": [("agenda", {"importar_foto"})],
    "agenda_import_edit": [("agenda", {"importar_editar"})],
    "correct_recent": [("acoes_recentes", {"corrigir", "desfazer_ultimas"})],
    "memory_manage": [("memoria", None)],
    "clarify": [],       # responde com uma pergunta, sem gravar
    "chat": [],          # responde em texto, sem gravar (anotar um fato na memoria e permitido)
}

# campo de acao do roteador -> acao do agente
ACOES: dict[str, dict[str, set[str]]] = {
    "fin_action": {},   # preenchido abaixo a partir do mapa da ferramenta
    "list_action": {"create": {"lista_criar", "lista_adicionar"}, "show": {"lista_ver"}, "add": {"lista_adicionar"}, "remove": {"lista_tirar_item"},
                    "check": {"lista_marcar"}, "uncheck": {"lista_desmarcar"}, "clear": {"lista_limpar"}, "delete": {"lista_apagar"}, "lists": {"listas"}},
    "note_action": {"save": {"nota_guardar"}, "search": {"nota_buscar"}, "list": {"notas"}, "delete": {"nota_apagar"}},
    "project_action": {"create": {"criar"}, "show": {"ver"}, "list": {"listar"}, "add_tasks": {"adicionar_tarefas", "sugerir_tarefas"},
                       "complete_task": {"concluir_tarefa"}, "reopen_task": {"reabrir_tarefa"}, "set_urgent": {"marcar_urgente"},
                       "set_due": {"definir_prazo"}, "rename": {"renomear"}, "delete": {"apagar"}, "overdue": {"atrasadas"}},
    "ev_action": {"move": {"mover", "corrigir"}, "cancel": {"cancelar"}, "free": {"horario_livre"}, "promote": {"lembrete_vira_compromisso"}},
    "contact_action": {"save": {"contato_salvar"}, "list": {"contatos"}, "remove": {"contato_apagar"}, "group_save": {"grupo_salvar"},
                       "group_list": {"grupos"}, "group_remove": {"grupo_apagar"}, "place_save": {"lugar_salvar"},
                       "place_list": {"lugares"}, "place_remove": {"lugar_apagar"}},
    "mem_action": {"forget": {"esquecer"}, "list": {"listar"}, "switch_on": {"ligar"}, "switch_off": {"desligar"}},
}

# campo do roteador -> parametros do agente onde o valor pode aparecer
CAMPOS: dict[str, list[str]] = {
    "title": ["titulo", "descricao", "texto", "projeto", "tarefa", "busca", "compromisso", "item"],
    "time": ["hora", "nova_hora", "hora_tomar"], "date": ["data", "nova_data", "prazo", "data_inicio"],
    "amount": ["valor"], "budget_amount": ["valor"], "item": ["item"], "location": ["local", "endereco"],
    "range_start": ["data_inicio", "data"], "range_end": ["data_fim", "data_inicio", "data"],
    "list_items": ["itens"], "list_name": ["lista"], "lead_minutes": ["antecedencia_min"], "repeat_freq": ["repete"],
    "recurring_day": ["dia_fixo"], "installments": ["parcelas"], "person": ["pessoa", "descricao"], "category": ["categoria"],
    "project_name": ["projeto"], "project_tasks": ["tarefas"], "take_time": ["hora_tomar"], "units_left": ["restam"],
    "units_total": ["quantidade"], "item_kind": ["tipo"], "contact_email": ["email"], "contact_name": ["nome"],
    "group_name": ["grupo", "nome"], "invitees": ["convidados"], "pref_no_emoji": ["sem_emoji"], "pref_nickname": ["apelido"],
    "pref_summary_time": ["resumo_manha"], "pref_lead_minutes": ["aviso_antes_min"], "fin_kind": ["tipo"], "period": ["periodo"],
    "mem_ref": ["referencia", "texto", "interruptor"], "fin_items": ["itens"], "mem_facts": ["texto"],
}
VALORES = {"repeat_freq": {"daily": "diario", "weekly": "semanal", "monthly": "mensal", "yearly": "anual"},
           "fin_kind": {"expense": {"gasto", None}, "income": "receita"}}
FORA_DO_ESCOPO = {"new_person": "oferta de salvar pessoa (desligada no produto)", "new_place": "oferta de salvar lugar (desligada no produto)",
                  "stop_reminder": None}
DOW = {"segunda": 0, "terca": 1, "quarta": 2, "quinta": 3, "sexta": 4, "sabado": 5, "domingo": 6}


def _n(s: Any) -> str:
    s = unicodedata.normalize("NFD", str(s).lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")


def _montar_fin() -> None:
    from .ferramentas import financas
    inv: dict[str, set[str]] = {}
    for acao, sql in financas.MAPA.items():
        inv.setdefault(sql, set()).add(acao)
    ACOES["fin_action"] = inv


_montar_fin()


def _datas(spec: str, hoje: date) -> set[str]:
    if spec == "hoje":
        return {hoje.isoformat()}
    if spec == "amanha":
        return {(hoje + timedelta(days=1)).isoformat()}
    if spec == "hoje_ou_amanha":
        return {hoje.isoformat(), (hoje + timedelta(days=1)).isoformat()}
    if spec.startswith("md:"):
        return {f"{hoje.year}-{spec[3:]}", f"{hoje.year + 1}-{spec[3:]}"}
    if spec.startswith("dow:"):
        wd = DOW[spec[4:]]
        d = hoje + timedelta(days=(wd - hoje.weekday()) % 7)
        return {d.isoformat(), (d + timedelta(days=7)).isoformat()}
    if spec == "inicio_mes":
        return {hoje.replace(day=1).isoformat()}
    if spec == "fim_mes":
        prox = (hoje.replace(day=28) + timedelta(days=4)).replace(day=1)
        return {(prox - timedelta(days=1)).isoformat()}
    if spec == "fim_semana":
        dom = hoje + timedelta(days=(6 - hoje.weekday()) % 7)
        return {dom.isoformat(), (dom - timedelta(days=1)).isoformat(), (dom + timedelta(days=7)).isoformat()}
    return set()


def _casa(esp: Any, v: Any, hoje: date, agora: datetime) -> bool:
    """Um valor de argumento satisfaz o esperado?"""
    if not isinstance(esp, dict):
        if isinstance(esp, list):
            return any(_casa(e, v, hoje, agora) for e in esp)
        if isinstance(esp, bool):
            return v is esp
        if isinstance(esp, (int, float)):
            try:
                return abs(float(v) - float(esp)) < 0.01
            except (TypeError, ValueError):
                return False
        if isinstance(esp, set):
            return v in esp
        return v is not None and _n(v).lstrip("0") == _n(esp).lstrip("0")
    if "nulo" in esp:
        return v in (None, "", [])
    if "naonulo" in esp:
        return v not in (None, "", [])
    if v is None:
        return False
    if "contem" in esp:
        return _n(esp["contem"]) in _n(v if not isinstance(v, list) else " ".join(map(str, v)))
    if "contem_algum" in esp:
        t = _n(v if not isinstance(v, list) else " ".join(map(str, v)))
        return any(_n(x) in t for x in esp["contem_algum"])
    if "data" in esp:
        return str(v) in _datas(esp["data"], hoje)
    if "data_em" in esp:
        return any(str(v) in _datas(s, hoje) for s in esp["data_em"])
    if "lista_contem" in esp:
        t = _n(" ".join(map(str, v)) if isinstance(v, list) else v)
        return all(_n(x) in t for x in esp["lista_contem"])
    if "lista_tamanho" in esp:
        return isinstance(v, list) and len(v) == esp["lista_tamanho"]
    if "em" in esp:
        return any(_casa(x, v, hoje, agora) for x in esp["em"])
    if "itens_valores" in esp:
        vals = sorted(float(i.get("valor") or 0) for i in v) if isinstance(v, list) and all(isinstance(i, dict) for i in v) else []
        return vals == sorted(map(float, esp["itens_valores"]))
    if "hora_rel_min" in esp:
        try:
            h, m = map(int, str(v).split(":"))
        except ValueError:
            return False
        alvo = agora + timedelta(minutes=esp["hora_rel_min"])
        return abs((h * 60 + m) - (alvo.hour * 60 + alvo.minute)) <= esp.get("tol", 15)
    return False


@dataclass
class Veredito:
    id: str
    grupo: str
    ok: bool
    medido: bool = True
    motivos: list[str] = field(default_factory=list)
    chamadas: list[str] = field(default_factory=list)
    tokens_in: int = 0
    tokens_out: int = 0


def _aceita(intents: list[str], c: Chamada) -> bool:
    for i in intents:
        for ferr, acoes in INTENCOES.get(i, []):
            if c.nome == ferr and (acoes is None or c.args.get("acao") in acoes):
                return True
    return False


def julgar(caso: dict, chamadas: list[Chamada], texto: str, hoje: date, agora: datetime) -> Veredito:
    """Compara o que o modelo chamou com o esperado do caso."""
    v = Veredito(caso["id"], caso["grupo"], True, chamadas=[f"{c.nome}.{c.args.get('acao')}" for c in chamadas])
    esp = caso.get("esperado")
    if caso.get("medir") is False or not esp:
        v.medido, v.motivos = False, [caso.get("motivo_nao_medido") or "sem esperado"]
        return v
    if "estado" in caso:
        v.medido, v.motivos = False, ["depende da oferta de salvar pendente, desligada no produto"]
        return v
    grava = [c for c in chamadas if not (c.nome == "memoria" and c.args.get("acao") in ("anotar", "listar"))]

    def falha(m: str) -> None:
        v.ok = False
        v.motivos.append(m)

    if "acoes" in esp:                      # varios pedidos numa mensagem
        for a in esp["acoes"]:
            ints = a["intent"] if isinstance(a["intent"], list) else [a["intent"]]
            achou = any(_aceita(ints, c) and all(_n(p) in _n(json.dumps(c.args, ensure_ascii=False)) for p in a.get("palavras", []))
                        for c in chamadas)
            if not achou:
                falha(f"faltou {'/'.join(ints)} com {a.get('palavras')}")
        return v

    ints = esp.get("intent")
    ints = ints if isinstance(ints, list) else [ints] if ints else []
    so_texto = [i for i in ints if i in ("chat", "clarify")]
    com_ferr = [i for i in ints if i not in ("chat", "clarify")]
    alvo = [c for c in chamadas if _aceita(com_ferr, c)]
    if ints:
        if alvo:
            pass
        elif so_texto and not [c for c in grava if c.nome != "pesquisa_web" or "research" not in ints]:
            pass                            # respondeu em texto, como esperado
        elif so_texto and not grava:
            pass
        else:
            falha(f"esperava {'/'.join(ints)}; chamou {v.chamadas or 'nada'}")
            return v

    for campo, e in (esp.get("campos") or {}).items():
        if campo in FORA_DO_ESCOPO:
            continue
        if campo in ACOES:
            aceitas: set[str] = set()
            for x in (e if isinstance(e, list) else [e]):
                aceitas |= ACOES[campo].get(x, set())
            if not aceitas:
                continue                    # ex.: mem_action offer_yes (fora do escopo)
            if not any(c.args.get("acao") in aceitas for c in (alvo or chamadas)):
                falha(f"{campo}={e}: acao esperada {sorted(aceitas)}")
            continue
        if campo == "mem_facts":
            anot = [c for c in chamadas if c.nome == "memoria" and str(c.args.get("acao")).startswith(("anotar", "criterio"))]
            if isinstance(e, dict) and "nulo" in e:
                if anot:
                    falha("anotou fato que nao era duradouro")
            elif not any(_casa(e, c.args.get("texto"), hoje, agora) for c in anot):
                falha(f"mem_facts: esperava anotar {e}")
            continue
        params = CAMPOS.get(campo)
        if not params:
            continue
        e2 = VALORES.get(campo, {}).get(e, e) if not isinstance(e, (dict, list)) else e
        cand = alvo or chamadas
        if isinstance(e, dict) and "nulo" in e:
            if any(c.args.get(p) not in (None, "", []) for c in cand for p in params[:1]):
                falha(f"{campo}: devia ficar vazio")
            continue
        if not any(_casa(e2, c.args.get(p), hoje, agora) for c in cand for p in params):
            falha(f"{campo}: esperava {e}")

    t = _n(texto)
    if esp.get("resposta_contem_algum") and not alvo and not any(_n(x) in t for x in esp["resposta_contem_algum"]):
        falha(f"resposta devia conter um de {esp['resposta_contem_algum']}")
    if esp.get("resposta_nao_contem") and any(_n(x) in t for x in esp["resposta_nao_contem"]):
        falha("resposta contem termo proibido")
    return v


def carregar(grupo: str | None = None) -> list[dict]:
    casos = json.loads(CASOS.read_text(encoding="utf-8"))["casos"]
    return [c for c in casos if not grupo or c["grupo"] == grupo]


async def rodar_caso(nucleo, usuario, caso: dict, papel: str = "simples", modelo: str | None = None,
                     passos: int = 3) -> Veredito:
    """Pergunta ao modelo o que ele faria, sem executar nada."""
    from .agente.contexto import Ctx, montar_sistema
    ctx = Ctx(nucleo=nucleo, usuario=usuario, texto=caso["mensagem"])
    turnos = [Turno("sistema", await montar_sistema(ctx))]
    for t in caso.get("contexto") or []:
        turnos.append(Turno("usuario" if t.get("r") == "user" else "assistente", t.get("t") or ""))
    turnos.append(Turno("usuario", caso["mensagem"]))
    esquemas = nucleo.registro.esquemas()
    mod = modelo or await nucleo.modelo(papel)
    chamadas: list[Chamada] = []
    texto, tin, tout = "", 0, 0
    for _ in range(passos):
        r = await nucleo.provedor.responder(turnos, esquemas, mod)
        tin, tout = tin + r.tokens_in, tout + r.tokens_out
        if not r.chamadas:
            texto = r.texto
            break
        chamadas += r.chamadas
        turnos.append(Turno("assistente", r.texto, chamadas=r.chamadas))
        for c in r.chamadas:
            turnos.append(Turno("ferramenta", "[resultado simulado da avaliação] ok", chamada_id=c.id))
    agora = ctx.agora
    v = julgar(caso, chamadas, texto, agora.date(), agora.replace(tzinfo=None))
    v.tokens_in, v.tokens_out = tin, tout
    return v


async def rodar(nucleo, usuario, casos: list[dict], modelo: str | None = None, paralelo: int = 4) -> dict:
    sem = asyncio.Semaphore(paralelo)

    async def um(c):
        async with sem:
            try:
                return await rodar_caso(nucleo, usuario, c, modelo=modelo)
            except Exception as e:
                return Veredito(c["id"], c["grupo"], False, motivos=[f"erro: {type(e).__name__}: {e}"[:160]])

    vs = await asyncio.gather(*(um(c) for c in casos))
    medidos = [v for v in vs if v.medido]
    mod = modelo or await nucleo.modelo("simples")
    async with nucleo.banco.anonimo() as cx:
        p = await cx.linha("SELECT usd_per_1m_in, usd_per_1m_out, usd_brl FROM agente.ai_pricing WHERE model = %s", mod)
    custo = None
    if p and medidos:
        tot = sum(v.tokens_in for v in medidos) * float(p["usd_per_1m_in"]) + sum(v.tokens_out for v in medidos) * float(p["usd_per_1m_out"])
        custo = tot / 1e6 * float(p["usd_brl"]) / len(medidos)
    por_grupo: dict[str, list[int]] = {}
    for v in medidos:
        g = por_grupo.setdefault(v.grupo, [0, 0])
        g[0] += 1 if v.ok else 0
        g[1] += 1
    return {"modelo": mod, "casos": len(vs), "medidos": len(medidos), "acertos": sum(1 for v in medidos if v.ok),
            "taxa": round(sum(1 for v in medidos if v.ok) / max(len(medidos), 1) * 100, 1),
            "custo_brl_por_caso": custo, "por_grupo": {g: f"{a}/{t}" for g, (a, t) in sorted(por_grupo.items())},
            "vereditos": vs}


async def _main(args) -> None:
    from .cli import preparar
    from .canais.memoria import CanalMemoria
    from .config import Config
    from .fabrica import montar
    n = montar(Config.do_ambiente(), canal=CanalMemoria())
    await n.banco.abrir()
    try:
        u = await n.usuario(await preparar(n))
        r = await rodar(n, u, carregar(args.grupo), modelo=args.modelo)
        print(f"modelo {r['modelo']} · provedor {n.provedor.nome}")
        print(f"acerto: {r['acertos']}/{r['medidos']} ({r['taxa']}%) · {r['casos'] - r['medidos']} não medidos")
        if r["custo_brl_por_caso"] is not None:
            print(f"custo por caso: R$ {r['custo_brl_por_caso']:.5f}".replace(".", ","))
        print("por grupo:", r["por_grupo"])
        for v in r["vereditos"]:
            if (not v.ok and v.medido) or (args.detalhe and v.medido):
                print(f"  {'OK ' if v.ok else 'ERR'} {v.id}: {v.chamadas} {'; '.join(v.motivos)}")
            elif args.detalhe:
                print(f"  --- {v.id}: não medido ({'; '.join(v.motivos)})")
    finally:
        await n.banco.fechar()


if __name__ == "__main__":
    p = argparse.ArgumentParser(description="Avaliação de paridade com os casos naturais")
    p.add_argument("--modelo")
    p.add_argument("--grupo")
    p.add_argument("--detalhe", action="store_true")
    asyncio.run(_main(p.parse_args()))
