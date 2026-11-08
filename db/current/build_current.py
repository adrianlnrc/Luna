#!/usr/bin/env python3
"""Gera db/current/functions/*.sql: a definicao ATUAL de cada funcao SQL.

Le as migracoes db/NNN_*.sql em ordem numerica (011 < 011b < 012), simula o
efeito sobre as funcoes (CREATE [OR REPLACE] FUNCTION, ALTER FUNCTION ...
RENAME TO, DROP FUNCTION), inclusive dentro de blocos DO e de EXECUTE $tag$..$tag$
(padrao "renomeia a antiga para *_pre_*/*_base e recria"), e escreve a ultima
definicao de cada (nome + tipos dos argumentos).

Nao conecta a banco nenhum. So biblioteca padrao. Uso:  python3 build_current.py
As migracoes NAO sao alteradas; os arquivos .md sao ignorados.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DB_DIR = os.path.dirname(HERE)
OUT_DIR = os.path.join(HERE, "functions")
INDEX_FILE = os.path.join(HERE, "INDEX.md")
DEFAULT_SCHEMA = "agente"

# ----------------------------------------------------------------- tokenizer
W, S, D, Q, P = "w", "s", "d", "q", "p"  # palavra, string, dollar, ident entre aspas, pontuacao


class Tok:
    __slots__ = ("kind", "start", "end", "inner_start", "inner_end", "val")

    def __init__(self, kind, start, end, inner_start=None, inner_end=None, val=None):
        self.kind, self.start, self.end = kind, start, end
        self.inner_start, self.inner_end, self.val = inner_start, inner_end, val


_WORD = re.compile(r"[A-Za-z0-9_\u0080-￿][A-Za-z0-9_$\u0080-￿]*")
_DOLLAR = re.compile(r"\$([A-Za-z_][A-Za-z0-9_]*)?\$")


def tokenize(text):
    """Tokens SQL sem comentarios/espacos. Respeita '...', E'...', "...", $tag$...$tag$, -- e /* */ aninhado."""
    toks, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c.isspace():
            i += 1
        elif text.startswith("--", i):
            j = text.find("\n", i)
            i = n if j < 0 else j + 1
        elif text.startswith("/*", i):
            depth, i = 1, i + 2
            while i < n and depth:
                if text.startswith("/*", i):
                    depth, i = depth + 1, i + 2
                elif text.startswith("*/", i):
                    depth, i = depth - 1, i + 2
                else:
                    i += 1
        elif c == "'":
            prev = toks[-1] if toks else None
            esc = bool(prev and prev.kind == W and prev.end == i and text[prev.start:prev.end] in ("E", "e"))
            j = i + 1
            while j < n:
                if esc and text[j] == "\\":
                    j += 2
                elif text[j] == "'":
                    if j + 1 < n and text[j + 1] == "'":
                        j += 2
                    else:
                        break
                else:
                    j += 1
            val = text[i + 1:j].replace("''", "'")
            toks.append(Tok(S, i, j + 1, i + 1, j, val))
            i = j + 1
        elif c == '"':
            j = i + 1
            while j < n:
                if text[j] == '"':
                    if j + 1 < n and text[j + 1] == '"':
                        j += 2
                        continue
                    break
                j += 1
            toks.append(Tok(Q, i, j + 1, val=text[i + 1:j].replace('""', '"')))
            i = j + 1
        elif c == "$":
            m = _DOLLAR.match(text, i)
            if m:
                tag = m.group(0)
                close = text.find(tag, m.end())
                if close < 0:
                    raise ValueError("dollar-quote %s sem fechamento (offset %d)" % (tag, i))
                toks.append(Tok(D, i, close + len(tag), m.end(), close))
                i = close + len(tag)
            else:  # $1, $2...
                toks.append(Tok(P, i, i + 1))
                i += 1
        else:
            m = _WORD.match(text, i)
            if m:
                toks.append(Tok(W, i, m.end(), val=m.group(0)))
                i = m.end()
            else:
                toks.append(Tok(P, i, i + 1, val=c))
                i += 1
    return toks


def split_statements(toks):
    cur = []
    for t in toks:
        if t.kind == P and t.val == ";":
            if cur:
                yield cur
            cur = []
        else:
            cur.append(t)
    if cur:
        yield cur


def is_w(t, word):
    return t.kind == W and t.val.upper() == word


def is_p(t, ch):
    return t.kind == P and t.val == ch


# ------------------------------------------------------------ signature utils
_MODES = {"IN", "OUT", "INOUT", "VARIADIC"}
_TYPE_ALIAS = {
    "int": "integer", "int4": "integer", "int8": "bigint", "int2": "smallint",
    "bool": "boolean", "timestamptz": "timestamp with time zone",
    "timetz": "time with time zone", "varchar": "character varying",
    "float8": "double precision", "float4": "real", "decimal": "numeric",
    "char": "character",
}
_MULTI_PREFIX = ("double precision", "character varying", "timestamp with", "timestamp without",
                 "time with", "time without", "bit varying")


def norm_type(words):
    s = " ".join(words).lower()
    s = re.sub(r"\s+", " ", s)
    s = re.sub(r"\s*([(),\[\]])\s*", r"\1", s)
    s = re.sub(r"\b(?:public|pg_catalog|agente)\.", "", s)
    s = re.sub(r"\(.*?\)", "", s)  # numeric(10,2) -> numeric (precisao nao distingue sobrecarga)
    base = s
    suffix = ""
    while base.endswith("[]"):
        base, suffix = base[:-2], suffix + "[]"
    base = _TYPE_ALIAS.get(base.strip(), base.strip())
    return base + suffix


def parse_args(text, toks):
    """toks: tokens entre os parenteses. Devolve lista de dicts {mode,name,type,raw}."""
    parts, cur, depth = [], [], 0
    for t in toks:
        if t.kind == P and t.val in "([":
            depth += 1
        elif t.kind == P and t.val in ")]":
            depth -= 1
        if depth == 0 and is_p(t, ","):
            parts.append(cur)
            cur = []
        else:
            cur.append(t)
    if cur:
        parts.append(cur)
    out = []
    for part in parts:
        # corta DEFAULT / = expr
        cut = len(part)
        for k, t in enumerate(part):
            if is_w(t, "DEFAULT") or is_p(t, "="):
                cut = k
                break
        head = part[:cut]
        raw = " ".join(text[t.start:t.end] if t.kind != D else "$$" for t in head)
        mode = "IN"
        if head and head[0].kind == W and head[0].val.upper() in _MODES:
            mode = head[0].val.upper()
            head = head[1:]
        words = []
        for t in head:
            words.append(t.val if t.kind in (W, Q, P) else text[t.start:t.end])
        name = None
        low = " ".join(w for w in words).lower()
        if len(words) >= 2 and not low.startswith(_MULTI_PREFIX) and words[0] not in ("[", "(", ")"):
            # unico caso sem nome com >=2 palavras: tipos multi-palavra (tratado acima)
            # ou "tipo[]"/"tipo(10)" (a segunda palavra seria pontuacao)
            if words[1] not in ("[", "(", ".", "]") and not (len(words) >= 3 and words[1] == "."):
                name, words = words[0], words[1:]
        out.append({"mode": mode, "name": name, "type": norm_type(words), "raw": raw})
    return out


def sig_types(args):
    return tuple(a["type"] for a in args if a["mode"] in ("IN", "INOUT", "VARIADIC"))


def read_qname(toks, i):
    """name | schema.name a partir de toks[i]; devolve (schema, name, novo_i)."""
    def ident(t):
        return t.val.lower() if t.kind == W else t.val
    if i >= len(toks) or toks[i].kind not in (W, Q):
        return None
    a = ident(toks[i])
    if i + 2 < len(toks) and is_p(toks[i + 1], ".") and toks[i + 2].kind in (W, Q):
        return a, ident(toks[i + 2]), i + 3
    return DEFAULT_SCHEMA, a, i + 1


def paren_group(toks, i):
    """toks[i] == '(' -> (tokens internos, indice apos o ')')."""
    depth, j = 0, i
    while j < len(toks):
        if is_p(toks[j], "("):
            depth += 1
        elif is_p(toks[j], ")"):
            depth -= 1
            if depth == 0:
                return toks[i + 1:j], j + 1
        j += 1
    return None, len(toks)


# ----------------------------------------------------------------- simulation
_RET_STOP = {"LANGUAGE", "AS", "IMMUTABLE", "STABLE", "VOLATILE", "SECURITY", "SET", "COST", "ROWS",
             "STRICT", "PARALLEL", "WINDOW", "LEAKPROOF", "CALLED", "RETURNS", "TRANSFORM", "SUPPORT", "NOT"}


class Rec:
    def __init__(self, schema, name, args, ret, text, migration, line, nested):
        self.schema, self.name, self.args, self.ret = schema, name, args, ret
        self.types = sig_types(args)
        self.text, self.migration, self.line, self.nested = text, migration, line, nested
        self.history = [(migration, line)]
        self.renamed_from = None  # (nome_antigo, migracao)

    @property
    def key(self):
        return (self.schema, self.name, self.types)


class Model:
    def __init__(self):
        self.live = {}          # key -> Rec
        self.events = []        # (tipo, migracao, texto)
        self.dropped = []       # (key, migracao)
        self.per_file_found = {}  # migracao -> n CREATE FUNCTION encontrados
        self.ambiguous = []     # (migracao, linha, texto)
        self.warnings = []

    # -- operacoes
    def create(self, rec):
        old = self.live.get(rec.key)
        same_name = [r for r in self.live.values() if (r.schema, r.name) == (rec.schema, rec.name) and r.key != rec.key]
        if same_name:
            self.events.append(("nova_assinatura", rec.migration,
                                "%s(%s) criada com assinatura diferente de %s" % (
                                    rec.name, ", ".join(rec.types),
                                    "; ".join("(%s)" % ", ".join(r.types) for r in same_name))))
        if old:
            rec.history = old.history + [(rec.migration, rec.line)]
            rec.renamed_from = None
            if old.ret != rec.ret and old.ret and rec.ret:
                self.events.append(("retorno_mudou", rec.migration,
                                    "%s: RETURNS %s -> %s (CREATE OR REPLACE falharia sem DROP)" % (rec.name, old.ret, rec.ret)))
            on = [a["name"] for a in old.args if a["mode"] != "OUT"]
            nn = [a["name"] for a in rec.args if a["mode"] != "OUT"]
            if on != nn and any(on) and any(nn):
                self.events.append(("nome_param_mudou", rec.migration,
                                    "%s: nomes de parametros %s -> %s (CREATE OR REPLACE falharia)" % (rec.name, on, nn)))
        self.live[rec.key] = rec

    def rename(self, schema, name, types, new, migration):
        key = (schema, name, types)
        rec = self.live.pop(key, None)
        if rec is None:
            self.warnings.append("%s: ALTER FUNCTION %s(%s) RENAME sem funcao conhecida" % (migration, name, ", ".join(types)))
            return
        rec.name = new
        rec.renamed_from = (key[1], migration)
        self.live[rec.key] = rec

    def drop(self, schema, name, types, migration):
        rec = self.live.pop((schema, name, types), None)
        if rec is None:
            self.warnings.append("%s: DROP FUNCTION %s(%s) sem funcao conhecida" % (migration, name, ", ".join(types)))
        else:
            self.dropped.append((rec.key, migration))


def line_of(text, pos, base):
    return base + text.count("\n", 0, pos)


def return_type(text, toks, i):
    if i < len(toks) and is_w(toks[i], "RETURNS"):
        j, words = i + 1, []
        while j < len(toks) and not (toks[j].kind == W and toks[j].val.upper() in _RET_STOP and words):
            words.append(text[toks[j].start:toks[j].end])
            j += 1
        return norm_type(words)
    return None


def process_sql(model, text, migration, line_base, in_do, nested):
    toks = tokenize(text)
    for stmt in split_statements(toks):
        starts = range(len(stmt)) if in_do else [0]
        handled_do = False
        if not in_do and is_w(stmt[0], "DO"):
            body = next((t for t in stmt[1:] if t.kind in (D, S)), None)
            if body is not None:
                inner = text[body.inner_start:body.inner_end] if body.kind == D else body.val
                process_sql(model, inner, migration, line_of(text, body.inner_start, line_base), True, True)
            continue
        for i in starts:
            t = stmt[i]
            if t.kind != W:
                continue
            u = t.val.upper()
            if u == "CREATE":
                j = i + 1
                if j + 1 < len(stmt) and is_w(stmt[j], "OR") and is_w(stmt[j + 1], "REPLACE"):
                    j += 2
                if j < len(stmt) and is_w(stmt[j], "FUNCTION"):
                    q = read_qname(stmt, j + 1)
                    if not q or q[2] >= len(stmt) or not is_p(stmt[q[2]], "("):
                        model.warnings.append("%s:%d: CREATE FUNCTION nao reconhecido" % (migration, line_of(text, t.start, line_base)))
                        continue
                    schema, name, k = q
                    inner, k2 = paren_group(stmt, k)
                    args = parse_args(text, inner)
                    ret = return_type(text, stmt, k2)
                    src = text[t.start:stmt[-1].end].strip()
                    ls = text.rfind("\n", 0, t.start) + 1
                    indent = text[ls:t.start]
                    if indent and not indent.strip():
                        src = "\n".join(l[len(indent):] if l.startswith(indent) else l
                                        for l in src.split("\n"))
                    rec = Rec(schema, name, args, ret, src, migration, line_of(text, t.start, line_base), nested)
                    model.create(rec)
                    model.per_file_found[migration] = model.per_file_found.get(migration, 0) + 1
                    break  # o corpo e uma string; nao varrer o resto
            elif u == "ALTER" and i + 1 < len(stmt) and is_w(stmt[i + 1], "FUNCTION"):
                q = read_qname(stmt, i + 2)
                if q and q[2] < len(stmt) and is_p(stmt[q[2]], "("):
                    inner, k2 = paren_group(stmt, q[2])
                    if k2 + 2 < len(stmt) + 0 and is_w(stmt[k2], "RENAME") and is_w(stmt[k2 + 1], "TO"):
                        new = stmt[k2 + 2]
                        model.rename(q[0], q[1], sig_types(parse_args(text, inner)),
                                     new.val.lower() if new.kind == W else new.val, migration)
            elif u == "DROP" and i + 1 < len(stmt) and is_w(stmt[i + 1], "FUNCTION"):
                j = i + 2
                if j + 1 < len(stmt) and is_w(stmt[j], "IF") and is_w(stmt[j + 1], "EXISTS"):
                    j += 2
                while j < len(stmt):
                    q = read_qname(stmt, j)
                    if not q or q[2] >= len(stmt) or not is_p(stmt[q[2]], "("):
                        break
                    inner, j = paren_group(stmt, q[2])
                    model.drop(q[0], q[1], sig_types(parse_args(text, inner)), migration)
                    if j < len(stmt) and is_p(stmt[j], ","):
                        j += 1
                    else:
                        break
            elif u == "EXECUTE" and in_do and i + 1 < len(stmt):
                nx = stmt[i + 1]
                if nx.kind in (D, S):
                    inner = text[nx.inner_start:nx.inner_end] if nx.kind == D else nx.val
                    process_sql(model, inner, migration, line_of(text, nx.inner_start, line_base), False, True)
                else:
                    seg = text[stmt[i].start:stmt[-1].end]
                    if re.search(r"(?is)\b(create|drop)\s+(or\s+replace\s+)?function\b|\balter\s+function\b.*\brename\b", seg):
                        model.ambiguous.append((migration, line_of(text, t.start, line_base),
                                                "EXECUTE dinamico (nao literal) menciona CREATE/ALTER/DROP FUNCTION: " + " ".join(seg.split())[:120]))


# --------------------------------------------------------------- file ordering
_MIG = re.compile(r"^(\d+)([a-z]*)_.*\.sql$")


def list_migrations(db_dir=DB_DIR):
    files, ignored = [], []
    for f in os.listdir(db_dir):
        p = os.path.join(db_dir, f)
        if not os.path.isfile(p):
            continue
        m = _MIG.match(f)
        if m:
            files.append(((int(m.group(1)), m.group(2), f), f))
        elif f[:1].isdigit():
            ignored.append(f)
    files.sort()
    return [f for _, f in files], sorted(ignored)


def count_create_function(text):
    """Contagem independente por regex em texto sem comentarios (para conferir o parser)."""
    toks = tokenize(text)
    clean = " ".join(text[t.start:t.end] for t in toks)
    # conta tambem dentro de strings aninhadas (EXECUTE $w$ CREATE FUNCTION ...)
    return len(re.findall(r"(?i)\bcreate\s+(?:or\s+replace\s+)?function\b", clean))


def run_model(db_dir=DB_DIR):
    model = Model()
    files, ignored = list_migrations(db_dir)
    regex_counts = {}
    for f in files:
        with open(os.path.join(db_dir, f), encoding="utf-8") as fh:
            text = fh.read()
        regex_counts[f] = count_create_function(text)
        process_sql(model, text, f, 1, False, False)
    return model, files, ignored, regex_counts


# ----------------------------------------------------------------- output
def sig_str(rec):
    return "%s(%s)" % (rec.name, ", ".join(rec.types))


def file_names(model):
    by_name = {}
    for rec in model.live.values():
        by_name.setdefault((rec.schema, rec.name), []).append(rec)
    names = {}
    for (schema, name), recs in by_name.items():
        prefix = "" if schema == DEFAULT_SCHEMA else schema + "."
        for rec in recs:
            if len(recs) == 1:
                fn = prefix + name + ".sql"
            else:
                suf = "_".join(re.sub(r"[^a-z0-9]+", "", t) or "x" for t in rec.types) or "noargs"
                fn = "%s%s__%s.sql" % (prefix, name, suf)
            names[rec.key] = fn
    return names


def render(rec, names):
    hist = ", ".join("%s:%d" % h for h in rec.history)
    lines = [
        "-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.",
        "-- Funcao: %s.%s(%s)" % (rec.schema, rec.name, ", ".join(a["raw"] for a in rec.args)),
        "-- Origem da definicao atual: %s (linha %d)%s" % (
            rec.migration, rec.line, " [dentro de bloco DO/EXECUTE, criacao condicional]" if rec.nested else ""),
        "-- Definicoes (migracao:linha), da mais antiga a atual: " + hist,
    ]
    if rec.renamed_from:
        lines.append("-- Renomeada de %s para %s em %s; o texto abaixo ainda traz o nome ORIGINAL "
                     "(a funcao no banco chama-se %s)." % (rec.renamed_from[0], rec.name, rec.renamed_from[1], rec.name))
    lines.append("")
    return "\n".join(lines) + rec.text.rstrip() + ("\n" if rec.text.rstrip().endswith(";") else ";\n")


def build_outputs(db_dir=DB_DIR):
    """Devolve (outputs {caminho_relativo: conteudo}, model, files, ignored, regex_counts)."""
    model, files, ignored, rc = run_model(db_dir)
    names = file_names(model)
    out = {}
    for rec in model.live.values():
        out["functions/" + names[rec.key]] = render(rec, names)
    out["INDEX.md"] = render_index(model, names)
    return out, model, files, ignored, rc


def render_index(model, names):
    rows = ["# Indice de funcoes (gerado, nao editar)", "",
            "Gerado por `build_current.py`. Colunas: arquivo, assinatura (tipos IN), migracao da definicao atual, "
            "numero de definicoes ao longo do historico.", "",
            "| arquivo | assinatura | origem atual | defs | obs |", "|---|---|---|---|---|"]
    for rec in sorted(model.live.values(), key=lambda r: (r.name, r.types)):
        obs = []
        if rec.renamed_from:
            obs.append("renomeada de %s (%s)" % rec.renamed_from)
        if rec.nested:
            obs.append("bloco DO/EXECUTE")
        rows.append("| %s | %s | %s:%d | %d | %s |" % (names[rec.key], sig_str(rec), rec.migration, rec.line,
                                                         len(rec.history), "; ".join(obs)))
    return "\n".join(rows) + "\n"


def overloads(model):
    by_name = {}
    for rec in model.live.values():
        by_name.setdefault((rec.schema, rec.name), []).append(rec)
    return {k: v for k, v in by_name.items() if len(v) > 1}


def write_outputs(out):
    fdir = os.path.join(HERE, "functions")
    os.makedirs(fdir, exist_ok=True)
    for f in os.listdir(fdir):
        if f.endswith(".sql"):
            os.remove(os.path.join(fdir, f))
    for rel, content in out.items():
        with open(os.path.join(HERE, rel), "w", encoding="utf-8") as fh:
            fh.write(content)


def main():
    out, model, files, ignored, rc = build_outputs()
    write_outputs(out)
    print("migracoes lidas: %d (%s .. %s); ignoradas (nao .sql): %s" % (
        len(files), files[0], files[-1], ", ".join(ignored) or "-"))
    print("funcoes vivas: %d arquivos em db/current/functions/" % len(model.live))
    ov = overloads(model)
    for (s, n), recs in sorted(ov.items()):
        print("sobrecarga: %s -> %s" % (n, " | ".join("(%s) [%s]" % (", ".join(r.types), r.migration) for r in recs)))
    for m, l, t in model.ambiguous:
        print("AMBIGUO %s:%d %s" % (m, l, t))
    for w in model.warnings:
        print("aviso:", w)
    return 0


if __name__ == "__main__":
    sys.exit(main())
