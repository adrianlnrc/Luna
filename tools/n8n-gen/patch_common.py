# ---------- helpers comuns (usados pelos patches de agenda, extras e fase 3) ----------
def _refresh():
    global byname
    byname={n['name']:n for n in nodes}
    return byname

def add_kb(key, buttons, row_size=None):
    """Novo teclado inline. buttons = [(rotulo, 'prefixo:{rid}'), ...] (callback_data pode ter {rid} e texto fixo depois,
    ex. 'agpk:{rid}:1'). Cria o no Telegram 'Enviar com <key>' e a regra em 'Qual teclado?' (antes do fallback)."""
    name='Enviar com '+key.replace('_',' ')
    btns=[{"text":t,"additionalFields":{"callback_data":"="+cb.replace('{rid}',"{{ $('Preparar envio').first().json.rid }}")}} for t,cb in buttons]
    rows=[{"row":{"buttons":btns}}] if not row_size else [{"row":{"buttons":btns[i:i+row_size]}} for i in range(0,len(btns),row_size)]
    pos=[6272, 2832+192*len([n for n in nodes if n['name'].startswith('Enviar com ')])]
    nodes.append({"name":name,"type":"n8n-nodes-base.telegram","typeVersion":1.2,"position":pos,
      "parameters":{"resource":"message","operation":"sendMessage","chatId":"={{ $('Preparar envio').first().json.chat_id }}","text":"={{ $('Preparar envio').first().json.text }}",
        "replyMarkup":"inlineKeyboard","inlineKeyboard":{"rows":rows},"additionalFields":{"appendAttribution":False}}})
    _refresh()
    kt=byname['Qual teclado?']['parameters']['rules']['values']
    kt.append({"outputKey":key.replace('_',' '),"renameOutput":True,"conditions":{"options":{"caseSensitive":True,"leftValue":"","typeValidation":"strict"},"conditions":[{"leftValue":"={{ $('Preparar envio').first().json.kb }}","operator":{"type":"string","operation":"equals"},"rightValue":key}],"combinator":"and"}})
    ko=conns['Qual teclado?']['main']
    ko.insert(len(kt)-1,[{'node':name,'type':'main','index':0}])
    return name

def add_route(key, intent, first_node):
    """Nova regra no 'Roteador de intencao' (antes do fallback) para intent == <intent>, ligando ao no <first_node>."""
    _refresh()
    rt=byname['Roteador de intencao']['parameters']['rules']['values']
    rt.append({"outputKey":key,"renameOutput":True,"conditions":{"options":{"caseSensitive":True,"leftValue":"","typeValidation":"strict"},"conditions":[{"leftValue":"={{ $json.intent }}","operator":{"type":"string","operation":"equals"},"rightValue":intent}],"combinator":"and"}})
    conns['Roteador de intencao']['main'].insert(len(rt)-1,[{'node':first_node,'type':'main','index':0}])

def pg_node(name, query, repl, pos, cred_node='Executar financas'):
    """No Postgres executeQuery. repl = expressao n8n (string que comeca com '={{ [')."""
    return {"name":name,"type":"n8n-nodes-base.postgres","typeVersion":2.6,"position":pos,"parameters":{"operation":"executeQuery","query":query,"options":{"queryReplacement":repl}}}

def code_node(name, js_code, pos):
    return {"name":name,"type":"n8n-nodes-base.code","typeVersion":2,"position":pos,"parameters":{"mode":"runOnceForAllItems","language":"javaScript","jsCode":js_code}}

def switch_cal(name, pos, field="={{ $json.calendar_key }}"):
    mk=lambda k:{"outputKey":k,"renameOutput":True,"conditions":{"options":{"caseSensitive":True,"leftValue":"","typeValidation":"strict"},"conditions":[{"leftValue":field,"operator":{"type":"string","operation":"equals"},"rightValue":k}],"combinator":"and"}}
    return {"name":name,"type":"n8n-nodes-base.switch","typeVersion":3.4,"position":pos,"parameters":{"mode":"rules","rules":{"values":[mk('adrian'),mk('maria')]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"sem calendario"}}}

def exec_wf(name, wf_id, values, pos):
    return {"name":name,"type":"n8n-nodes-base.executeWorkflow","typeVersion":1.3,"position":pos,"parameters":{"source":"database","mode":"once","workflowId":{"__rl":True,"mode":"id","value":wf_id},"workflowInputs":{"mappingMode":"defineBelow","value":values}}}
