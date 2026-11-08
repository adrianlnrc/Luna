#!/usr/bin/env python3
"""Confere se db/current/ esta em dia com as migracoes e emite alertas.

Recompoe tudo em memoria (mesma logica do build_current.py), compara com os
arquivos de db/current/ e imprime:
  - ERRO  : arquivo faltando, sobrando ou diferente (rode build_current.py);
  - ALERTA: sobrecarga viva (mesmo nome, assinaturas diferentes), mudanca de
            retorno/nome de parametro em CREATE OR REPLACE, EXECUTE dinamico
            nao analisavel, divergencia entre o parser e uma contagem por regex.
Codigo de saida: 0 em dia; 1 desatualizado; 2 se --strict e houver alertas.
Nao conecta a banco. Uso: python3 check_current.py [--strict]
"""
import os
import sys

import build_current as b


def main():
    strict = "--strict" in sys.argv
    out, model, files, ignored, rc = b.build_outputs()
    errors, alerts = [], []

    expected = set(out)
    present = set()
    for root, _, fs in os.walk(b.HERE):
        for f in fs:
            rel = os.path.relpath(os.path.join(root, f), b.HERE)
            if rel.startswith("functions" + os.sep) and f.endswith(".sql"):
                present.add(rel.replace(os.sep, "/"))
    if os.path.exists(b.INDEX_FILE):
        present.add("INDEX.md")
    for rel in sorted(expected - present):
        errors.append("faltando: " + rel)
    for rel in sorted(present - expected):
        errors.append("sobrando (nao corresponde a nenhuma funcao atual): " + rel)
    for rel in sorted(expected & present):
        with open(os.path.join(b.HERE, rel), encoding="utf-8") as fh:
            if fh.read() != out[rel]:
                errors.append("desatualizado: " + rel)

    for (schema, name), recs in sorted(b.overloads(model).items()):
        alerts.append("sobrecarga viva: %s -> %s" % (
            name, " | ".join("(%s) vinda de %s" % (", ".join(r.types) or "sem args", r.migration) for r in recs)))
    for kind, mig, txt in model.events:
        if kind == "nova_assinatura":
            continue  # ja coberto por 'sobrecarga viva' se ainda existir; senao foi resolvida por DROP/RENAME
        alerts.append("%s: %s" % (mig, txt))
    for kind, mig, txt in model.events:
        if kind == "nova_assinatura":
            names = {(r.schema, r.name) for r in model.live.values()}
            nm = txt.split("(")[0]
            if not any(n == nm for _, n in names if len(b.overloads(model).get(("agente", n), [])) > 1):
                alerts.append("%s: %s (a antiga nao esta mais viva: DROP/RENAME posterior)" % (mig, txt))
    for mig, line, txt in model.ambiguous:
        alerts.append("ambiguo %s:%d %s" % (mig, line, txt))
    for w in model.warnings:
        alerts.append("aviso: " + w)
    for f in files:
        if rc[f] != model.per_file_found.get(f, 0):
            alerts.append("%s: regex achou %d CREATE FUNCTION, o parser registrou %d (confira)" % (
                f, rc[f], model.per_file_found.get(f, 0)))

    print("migracoes: %d | funcoes atuais: %d | ignorados: %s" % (len(files), len(model.live), ", ".join(ignored) or "-"))
    for e in errors:
        print("ERRO   ", e)
    for a in alerts:
        print("ALERTA ", a)
    if errors:
        print("\ndb/current/ DESATUALIZADO: rode  python3 db/current/build_current.py")
        return 1
    print("\ndb/current/ em dia com as migracoes (%d alertas)." % len(alerts))
    return 2 if (strict and alerts) else 0


if __name__ == "__main__":
    sys.exit(main())
