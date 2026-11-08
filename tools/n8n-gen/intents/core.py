"""Registro de Intencoes: tipos e motor de injecao.

Uma Intencao declara tudo o que o gerador precisa costurar nos nos 'Montar pedido a IA', 'Interpretar resposta',
'Preparar envio' e 'Buscar usuario', mais os nos de tratamento e a rota no Roteador. O motor injeta cada parte em
ANCORAS FIXAS (constantes abaixo), no mesmo lugar e na mesma ordem em que os patches faziam, entao a ordem de
registro/aplicacao importa so entre Intencoes que usam a mesma ancora.
"""
import types
from dataclasses import dataclass, field
from typing import Callable, List, Optional, Tuple

# ---- ancoras (strings que existem no codigo gerado ate antes do patch_zz_compact) ----
A_ENUM = "'clarify', 'chat'] },"                       # fim do enum de intents (insere antes de 'clarify')
A_HINT = ", clarify (falta informacao essencial"       # regra INTENTS: descricao curta de cada intent
A_SCHEMA_END = "\n};\nconst schema = {"                 # fim do objeto props do schema
A_RULES = "  'FINANCAS categorias: "                    # regras estaticas entram antes desta linha
A_PROMPT = "prompt += 'MENSAGEM ATUAL DO USUARIO'"      # contexto variavel entra antes da mensagem atual
A_INTERP = "if (out.intent === 'finance') {"            # blocos de 'Interpretar resposta'
A_SEND = "const html = text.split('**')"                # pos-processamento de 'Preparar envio'
A_USERQ = " FROM agente.users u WHERE"                  # colunas novas de 'Buscar usuario'

NODE_MP = 'Montar pedido a IA'


def once(code: str, old: str, new: str) -> str:
    """Troca exatamente uma ocorrencia (falha alto se a ancora sumiu ou ficou ambigua)."""
    n = code.count(old)
    assert n == 1, ('ancora %d vezes' % n, old[:80])
    return code.replace(old, new, 1)


def safe_rule(s: str) -> str:
    """Regras vivem em strings JS '...': proibido aspas simples, crase, barra invertida e ${."""
    assert "'" not in s and '`' not in s and '\\' not in s and '${' not in s, s[:60]
    return s


def schema_add(code: str, frag: str, sep: str = ",\n", before: Optional[str] = None) -> str:
    """Acrescenta propriedades ao schema da IA (frag sem virgula final): ao fim do objeto props, ou, com before=,
    imediatamente antes desse texto (que deve ocorrer uma vez; frag + sep sao inseridos antes dele)."""
    if before is not None:
        return once(code, before, frag + sep + before)
    return once(code, A_SCHEMA_END, sep + frag + A_SCHEMA_END)


def enum_add(code: str, name: str, after: Optional[str] = None) -> str:
    """Poe 'name' no enum de intents: antes de 'clarify' (padrao) ou logo depois de 'after'."""
    if after is not None:
        return once(code, "'" + after + "', ", "'" + after + "', '" + name + "', ")
    return once(code, A_ENUM, "'" + name + "', " + A_ENUM)


@dataclass
class Edit:
    """Troca ancorada (uma ocorrencia) em parameters[field] de um no. Para o que a Intencao toca fora dos 4 pontos padrao."""
    node: str
    field: str
    old: str
    new: str


@dataclass
class Set:
    """Atribuicao direta em parameters[path...] de um no (ex. ('options','queryReplacement'))."""
    node: str
    path: Tuple[str, ...]
    value: str


@dataclass
class Intent:
    name: str                                   # valor do enum, ex. 'correct_recent'
    also: List[str] = field(default_factory=list)        # outras intents do mesmo modulo (entram no enum; cada uma precisa de rota)
    internal: List[str] = field(default_factory=list)    # intents produzidas por codigo (nao estao no enum; so rota). Ex. invite_event
    base: bool = False                          # intent do modelo original (main.json + texto base do gen.py): so entra no registro p/ a checagem; nao e aplicada
    extends: Optional[str] = None               # estagio/extensao de uma intent base (finance, create_reminder...): sem enum nem rota proprios
    enum: bool = True                           # False: o nome ja entra no enum por outro patch (transitorio ate migrar patch_f2a/f4_schema)
    enum_after: Optional[str] = None            # posicao no enum: depois desta intent (padrao: antes de 'clarify')
    also_after: Optional[dict] = None           # idem para as de 'also': {nome: depois_de}
    schema_parts: List[Tuple[str, str, Optional[str]]] = field(default_factory=list)  # trechos extras do schema: (trecho, separador, inserir_antes_de)
    schema_before: Optional[str] = None         # insere o schema antes deste texto (padrao: fim de props)
    hint: str = ''                              # descricao curta na regra INTENTS ('nome (quando usar)')
    schema: str = ''                            # propriedades novas do schema (texto JS, sem virgula final)
    schema_sep: str = ",\n"                     # separador antes do trecho do schema
    rules: List[str] = field(default_factory=list)       # regras estaticas do prompt (texto sem aspas externas)
    raw_rules: str = ''                         # bloco de linhas JS ja formatadas ('  ...,\n' cada), p/ regras com trecho dinamico
    prompt_ctx: str = ''                        # JS inserido antes da mensagem atual (contexto variavel)
    interpret_js: str = ''                      # JS inserido em 'Interpretar resposta' (normaliza campos da IA)
    send_js: str = ''                           # JS inserido em 'Preparar envio' antes de montar o html
    user_cols: List[str] = field(default_factory=list)   # colunas SQL extras em 'Buscar usuario'
    edits: List[Edit] = field(default_factory=list)
    sets: List[Set] = field(default_factory=list)
    route: Optional[Tuple[str, str]] = None     # (chave da saida no Roteador, 1o no do tratamento)
    routes: List[Tuple[str, str, str]] = field(default_factory=list)  # rotas extras: (chave, intent, 1o no)
    build: Optional[Callable] = None            # build(): cria nos/conexoes. Roda COM AS GLOBAIS DO gen.py (nodes, conns, byname, pg_node, setc, rep...);
                                                # nomes que precisam sobreviver (como nos patches) entram com `global`


class Registry:
    def __init__(self):
        self._by = {}
        self.applied = []

    def register(self, it: Intent) -> Intent:
        assert it.name not in self._by, 'intent duplicada: ' + it.name
        self._by[it.name] = it
        return it

    def names(self):
        """Todas as intents do enum que o registro possui (principais + 'also')."""
        return [n for it in self._by.values() if not it.extends for n in [it.name] + list(it.also)]

    def internal_names(self):
        """Intents internas (so rota, fora do enum)."""
        return [n for it in self._by.values() for n in it.internal]

    def get(self, name):
        return self._by[name]

    def apply(self, name: str, g: dict) -> None:
        """Injeta a Intencao no workflow em construcao. g = globals() do gen.py (nodes, conns, byname, NEW, helpers)."""
        it = self._by[name]
        assert not it.base, 'intent base nao se aplica: ' + name
        assert name not in self.applied, 'ja aplicada: ' + name
        byname = g['_refresh']()
        P = lambda node: byname[node]['parameters']

        mp = P(g['NEW'])['jsCode']
        if it.enum and not it.extends:
            mp = enum_add(mp, it.name, it.enum_after)
            for extra in it.also:
                mp = enum_add(mp, extra, (it.also_after or {}).get(extra))
        if it.hint:
            mp = once(mp, A_HINT, ", " + it.hint + A_HINT)
        if it.schema:
            mp = schema_add(mp, it.schema, it.schema_sep, it.schema_before)
        for frag, sep, before in it.schema_parts:
            mp = schema_add(mp, frag, sep, before)
        if it.rules:
            mp = once(mp, A_RULES, ''.join("  '" + safe_rule(r) + "',\n" for r in it.rules) + A_RULES)
        if it.raw_rules:
            mp = once(mp, A_RULES, it.raw_rules + A_RULES)
        if it.prompt_ctx:
            mp = once(mp, A_PROMPT, it.prompt_ctx + "\n" + A_PROMPT)
        P(g['NEW'])['jsCode'] = mp

        if it.interpret_js:
            P('Interpretar resposta')['jsCode'] = once(P('Interpretar resposta')['jsCode'], A_INTERP, it.interpret_js + "\n" + A_INTERP)
        if it.send_js:
            P('Preparar envio')['jsCode'] = once(P('Preparar envio')['jsCode'], A_SEND, it.send_js + "\n" + A_SEND)
        if it.user_cols:
            q = P('Buscar usuario')
            q['query'] = once(q['query'], A_USERQ, ''.join(', ' + c for c in it.user_cols) + A_USERQ)
        for e in it.edits:
            P(e.node)[e.field] = once(P(e.node)[e.field], e.old, e.new)
        for s in it.sets:
            d = P(s.node)
            for k in s.path[:-1]:
                d = d[k]
            d[s.path[-1]] = s.value

        if it.build:
            fn = it.build
            types.FunctionType(fn.__code__, g, fn.__name__, fn.__defaults__)()
        if it.route:
            g['add_route'](it.route[0], it.name, it.route[1])
        for key, intent, first in it.routes:
            g['add_route'](key, intent, first)
        self.applied.append(name)
