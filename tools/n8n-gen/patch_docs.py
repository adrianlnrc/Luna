# ---------- DOCUMENTOS (D): guardar, achar e reenviar arquivos; aviso de vencimento ----------
_refresh()
IRD = "$('Interpretar resposta').first().json."

# --- Normalizar update: qualquer arquivo (video, documento de qualquer tipo ate 50 MB) + tamanho e tipo de envio ---
nu = byname['Normalizar update']['parameters']['jsCode']
nu = rep(nu, "message_id = 0, mime = '', file_name = '';", "message_id = 0, mime = '', file_name = '', file_size = 0, tg_type = '';")
nu = rep(nu, "{ kind = 'photo'; file_id = m.photo[m.photo.length - 1].file_id; text = m.caption || ''; }",
             "{ kind = 'photo'; file_id = m.photo[m.photo.length - 1].file_id; text = m.caption || ''; tg_type = 'photo'; file_size = Number(m.photo[m.photo.length - 1].file_size || 0); }")
nu = rep(nu, "    kind = (okTipo && Number(m.document.file_size || 0) <= 15000000) ? 'document' : 'unsupported';\n  }",
             "    file_size = Number(m.document.file_size || 0); tg_type = 'document';\n"
             "    kind = (okTipo && file_size <= 15000000) ? 'document' : (file_size <= 52428800 ? 'file' : 'unsupported');\n  }\n"
             "  else if (m.video) {\n"
             "    file_id = m.video.file_id; text = m.caption || ''; mime = String(m.video.mime_type || ''); file_name = m.video.file_name || ''; tg_type = 'video';\n"
             "    file_size = Number(m.video.file_size || 0);\n"
             "    kind = file_size <= 52428800 ? 'file' : 'unsupported';\n  }")
nu = rep(nu, "mime: mime, file_name: file_name } }];", "mime: mime, file_name: file_name, file_size: file_size, tg_type: tg_type } }];")
byname['Normalizar update']['parameters']['jsCode'] = nu

# --- texto do arquivo grande demais ---
rc = byname['Resposta do comando']['parameters']['jsCode']
rc = rep(rc, "text = 'Por enquanto eu leio PDF e imagens (ate 15 MB), alem de texto, audio e fotos.';",
             "text = 'Esse arquivo passa de 50 MB, o limite do Telegram para eu guardar e reenviar. Mande um menor.';")
byname['Resposta do comando']['parameters']['jsCode'] = rc

# --- historico: arquivos sem IA tambem entram na conversa (para o "guarda" seguinte) ---
mh = byname['Montar historico']['parameters']['jsCode']
mh = rep(mh, "u.kind === 'photo' || u.kind === 'document')", "u.kind === 'photo' || u.kind === 'document' || u.kind === 'file')")
mh = rep(mh, "  if (u.kind === 'document') { userText = '[arquivo] ' + userText; }",
             "  if (u.kind === 'document') { userText = '[arquivo] ' + userText; }\n  if (u.kind === 'file') { userText = '[arquivo ' + (u.file_name || '') + '] ' + userText; }")
byname['Montar historico']['parameters']['jsCode'] = mh

# --- Tipo de mensagem: nova saida para arquivos sem IA ---
tv = byname['Tipo de mensagem']['parameters']['rules']['values']
tv.append({"outputKey": "arquivo", "renameOutput": True, "conditions": {"options": {"caseSensitive": True, "leftValue": "", "typeValidation": "strict"},
  "conditions": [{"leftValue": "={{ $('Normalizar update').first().json.kind }}", "operator": {"type": "string", "operation": "equals"}, "rightValue": "file"}], "combinator": "and"}})
tm = conns['Tipo de mensagem']['main']
tm.append([{'node': 'Docs: arquivo direto', 'type': 'main', 'index': 0}])
# foto (saida 4) e documento (saida 5) passam antes por "registrar recebido" e seguem para Baixar audio
assert tm[4][0]['node'] == 'Baixar audio' and tm[5][0]['node'] == 'Baixar audio'
tm[4] = [{'node': 'Docs: registrar recebido', 'type': 'main', 'index': 0}]
tm[5] = [{'node': 'Docs: registrar recebido', 'type': 'main', 'index': 0}]

# --- Intencao document_manage (regras, JSON do modulo, nos Docs:, teclados e rota): intents/documentos.py ---
from intents import REGISTRY
REGISTRY.apply('document_manage', globals())
