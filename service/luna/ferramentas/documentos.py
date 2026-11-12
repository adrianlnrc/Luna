"""Ferramenta documentos: invoucro de agente.f_docs. O banco guarda so a referencia do arquivo, nunca o conteudo."""
from __future__ import annotations

from ..tipos import Arquivo, Resultado
from .base import ALTERA, CONSULTA, CRIA, Acao, Ferramenta, S
from .util import data_ok, do_banco

MAPA = {"buscar": "find", "pastas": "list_folders", "enviar_pasta": "send_folder", "guardar": "save", "criar_pasta": "create_folder",
        "definir_vencimento": "expiry_set", "mover": "move", "renomear": "rename", "apagar": "delete"}


async def _executar(ctx, acao: str, a: dict) -> Resultado:
    async with ctx.cx() as cx:
        r = await cx.fn("f_docs", ctx.uid, {
            "action": MAPA[acao], "title": a.get("titulo") or "", "query": a.get("busca") or "", "folder": a.get("pasta") or "",
            "folder_to": a.get("pasta_destino") or "", "expires_on": a["vence_em"] if data_ok(a.get("vence_em")) else "",
            "alert_days": a.get("avisar_dias"), "file_id": ctx.arquivo.file_id if ctx.arquivo and acao == "guardar" else ""})
    res = do_banco(r, "Não consegui agora. Tente de novo.")
    for f in ((r or {}).get("files") or [])[:10]:
        tipo = f.get("tg_type") if f.get("tg_type") in ("photo", "video") else "document"
        res.arquivos.append(Arquivo(file_id=str(f.get("file_id") or ""), tipo=tipo, nome=str(f.get("caption") or "")[:200]))
    return res


def _r(t: str):
    return lambda a: (f"{t} \"{a.get('busca') or a.get('titulo') or ''}\""
                      + (f" para a pasta {a.get('pasta_destino')}" if a.get("pasta_destino") else "")
                      + (f" como \"{a.get('titulo')}\"" if t == "Renomear" and a.get("titulo") else "")
                      + (f", vence em {a.get('vence_em')}" if a.get("vence_em") else ""))


FERRAMENTA = Ferramenta(
    nome="documentos",
    descricao="Arquivos guardados (fotos, PDFs, vídeos) em pastas, com título e vencimento. Buscar reenvia o arquivo ao usuário.",
    acoes={
        "buscar": Acao("buscar", CONSULTA, "acha e reenvia arquivos pelo nome"),
        "pastas": Acao("pastas", CONSULTA, "lista pastas e o que tem nelas"),
        "enviar_pasta": Acao("enviar_pasta", CONSULTA, "reenvia tudo de uma pasta"),
        "guardar": Acao("guardar", CRIA, "guarda o arquivo recebido agora ou há pouco (título, pasta, vencimento)",
                        resumo=lambda a: f"Guardar o arquivo como \"{a.get('titulo') or 'sem título'}\"" + (f" na pasta {a.get('pasta')}" if a.get("pasta") else "")),
        "criar_pasta": Acao("criar_pasta", CRIA, "cria pasta", resumo=lambda a: f"Criar a pasta {a.get('pasta')}"),
        "definir_vencimento": Acao("definir_vencimento", CRIA, "define vencimento e aviso de um documento", resumo=_r("Definir vencimento de")),
        "mover": Acao("mover", ALTERA, "move para outra pasta", resumo=_r("Mover")),
        "renomear": Acao("renomear", ALTERA, "troca o título", resumo=_r("Renomear")),
        "apagar": Acao("apagar", ALTERA, "apaga um arquivo ou uma pasta", nativa=True),
    },
    parametros={
        "titulo": S("string", "título do documento"),
        "busca": S("string", "o que procurar"),
        "pasta": S("string"),
        "pasta_destino": S("string"),
        "vence_em": S("string", "AAAA-MM-DD"),
        "avisar_dias": S("integer", "avisar X dias antes do vencimento"),
    },
    executar=_executar,
)
