# Intencao document_manage (D): guardar, achar e reenviar arquivos; aviso de vencimento.
# A leitura de arquivos (Normalizar update, Tipo de mensagem, historico) fica em patch_docs.py: nao e a Intencao.
# Depende de db (agente.f_docs, f_docs_file, f_docs_inbox_note, f_docs_cb).
from .core import Intent

INTERPRET = """if (out.intent === 'document_manage') {
  out.docs_json = JSON.stringify({
    action: out.doc_action || '', title: out.title || '', query: out.doc_query || '', folder: out.folder || '', folder_to: out.folder_to || '',
    expires_on: (out.expires_on && okDate.test(out.expires_on)) ? out.expires_on : '', alert_days: out.alert_days || null,
    file_id: (u.kind === 'photo' || u.kind === 'document') ? (u.file_id || '') : ''
  });
}"""

RULES = [
 "DOCUMENTOS (intent=document_manage): o usuario GUARDA e ACHA arquivos que ele mandou (foto, PDF, documento) e pede de volta. doc_action = save (guarda isso, guarda essa foto, salva esse PDF, arquiva na pasta Casa; vale para o arquivo desta mensagem OU o que ele mandou logo antes), find (acha a apolice do carro, cade o contrato, me manda a foto da praia, procura o alvara), send_folder (me manda tudo da reforma, manda os arquivos da pasta Viagens, link da pasta Casa = manda os arquivos), move (move o contrato para a pasta Casa: doc_query = o arquivo, folder_to = pasta destino), rename (renomeia o contrato para Contrato de aluguel: doc_query = nome atual, title = nome novo; renomear PASTA: folder = nome atual, folder_to = nome novo, doc_query vazio), delete (apaga o arquivo X: doc_query; apaga a pasta Y: folder), list_folders (minhas pastas; o que tem na pasta Casa: folder), create_folder (cria uma pasta Viagens: folder), expiry_set (me avisa antes do alvara vencer; o seguro vence em 15/03/2027, me avisa 30 dias antes: doc_query = o arquivo, expires_on = YYYY-MM-DD, alert_days = quantos dias antes, 7 se ele nao disse).",
 "DOCUMENTOS campos: em save, title = nome curto do arquivo (Apolice do carro, Foto da praia); doc_query = DESCRICAO com palavras-chave do conteudo, para a busca (se veio imagem, descreva o que voce ve: foto de praia com guarda-sol e por do sol; se o arquivo foi enviado antes e a conversa recente traz a descricao dele, reaproveite); folder = so se o usuario citou a pasta; expires_on e alert_days se ele deu o vencimento. Em find e send_folder, doc_query = palavras do que procura e folder so se citou a pasta. Nunca invente data de vencimento. reply = frase curta, mas quem confirma o resultado e o sistema.",
 "DOCUMENTOS contraste: guardar, arquivar, achar ou mandar de volta um ARQUIVO = document_manage. Anotar uma ideia ou texto solto = note_manage. Lista de itens (mercado) = list_manage. Foto de recibo, nota ou boleto SEM pedido para guardar = finance; se pedir para guardar o recibo = document_manage save. Lembrete comum com data e hora = create_reminder; aviso de VENCIMENTO de documento guardado = document_manage expiry_set. PDF ou foto enviado sem instrucao e que nao e conta: intent=chat, descreva em duas frases e pergunte se quer guardar.",
]


# campos do schema da IA (inseridos antes da ancora, na ordem em que os modulos entram)
SCHEMA_DOC = """doc_action: { type: ['string', 'null'], enum: ['save', 'find', 'send_folder', 'move', 'rename', 'delete', 'list_folders', 'create_folder', 'expiry_set', null] },
  folder: NN('string'), folder_to: NN('string'), doc_query: NN('string'), expires_on: NN('string'),"""


def build():
    global nodes, byname
    IRD = "$('Interpretar resposta').first().json."
    NU = "$('Normalizar update').first().json."
    _fjson = "JSON.stringify({ file_id: " + NU + "file_id, tg_type: " + NU + "tg_type, mime: " + NU + "mime, file_name: " + NU + "file_name, file_size: " + NU + "file_size, caption: " + NU + "text })"

    def _tg(name, op, pos):
        return {"name": name, "type": "n8n-nodes-base.telegram", "typeVersion": 1.2, "position": pos, "onError": "continueRegularOutput",
                "parameters": {"resource": "message", "operation": op, "chatId": "={{ $json.chat_id }}", "binaryData": False,
                               "file": "={{ $json.file_id }}", "additionalFields": {"caption": "={{ $json.caption }}"}}}

    def _tipo_rule(key, val):
        return {"outputKey": key, "renameOutput": True, "conditions": {"options": {"caseSensitive": True, "leftValue": "", "typeValidation": "strict"},
                "conditions": [{"leftValue": "={{ $json.tg_type }}", "operator": {"type": "string", "operation": "equals"}, "rightValue": val}], "combinator": "and"}}

    nodes += [
     pg_node("Docs: registrar recebido", "SELECT agente.f_docs_inbox_note($1::bigint, $2::jsonb) AS r",
             "={{ [ $('Buscar usuario').first().json.id || 0, " + _fjson + " ] }}", [1100, 3300]),
     pg_node("Docs: arquivo direto", "SELECT agente.f_docs_file($1::bigint, $2::jsonb) AS r",
             "={{ [ $('Buscar usuario').first().json.id || 0, " + _fjson + " ] }}", [1100, 3500]),
     pg_node("Docs: executar", "SELECT agente.f_docs($1::bigint, $2::jsonb) AS r",
             "={{ [ " + IRD + "user_id, " + IRD + "docs_json ] }}", [4480, 4200]),
     ifnode("Docs: tem arquivos?", "={{ !!($json.r && Array.isArray($json.r.files) && $json.r.files.length > 0) }}", 'boolean', 'true', '', [4704, 4200]),
     code_node("Docs: resposta",
       "const u = $('Normalizar update').first().json;\nconst r = $input.first().json.r || {};\n"
       "return [{ json: { chat_id: u.chat_id, text: r.text || 'Nao consegui agora. Tente de novo.', kb: r.kb || 'none', rid: r.rid || 0, state: '' } }];", [4928, 4360]),
     code_node("Docs: expandir",
       "const u = $('Normalizar update').first().json;\nconst r = $input.first().json.r || {};\n"
       "const files = Array.isArray(r.files) ? r.files : [];\n"
       "return files.slice(0, 10).map(function (f, i) {\n"
       "  const t = f.tg_type === 'photo' ? 'photo' : (f.tg_type === 'video' ? 'video' : 'document');\n"
       "  return { json: { chat_id: u.chat_id, file_id: String(f.file_id || ''), tg_type: t, caption: String(f.caption || '').replace(/[<>&]/g, '').slice(0, 200), idx: i } };\n"
       "});", [4928, 4040]),
     {"name": "Docs: tipo de arquivo", "type": "n8n-nodes-base.switch", "typeVersion": 3.4, "position": [5152, 4040],
      "parameters": {"mode": "rules", "rules": {"values": [_tipo_rule('foto', 'photo'), _tipo_rule('video', 'video')]},
                     "options": {"fallbackOutput": "extra", "renameFallbackOutput": "documento"}}},
     _tg("Docs: enviar foto", "sendPhoto", [5376, 3920]),
     _tg("Docs: enviar video", "sendVideo", [5376, 4040]),
     _tg("Docs: enviar documento", "sendDocument", [5376, 4160]),
     code_node("Docs: resposta final",
       "const u = $('Normalizar update').first().json;\nconst r = $('Docs: executar').first().json.r || {};\n"
       "let total = 0;\ntry { total = $('Docs: expandir').all().length; } catch (e) { total = 0; }\n"
       "let feitos = 0;\nlet falhas = 0;\n"
       "let a = [];\ntry { a = $('Docs: enviar foto').all(); } catch (e) { a = []; }\n"
       "a.forEach(function (it) { if (it.json && it.json.error) { falhas += 1; } else { feitos += 1; } });\n"
       "a = [];\ntry { a = $('Docs: enviar video').all(); } catch (e) { a = []; }\n"
       "a.forEach(function (it) { if (it.json && it.json.error) { falhas += 1; } else { feitos += 1; } });\n"
       "a = [];\ntry { a = $('Docs: enviar documento').all(); } catch (e) { a = []; }\n"
       "a.forEach(function (it) { if (it.json && it.json.error) { falhas += 1; } else { feitos += 1; } });\n"
       "if (feitos + falhas < total) { return []; }\n"
       "let text = String(r.text || 'Pronto.');\n"
       "if (falhas > 0) { text += ' (' + falhas + (falhas === 1 ? ' arquivo nao pode ser enviado' : ' arquivos nao puderam ser enviados') + ': o Telegram recusou.)'; }\n"
       "return [{ json: { chat_id: u.chat_id, text: text, kb: 'none', rid: 0, state: '' } }];", [5600, 4040]),
    ]
    _refresh()
    for _n in ("Docs: registrar recebido", "Docs: arquivo direto", "Docs: executar"):
        byname[_n]['onError'] = 'continueRegularOutput'
        byname[_n]['alwaysOutputData'] = True

    setc('Docs: registrar recebido', ['Baixar audio'])
    setc('Docs: arquivo direto', ['Docs: resposta'])
    setc('Docs: executar', ['Docs: tem arquivos?'])
    conns['Docs: tem arquivos?'] = {'main': [[{'node': 'Docs: expandir', 'type': 'main', 'index': 0}], [{'node': 'Docs: resposta', 'type': 'main', 'index': 0}]]}
    setc('Docs: resposta', ['Preparar envio'])
    setc('Docs: expandir', ['Docs: tipo de arquivo'])
    conns['Docs: tipo de arquivo'] = {'main': [[{'node': 'Docs: enviar foto', 'type': 'main', 'index': 0}], [{'node': 'Docs: enviar video', 'type': 'main', 'index': 0}], [{'node': 'Docs: enviar documento', 'type': 'main', 'index': 0}]]}
    setc('Docs: enviar foto', ['Docs: resposta final'])
    setc('Docs: enviar video', ['Docs: resposta final'])
    setc('Docs: enviar documento', ['Docs: resposta final'])
    setc('Docs: resposta final', ['Preparar envio'])
    # teclados de confirmacao: dcdel/dckeep (arquivo) e dcfdel/dckeep (pasta) -> agente.f_docs_cb
    add_kb('dc_del', [('Sim, apagar', 'dcdel:{rid}'), ('Nao', 'dckeep:{rid}')])
    add_kb('dc_fdel', [('Sim, apagar a pasta', 'dcfdel:{rid}'), ('Nao', 'dckeep:{rid}')])
    _refresh()


INTENT = Intent(
    name='document_manage',
    enum_after='misc_query',
    schema_parts=[(SCHEMA_DOC, "\n  ", "card: NN('string'),")],
    rules=RULES,
    interpret_js=INTERPRET,
    route=('documentos', 'Docs: executar'),
    build=build,
)
