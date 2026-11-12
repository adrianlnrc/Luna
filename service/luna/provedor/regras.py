"""Provedor local de regras: entende um conjunto pequeno de frases SEM chamar nenhuma API.

Serve para rodar e demonstrar o agente localmente sem chave (python -m luna.cli). Nao substitui um modelo:
com LUNA_OPENAI_API_KEY definida o servico usa o provedor real.
"""
from __future__ import annotations

import itertools
import re
import unicodedata
from datetime import date, datetime, timedelta

from .base import Chamada, RespostaModelo, Turno

_seq = itertools.count(1)
DIAS = {"segunda": 0, "terca": 1, "quarta": 2, "quinta": 3, "sexta": 4, "sabado": 5, "domingo": 6}


def _n(s: str) -> str:
    s = unicodedata.normalize("NFD", s.lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")


def _c(nome: str, **args) -> Chamada:
    return Chamada(id=f"r{next(_seq)}", nome=nome, args=args)


def _valor(t: str) -> float | None:
    m = re.search(r"(?:r\$\s*)?(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?", t)
    if not m:
        return None
    return float(m.group(1).replace(".", "") + "." + (m.group(2) or "0"))


def _hora(t: str) -> str | None:
    m = re.search(r"\b(?:as|às)?\s*(\d{1,2})\s*(?:h|:)\s*(\d{2})?\b", t)
    if not m or int(m.group(1)) > 23:
        return None
    return f"{int(m.group(1)):02d}:{m.group(2) or '00'}"


def _data(t: str, hoje: date) -> str | None:
    n = _n(t)
    if "depois de amanha" in n:
        return (hoje + timedelta(days=2)).isoformat()
    if "amanha" in n:
        return (hoje + timedelta(days=1)).isoformat()
    if re.search(r"\bhoje\b", n):
        return hoje.isoformat()
    m = re.search(r"\bdia (\d{1,2})(?:/(\d{1,2}))?", n) or re.search(r"\b(\d{1,2})/(\d{1,2})\b", n)
    if m:
        d, mes = int(m.group(1)), int(m.group(2)) if m.group(2) else hoje.month
        try:
            dt = date(hoje.year, mes, d)
        except ValueError:
            return None
        if dt < hoje:
            dt = date(hoje.year + (1 if m.group(2) else 0), mes if m.group(2) else (mes % 12) + 1, d) if True else dt
        return dt.isoformat()
    for nome, wd in DIAS.items():
        if re.search(r"\b" + nome, n):
            return (hoje + timedelta(days=(wd - hoje.weekday()) % 7 or 7)).isoformat()
    return None


class ProvedorRegras:
    nome = "regras"

    def _hoje(self, turnos: list[Turno]) -> date:
        m = re.search(r"HOJE: [^,]+, (\d{2})/(\d{2})/(\d{4})", turnos[0].texto if turnos else "")
        return date(int(m.group(3)), int(m.group(2)), int(m.group(1))) if m else datetime.now().date()

    def _decidir(self, texto: str, hoje: date) -> list[Chamada] | str:
        t, n = texto.strip(), _n(texto)
        if re.search(r"\b(posso|devo|vale a pena|consigo|da pra|como esta minha semana|como estou|minha situacao)\b", n):
            return [_c("retrato", acao="ver", dias=7),
                    _c("agenda", acao="listar", data_inicio=hoje.isoformat(), data_fim=(hoje + timedelta(days=7)).isoformat())]
        if re.search(r"\b(pesquisa|pesquise|cotacao|qual o preco|quanto custa|regra d)", n):
            return [_c("pesquisa_web", acao="buscar", consulta=t)]
        m = re.search(r"\b(?:quero gastar no maximo|limite(?: geral)?(?: de| do mes de)?)\s", n)
        if m and _valor(n[m.end():]) is not None:
            return [_c("financas", acao="limite_definir", valor=_valor(n[m.end():]))]
        m = re.search(r"\b(gastei|paguei|recebi)\b", n)
        if m and _valor(n) is not None:
            desc = re.sub(r"^.*?\d[\d.,]*\s*(reais)?\s*(no|na|em|de|do|da|com)?\s*", "", t, count=1, flags=re.I).strip(" .") or "sem descrição"
            return [_c("financas", acao="lancar", tipo="receita" if m.group(1) == "recebi" else "gasto", valor=_valor(n), descricao=desc)]
        if re.search(r"\b(quanto gastei|resumo do mes|meus gastos)\b", n):
            return [_c("financas", acao="resumo")]
        if re.search(r"\bme lembr", n):
            tit = re.sub(r"(?i)^.*?\b(?:de|que|para|pra)\b\s+", "", re.sub(
                r"(?i)\b(hoje|amanh[ãa]|depois de amanh[ãa]|dia \d{1,2}(/\d{1,2})?|(?:às|as)\s*\d{1,2}(?:h|:\d{2})\d{0,2}|\d{1,2}h\d{0,2}|"
                r"segunda|ter[çc]a|quarta|quinta|sexta|s[áa]bado|domingo)\b", "", t), count=1).strip(" ,.") or "lembrete"
            h = _hora(n)
            if not h:
                return "A que horas você quer que eu te lembre?"
            return [_c("lembretes", acao="criar", titulo=tit, data=_data(t, hoje), hora=h)]
        m = re.search(r"\blista (?:de |do |da )?([\w ]+?):\s*(.+)$", t, flags=re.I)
        if m:
            return [_c("listas_notas", acao="lista_adicionar", lista=m.group(1).strip(), itens=[x.strip() for x in re.split(r",| e ", m.group(2)) if x.strip()])]
        m = re.search(r"^\s*anota[:\s]+(.+)$", t, flags=re.I)
        if m:
            return [_c("listas_notas", acao="nota_guardar", texto=m.group(1).strip())]
        if re.search(r"\b(o que tenho|minha agenda|meus compromissos)\b", n):
            d = _data(t, hoje) or hoje.isoformat()
            return [_c("agenda", acao="listar", data_inicio=d, data_fim=d if "semana" not in n else (hoje + timedelta(days=7)).isoformat())]
        m = re.search(r"\b(?:marca|agenda|reuniao|consulta|dentista|jantar|almoco)\b", n)
        if m and _hora(n):
            tit = re.sub(r"(?i)\b(marca|agenda)r?\b|\b(hoje|amanh[ãa]|dia \d{1,2}(/\d{1,2})?|(?:às|as)\s*\d{1,2}(?:h|:\d{2})\d{0,2}|\d{1,2}h\d{0,2}|"
                         r"segunda|ter[çc]a|quarta|quinta|sexta|s[áa]bado|domingo)\b", "", t).strip(" ,.") or "Compromisso"
            return [_c("agenda", acao="criar", titulo=tit[:80], data=_data(t, hoje), hora=_hora(n))]
        if re.search(r"\bminhas tarefas\b", n):
            return [_c("tarefas", acao="listar")]
        m = re.search(r"^\s*(?:nunca|sempre)\b.+", t, flags=re.I)
        if m:
            return [_c("memoria", acao="criterio_pedido", texto=t)]
        if re.search(r"\b(oi|ola|bom dia|boa tarde|boa noite)\b", n):
            return "Oi! Sou a Luna em modo de demonstração (sem modelo de IA). Tente: \"gastei 42 no mercado\", \"me lembra amanhã às 9h de ligar pro contador\" ou \"posso aceitar o jantar de sexta?\"."
        return ("Estou no modo de demonstração, sem modelo de IA, e só entendo frases simples: gastos, lembretes com hora, listas, "
                "\"o que tenho hoje\", \"quanto gastei\" e perguntas com \"posso...\". Defina LUNA_OPENAI_API_KEY para a conversa completa.")

    def _fechar(self, turnos: list[Turno]) -> str:
        res = []
        for t in turnos:
            if t.papel == "ferramenta":
                corpo = t.texto.split("\n", 1)[1] if "\n" in t.texto else t.texto
                res.append(corpo)
        return "Juntei o que encontrei:\n\n" + "\n\n".join(res) if res else "Feito."

    async def responder(self, turnos: list[Turno], ferramentas: list[dict], modelo: str, esquema: dict | None = None) -> RespostaModelo:
        ultimo = turnos[-1] if turnos else Turno("usuario", "")
        if ultimo.papel in ("ferramenta", "sistema") and any(t.papel == "ferramenta" for t in turnos):
            return RespostaModelo(texto=self._fechar(turnos), tokens_in=sum(len(t.texto) for t in turnos) // 4, tokens_out=60, modelo=modelo, estimado=True)
        texto = next((t.texto for t in reversed(turnos) if t.papel == "usuario"), "")
        r = self._decidir(texto, self._hoje(turnos))
        nomes = {f["name"] for f in ferramentas}
        tin = sum(len(t.texto) for t in turnos) // 4
        if isinstance(r, str):
            return RespostaModelo(texto=r, tokens_in=tin, tokens_out=len(r) // 4, modelo=modelo, estimado=True)
        r = [c for c in r if c.nome in nomes]
        if not r:
            return RespostaModelo(texto=self._fechar(turnos), tokens_in=tin, tokens_out=40, modelo=modelo, estimado=True)
        return RespostaModelo(chamadas=r, tokens_in=tin, tokens_out=40, modelo=modelo, estimado=True)

    async def transcrever(self, audio: bytes, nome: str, modelo: str) -> tuple[str, int]:
        return "", 0
