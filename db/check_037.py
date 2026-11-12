#!/usr/bin/env python3
"""Confere offline que 037_menu_ajustes.sql so difere da 036 na dica e nos titulos da area 8.
Nao conecta a banco. Uso: python3 check_037.py (sai 1 se houver outra diferenca)."""
import difflib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def corpo(nome):
    s = open(os.path.join(HERE, nome), encoding="utf-8").read()
    return s[s.index("CREATE OR REPLACE FUNCTION"):].splitlines()


DICA_V = "Pode mandar vários pedidos juntos: eu faço todos e mostro num Feito:. Se errar, toque em Desfazer tudo."
DICA_N = 'Pode mandar vários pedidos juntos: eu faço todos e mostro num resumo "Feito". Se errar, toque em Desfazer tudo.'
PERMITIDAS = {
    ("Fotos, áudio e pesquisa", "Fotos e pesquisa"),
    ("Fotos, áudio e pesquisa: ver mais", "Fotos e pesquisa: ver mais"),
    (DICA_V, DICA_N),
}


def normaliza(l):
    return l.strip().replace("WHEN 8 THEN $m$", "").replace("dica text := '", "").rstrip("';").replace("$m$", "")


a, b = corpo("036_menu_secretaria.sql"), corpo("037_menu_ajustes.sql")
erros, achadas = [], []
if len(a) != len(b):
    erros.append("numero de linhas difere: %d vs %d" % (len(a), len(b)))
else:
    for n, (x, y) in enumerate(zip(a, b), 1):
        if x == y:
            continue
        par = (normaliza(x), normaliza(y))
        if par in PERMITIDAS:
            achadas.append((n, par[0], par[1]))
        else:
            erros.append("linha %d: %r -> %r" % (n, x, y))
    esperadas = {DICA_V: 2, "Fotos, áudio e pesquisa": 1, "Fotos, áudio e pesquisa: ver mais": 1}
    for v, qtd in esperadas.items():
        got = sum(1 for _, o, _ in achadas if o == v)
        if got != qtd:
            erros.append("esperava %d troca(s) de %r, achei %d" % (qtd, v, got))
s37 = open(os.path.join(HERE, "037_menu_ajustes.sql"), encoding="utf-8").read()
if "RENAME" in s37 or re.search(r"\bDO \$", s37):
    erros.append("037 nao deve conter bloco DO/RENAME")
if "SET search_path" not in s37:
    erros.append("037 sem SET search_path")
for n, o, nw in achadas:
    print("linha %d: %s -> %s" % (n, o, nw))
if erros:
    print("ERRO:\n" + "\n".join(erros))
    sys.exit(1)
print("OK: %d diferencas, todas permitidas (dica x2, titulo area 8 x2)." % len(achadas))
