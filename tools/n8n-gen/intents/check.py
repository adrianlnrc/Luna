"""Checagem de consistencia das Intencoes no workflow gerado.

    python3 intents/check.py [modified.json]     (codigo de saida 1 se houver ERRO)

Regras (intent no enum <=> tem rota no Roteador <=> a rota liga a um no que existe e que chega a 'Preparar envio'):
  ERRO  intent registrada: ausente do enum, sem rota, rota sem ligacao, ligacao para no inexistente, ou sem caminho ate 'Preparar envio'
  ERRO  intent do enum sem rota (e fora das excecoes abaixo)
  ERRO  rota do Roteador para saida sem ligacao ou ligada a no inexistente
  AVISO rota sem entrada no enum (intent produzida por codigo, nao pela IA)
"""
import json
import os
import re
import sys

ROUTER = 'Roteador de intencao'
MP = 'Montar pedido a IA'
SEND = 'Preparar envio'
FALLBACK = {'clarify', 'chat'}                                  # caem na saida de fallback do Roteador
TASK_VIA_ACTION = {'create_task', 'list_tasks', 'complete_task'}  # roteadas por task_action, nao por intent


def _enum(mp_code):
    m = re.search(r"intent: \{ type: 'string', enum: \[([^\]]*)\]", mp_code)
    assert m, 'enum de intents nao encontrado em ' + MP
    return re.findall(r"'([a-z_]+)'", m.group(1))


def _routes(router):
    p = router['parameters']
    out = p['output']
    m = re.search(r"\(\{(.*?)\}\)\[\$json\.intent\]", out)
    assert m, 'mapa de rotas nao encontrado em ' + ROUTER
    mapa = json.loads('{' + m.group(1) + '}')
    t = re.search(r"\$json\.task_action \? (\d+)", out)
    return mapa, (int(t.group(1)) if t else None), p['numberOutputs'] - 1


def _reaches(conns, start, goal):
    seen, todo = set(), [start]
    while todo:
        n = todo.pop()
        if n == goal:
            return True
        if n in seen:
            continue
        seen.add(n)
        for lst in conns.get(n, {}).get('main', []):
            todo += [t['node'] for t in lst]
    return False


def check(w, registered=(), internal=()):
    """w = dict do workflow (nodes/connections). registered = nomes de Intencoes do registro (checagem estrita).
    Retorna (erros, avisos)."""
    err, warn = [], []
    names = {n['name']: n for n in w['nodes']}
    conns = w['connections']
    enum = _enum(names[MP]['parameters']['jsCode'])
    mapa, task_idx, fb_idx = _routes(names[ROUTER])
    outs = conns.get(ROUTER, {}).get('main', [])

    def handler_problems(idx, intent):
        if idx >= len(outs) or not outs[idx]:
            return ['%s: saida %d do Roteador sem ligacao' % (intent, idx)]
        probs = []
        for t in outs[idx]:
            if t['node'] not in names:
                probs.append('%s: rota liga ao no inexistente %r' % (intent, t['node']))
            elif not _reaches(conns, t['node'], SEND):
                probs.append('%s: de %r nao ha caminho ate %r' % (intent, t['node'], SEND))
        return probs

    for r in registered:
        if r not in enum:
            err.append('%s: registrada mas ausente do enum' % r)
        if r not in mapa and r not in FALLBACK and r not in TASK_VIA_ACTION:
            err.append('%s: registrada mas sem rota no Roteador' % r)
    for it in enum:
        if it in FALLBACK:
            continue
        if it in TASK_VIA_ACTION:
            idx = task_idx
        else:
            idx = mapa.get(it)
        if idx is None:
            err.append('%s: no enum mas sem rota' % it)
            continue
        for p in handler_problems(idx, it):
            (err if (it in registered) else warn).append(p)
    for it in internal:
        if it in enum:
            err.append('%s: declarada interna mas esta no enum' % it)
        if it not in mapa:
            err.append('%s: interna registrada mas sem rota no Roteador' % it)
    for it, idx in mapa.items():
        if it not in enum:
            ps = handler_problems(idx, it)
            if it in internal:
                err.extend(ps)
            else:
                warn.append('%s: tem rota mas nao esta no enum (produzida por codigo, nao pela IA) e nao esta no registro' % it)
                warn.extend(ps)
    if fb_idx >= len(outs) or not outs[fb_idx]:
        err.append('fallback do Roteador sem ligacao')
    return err, warn


def main(argv):
    here = os.path.dirname(os.path.abspath(__file__))
    path = argv[1] if len(argv) > 1 else os.path.join(here, '..', 'modified.json')
    sys.path.insert(0, os.path.join(here, '..'))
    from intents import REGISTRY
    w = json.load(open(path))
    err, warn = check(w, REGISTRY.names(), REGISTRY.internal_names())
    for x in warn:
        print('AVISO', x)
    for x in err:
        print('ERRO ', x)
    print('intents registradas: %s | erros: %d | avisos: %d' % (', '.join(REGISTRY.names()), len(err), len(warn)))
    return 1 if err else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
