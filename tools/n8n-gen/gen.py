import json,re,sys
w=json.load(open('main.json'))
nodes=w['nodes']
conns=w['connections']
byname={n['name']:n for n in nodes}
exec(open('patch_common.py').read())   # helpers (_refresh, add_kb, add_route, pg_node...) usados pelo registro de Intencoes
OLD='Montar pedido ao Gemini'; NEW='Montar pedido a IA'

# ---------- Montar pedido: novo codigo ----------
old=byname[OLD]['parameters']['jsCode']
i0=old.index("const u = $('Normalizar update')")
i1=old.index("const schema = {")
mid=old[i0:i1]
head="""let MODELO = 'gpt-6-luna';
try {
  const cfg = $('Ler configuracao do modelo').first().json.modelo;
  if (cfg) {
    const s = String(cfg).trim();
    if (s.charAt(0) === '{') {
      const o = JSON.parse(s);
      if (o.modelo && String(o.modelo).indexOf('gpt') === 0) { MODELO = String(o.modelo); }
    } else if (s.indexOf('gpt') === 0) { MODELO = s; }
  }
} catch (e) {}
"""
tail="""const NN = function (t) { return { type: [t, 'null'] }; };
const props = {
  intent: { type: 'string', enum: ['create_reminder', 'create_event', 'list_agenda', 'create_supply', 'supply_bought', 'supply_adjust', 'supply_taken', 'supply_schedule', 'set_preference', 'provide_time', 'create_task', 'list_tasks', 'complete_task', 'clarify', 'chat'] },
  transcript: { type: 'string' }, title: { type: 'string' }, date: { type: 'string' }, time: { type: 'string' }, reply: { type: 'string' },
  duration_minutes: NN('integer'), location: NN('string'), lead_minutes: NN('integer'), shared: NN('boolean'),
  range_start: NN('string'), range_end: NN('string'), item: NN('string'),
  item_kind: { type: ['string', 'null'], enum: ['remedio', 'suplemento', null] },
  take_time: NN('string'), stop_reminder: NN('boolean'), units_total: NN('integer'), units_per_day: NN('number'),
  started_on: NN('string'), alert_days: NN('integer'), units_left: NN('integer'), pause_days: NN('integer'),
  pref_lead_minutes: NN('integer'), pref_summary_time: NN('string'), pref_supply_days: NN('integer')
};
const schema = { type: 'object', properties: props, required: Object.keys(props), additionalProperties: false };
let atual = u.text || '';
if (u.kind === 'voice') { atual = String($input.first().json.text || '').trim(); }
if (isPhoto && !atual) { atual = 'Imagem enviada pelo usuario, sem legenda.'; }
const agoraMs = Date.now();
const recentes = hist.filter(function (h) { return h && h.t && (agoraMs - h.ts) < 6 * 3600 * 1000; });
while (recentes.length && recentes[0].r !== 'user') { recentes.shift(); }
const linhas = recentes.map(function (h) { return (h.r === 'model' ? 'Assistente: ' : 'Usuario: ') + h.t; });
let prompt = '';
if (linhas.length) { prompt = 'CONVERSA RECENTE (mais antiga primeiro):' + NL + linhas.join(NL) + NL + NL; }
prompt += 'MENSAGEM ATUAL DO USUARIO' + (u.kind === 'voice' ? ' (transcricao de audio)' : '') + ':' + NL + atual;
if (isPhoto) { prompt += NL + '(Uma imagem esta anexada a esta mensagem.)'; }
return [{ json: { modelo: MODELO, instrucoes: regras.join(NL), prompt: prompt, schema_json: JSON.stringify(schema),
  image_url: (media && isPhoto) ? 'data:image/jpeg;base64,' + media : '', texto_atual: atual, state: state,
  history_size: recentes.length, via_audio: u.kind === 'voice', via_photo: isPhoto && !!media } }];"""
mid=mid.replace("const media = $input.first().json.audio_b64 || '';","const media = $input.first().json.audio_b64 || '';")
newcode=head+mid+tail
byname[OLD]['parameters']['jsCode']=newcode
byname[OLD]['name']=NEW

old_campos="'CAMPOS: preencha SEMPRE title, date, time e reply. Use texto vazio (\"\") quando o campo nao se aplica. Os demais campos so quando se aplicam; NUNCA coloque 0 em campos numericos que o usuario nao citou (omita-os).',"
assert old_campos in newcode, 'campos'
newcode=newcode.replace(old_campos,"'CAMPOS: preencha SEMPRE title, date, time e reply (texto vazio \"\" quando nao se aplicam). Todos os outros campos do schema devem aparecer: use null quando nao se aplicam ou o usuario nao citou; NUNCA use 0 em campo numerico que o usuario nao citou.',")
byname[OLD]['parameters']['jsCode']=newcode
# ---------- Interpretar resposta: patch ----------
ip=byname['Interpretar resposta']['parameters']
c=ip['jsCode']
a=c.index("let g = null;"); b=c.index("if (!g || !g.intent) {")
c=c[:a]+"""let g = null;
try {
  const itens = r && Array.isArray(r.output) ? r.output : [];
  let txt = '';
  itens.forEach(function (o) {
    if (o && o.type === 'message' && Array.isArray(o.content)) {
      o.content.forEach(function (p) { if (p && p.text && typeof p.text === 'object') { g = p.text; } else if (p && p.text) { txt += p.text; } });
    }
  });
  if (!g) { g = JSON.parse(txt); }
} catch (e) { g = null; }
"""+c[b:]
old_err="const errTxt = r && r.error ? String(r.error.message || '') + ' ' + String(r.error.description || '') : '';"
assert old_err in c
c=c.replace(old_err,"let errTxt = '';\n  if (r && r.error) { errTxt = typeof r.error === 'string' ? r.error : JSON.stringify(r.error); }")
c=c.replace("const quota = /quota|too many requests|rate limit|429/i.test(errTxt);","const quota = /quota|too many requests|rate limit|429|insufficient|billing/i.test(errTxt);")
c=c.replace("const modeloOff = /no longer available|not found|could not be found/i.test(errTxt);","const modeloOff = /model_not_found|does not exist|no longer available|not found|could not be found/i.test(errTxt);")
c=c.replace("msg = 'Atingi o limite diario de uso do Gemini (plano gratuito). Volto a responder quando a cota renovar ou quando o plano for ampliado.';","msg = 'Atingi o limite de uso da OpenAI (credito ou cota). Verifique o saldo da conta para eu voltar a responder.';")
c=c.replace("'O modelo do Gemini configurado ('","'O modelo configurado ('")
c=c.replace("const out = Object.assign({}, base, g);","Object.keys(g).forEach(function (k) { if (g[k] === null) { delete g[k]; } });\nif (!g.transcript) { g.transcript = ctx.texto_atual || ''; }\nconst out = Object.assign({}, base, g);")
c=c.replace("/\\[agendado: ([0-9-]{10}) ([0-9:]{5})\\]/","/[[]agendado: ([0-9-]{10}) ([0-9:]{5})[]]/")
c=c.replace(OLD,NEW)
assert '\\' not in c, 'backslash left'
ip['jsCode']=c


# ---------- FINANCAS (intent finance): codigo, regras, schema, JSON e textos de ajuda -> intents/financas.py ----------
from intents import REGISTRY
REGISTRY.apply('finance', globals())

rc=byname['Resposta do comando']['parameters']
assert 'uso o Gemini, do Google' in rc['jsCode']
rc['jsCode']=rc['jsCode'].replace('eu uso o Gemini, do Google, entao o conteudo delas passa por la.','eu uso a OpenAI (ChatGPT), entao o conteudo delas passa por la.')
# ---------- novos nos ----------
def ifnode(name,left,optype,opname,right,pos):
    cond={"leftValue":left,"operator":{"type":optype,"operation":opname},"rightValue":right}
    if optype=='boolean': cond["operator"]["singleValue"]=True
    return {"name":name,"type":"n8n-nodes-base.if","typeVersion":2.2,"position":pos,"parameters":{"conditions":{"options":{"caseSensitive":True,"leftValue":"","typeValidation":"strict","version":2},"conditions":[cond],"combinator":"and"}}}
M="$('"+NEW+"').first().json."
def oainode(name,pos,photo):
    vals=[{"type":"text","role":"user","content":"={{ "+M+"prompt }}"}]
    if photo: vals.append({"type":"image","role":"user","imageType":"url","imageUrl":"={{ "+M+"image_url }}","imageDetail":"auto"})
    return {"name":name,"type":"@n8n/n8n-nodes-langchain.openAi","typeVersion":2.3,"position":pos,"onError":"continueRegularOutput","retryOnFail":True,
      "parameters":{"resource":"text","operation":"response","modelId":{"__rl":True,"mode":"id","value":"={{ "+M+"modelo }}"},
        "responses":{"values":vals},"simplify":True,
        "options":{"instructions":"={{ "+M+"instrucoes }}","maxTokens":1500,"store":False,
          "textFormat":{"textOptions":{"type":"json_schema","name":"interpretacao","schema":"={{ "+M+"schema_json }}","strict":True}}}}}
trans={"name":"Transcrever audio","type":"@n8n/n8n-nodes-langchain.openAi","typeVersion":2.3,"position":[1100,500],"onError":"continueRegularOutput",
  "parameters":{"resource":"audio","operation":"transcribe","binaryPropertyName":"data","options":{"language":"pt"}}}
nodes[:] = [n for n in nodes if n['name'] not in ('Gemini interpreta',)]
nodes += [ifnode('E audio?',"={{ $('Normalizar update').first().json.kind }}",'string','equals','voice',[900,500]),
          trans,
          ifnode('Tem foto?',"={{ "+M+"via_photo }}",'boolean','true','',[2200,500]),
          oainode('OpenAI interpreta texto',[2450,560],False),
          oainode('OpenAI interpreta foto',[2450,420],True)]

# ---------- conexoes ----------
def rename_in_conns():
    nc={}
    for s,v in conns.items():
        s2=NEW if s==OLD else s
        nv={}
        for k,outs in v.items():
            nv[k]=[[{**t,'node':(NEW if t['node']==OLD else t['node'])} for t in tl] for tl in outs]
        nc[s2]=nv
    return nc
conns=rename_in_conns()
def setc(src,outs): conns[src]={'main':[[{'node':t,'type':'main','index':0}] for t in outs]}
setc('Baixar audio',['E audio?'])
setc('E audio?',['Transcrever audio','Audio em base64'])
setc('Transcrever audio',[NEW])
setc('Mostrar digitando',['Tem foto?'])
setc('Tem foto?',['OpenAI interpreta foto','OpenAI interpreta texto'])
setc('OpenAI interpreta texto',['Interpretar resposta'])
setc('OpenAI interpreta foto',['Interpretar resposta'])
conns.pop('Gemini interpreta',None)

# ---------- FINANCAS: nos novos, rota, teclados -> intents/financas.py ----------
REGISTRY.apply('finance.nos', globals())

# ---------- ARQUIVOS (PDF / imagem como documento) ----------
def rep(code, old, new, count=1):
    assert old in code, old[:60]
    return code.replace(old, new, count)

# Normalizar update
nu=byname['Normalizar update']['parameters']['jsCode']
nu=rep(nu,"let kind = 'other', text = '', file_id = '', chat_id = 0, from_id = 0, cb_id = '', cb_data = '', message_id = 0;","let kind = 'other', text = '', file_id = '', chat_id = 0, from_id = 0, cb_id = '', cb_data = '', message_id = 0, mime = '', file_name = '';")
nu=rep(nu,"  else if (typeof m.text === 'string')","""  else if (m.document) {
    const mt = String(m.document.mime_type || '').toLowerCase();
    file_id = m.document.file_id; text = m.caption || ''; mime = mt; file_name = m.document.file_name || '';
    const okTipo = mt === 'application/pdf' || mt === 'image/jpeg' || mt === 'image/png' || mt === 'image/webp' || mt === 'image/gif';
    kind = (okTipo && Number(m.document.file_size || 0) <= 15000000) ? 'document' : 'unsupported';
  }
  else if (typeof m.text === 'string')""")
nu=rep(nu,"cb_data: cb_data, message_id: message_id } }];","cb_data: cb_data, message_id: message_id, mime: mime, file_name: file_name } }];")
byname['Normalizar update']['parameters']['jsCode']=nu

# Tipo de mensagem: duas regras novas
tv=byname['Tipo de mensagem']['parameters']['rules']['values']
for key,out in (('documento','document'),('arquivo nao suportado','unsupported')):
    tv.append({"outputKey":key,"renameOutput":True,"conditions":{"options":{"caseSensitive":True,"leftValue":"","typeValidation":"strict"},"conditions":[{"leftValue":"={{ $('Normalizar update').first().json.kind }}","operator":{"type":"string","operation":"equals"},"rightValue":out}],"combinator":"and"}})
to=conns['Tipo de mensagem']['main']
to.append([{'node':'Baixar audio','type':'main','index':0}])
to.append([{'node':'Resposta do comando','type':'main','index':0}])

# Resposta do comando: arquivo nao suportado + textos
rc2=byname['Resposta do comando']['parameters']['jsCode']
rc2=rep(rc2,"if (cmd === '/start') {","if (u.kind === 'unsupported') {\n  text = 'Por enquanto eu leio PDF e imagens (ate 15 MB), alem de texto, audio e fotos.';\n} else if (cmd === '/start') {")
rc2=rep(rc2,"(texto, audio ou foto do recibo)","(texto, audio, foto ou PDF do recibo ou boleto)")
byname['Resposta do comando']['parameters']['jsCode']=rc2

# Montar pedido a IA
mp=byname[NEW]['parameters']['jsCode']
mp=rep(mp,"const isPhoto = u.kind === 'photo';","const isPhoto = u.kind === 'photo';\nconst isDoc = u.kind === 'document';\nconst isPdf = isDoc && String(u.mime || '').indexOf('pdf') >= 0;\nconst isImgDoc = isDoc && !isPdf;")
mp=rep(mp,"if (isPhoto && !atual) { atual = 'Imagem enviada pelo usuario, sem legenda.'; }","if (isPhoto && !atual) { atual = 'Imagem enviada pelo usuario, sem legenda.'; }\nif (isDoc && !atual) { atual = 'Arquivo enviado pelo usuario, sem legenda.'; }")
mp=rep(mp,"if (isPhoto) { prompt += NL + '(Uma imagem esta anexada a esta mensagem.)'; }","if (isPhoto) { prompt += NL + '(Uma imagem esta anexada a esta mensagem.)'; }\nif (isDoc) { prompt += NL + '(Um arquivo ' + (isPdf ? 'PDF' : 'de imagem') + (u.file_name ? ' chamado ' + u.file_name : '') + ' esta anexado a esta mensagem.)'; }")
mp=rep(mp,"image_url: (media && isPhoto) ? 'data:image/jpeg;base64,' + media : '', texto_atual: atual, state: state,\n  history_size: recentes.length, via_audio: u.kind === 'voice', via_photo: isPhoto && !!media } }];","image_url: (media && (isPhoto || isImgDoc)) ? 'data:' + (isImgDoc ? u.mime : 'image/jpeg') + ';base64,' + media : '', texto_atual: atual, state: state,\n  file_b64: (media && isPdf) ? media : '', file_name: u.file_name || 'documento.pdf',\n  history_size: recentes.length, via_audio: u.kind === 'voice', via_photo: (isPhoto || isImgDoc) && !!media, via_pdf: isPdf && !!media } }];")
mp=rep(mp,"  'FINANCAS categorias: ","  'ARQUIVO (PDF ou imagem enviada como arquivo): recibo, nota fiscal, cupom ou comprovante de pagamento: intent=finance, fin_action=add, amount = TOTAL pago, title = estabelecimento, date = data do documento (YYYY-MM-DD). Boleto ou fatura A PAGAR: intent=finance, fin_action=add, paid=false, amount = valor a pagar, date = VENCIMENTO, title = beneficiario ou nome da conta. Extrato ou fatura de cartao com muitas linhas: registre so o TOTAL a pagar como conta (a importacao linha a linha ainda nao existe) e avise isso em reply. Outros documentos (contrato, receita, laudo): intent=chat, resuma em duas frases e pergunte o que o usuario quer fazer. Se nao der para ler o valor com certeza, use clarify.',\n  'FINANCAS categorias: ")
byname[NEW]['parameters']['jsCode']=mp

# Interpretar resposta: origem do lancamento
ir=byname['Interpretar resposta']['parameters']['jsCode']
ir=rep(ir,"source: u.kind === 'photo' ? 'photo' : (ctx.via_audio ? 'audio' : 'text')","source: (u.kind === 'photo' || u.kind === 'document') ? 'photo' : (ctx.via_audio ? 'audio' : 'text')")
byname['Interpretar resposta']['parameters']['jsCode']=ir

# Montar historico
mh=byname['Montar historico']['parameters']['jsCode']
mh=rep(mh,"(u.kind === 'text' || u.kind === 'voice' || u.kind === 'photo')","(u.kind === 'text' || u.kind === 'voice' || u.kind === 'photo' || u.kind === 'document')")
mh=rep(mh,"if (u.kind === 'photo') { userText = '[foto] ' + userText; }","if (u.kind === 'photo') { userText = '[foto] ' + userText; }\n  if (u.kind === 'document') { userText = '[arquivo] ' + userText; }")
byname['Montar historico']['parameters']['jsCode']=mh

# novos nos: Tem PDF?, Preparar PDF, OpenAI interpreta PDF
MM="$('"+NEW+"').first().json."
nodes += [
 {"name":"Tem PDF?","type":"n8n-nodes-base.if","typeVersion":2.2,"position":[2200,700],"parameters":{"conditions":{"options":{"caseSensitive":True,"leftValue":"","typeValidation":"strict","version":2},"conditions":[{"leftValue":"={{ "+MM+"via_pdf }}","operator":{"type":"boolean","operation":"true","singleValue":True},"rightValue":""}],"combinator":"and"}}},
 {"name":"Preparar PDF","type":"n8n-nodes-base.code","typeVersion":2,"position":[2450,800],"parameters":{"mode":"runOnceForAllItems","language":"javaScript","jsCode":"const m = $('"+NEW+"').first().json;\nconst bin = await this.helpers.prepareBinaryData(Buffer.from(String(m.file_b64), 'base64'), m.file_name || 'documento.pdf', 'application/pdf');\nreturn [{ json: { ok: true }, binary: { data: bin } }];"}},
 {"name":"OpenAI interpreta PDF","type":"@n8n/n8n-nodes-langchain.openAi","typeVersion":2.3,"position":[2700,800],"onError":"continueRegularOutput","retryOnFail":True,
  "parameters":{"resource":"text","operation":"response","modelId":{"__rl":True,"mode":"id","value":"={{ "+MM+"modelo }}"},
    "responses":{"values":[{"type":"text","role":"user","content":"={{ "+MM+"prompt }}"},{"type":"file","role":"user","fileType":"base64","binaryPropertyName":"data","fileName":"={{ "+MM+"file_name }}"}]},"simplify":True,
    "options":{"instructions":"={{ "+MM+"instrucoes }}","maxTokens":1500,"store":False,
      "textFormat":{"textOptions":{"type":"json_schema","name":"interpretacao","schema":"={{ "+MM+"schema_json }}","strict":True}}}}},
]
byname={n['name']:n for n in nodes}
setc('Tem foto?',['OpenAI interpreta foto','Tem PDF?'])
setc('Tem PDF?',['Preparar PDF','OpenAI interpreta texto'])
setc('Preparar PDF',['OpenAI interpreta PDF'])
setc('OpenAI interpreta PDF',['Interpretar resposta'])

byname={n['name']:n for n in nodes}
exec(open('patch_f2a.py').read())
import os
for _p in ('patch_f4_schema.py','patch_agenda.py','patch_extras.py','patch_fase3.py','patch_fix1.py','patch_docs.py','patch_listas.py','patch_projetos.py','patch_f8_projetos_google.py','patch_f5_cmd.py','patch_f5_menu.py','patch_f5_locais.py','patch_f6_correcoes.py','patch_f7_m1_listas.py','patch_f7_m2_recibo.py','patch_f7_m3_relatorios.py','patch_f7_m4_custo.py','patch_f7_m5_pesquisa.py','patch_f8_agenda_import.py','patch_f10_acoes.py','patch_f11_memoria.py','patch_f13_menu.py','patch_zz_compact.py'):
    if os.path.exists(_p): exec(open(_p).read())
json.dump({'nodes':nodes,'connections':conns,'name':w['name']},open('modified.json','w'),ensure_ascii=False)
# ---------- consistencia do registro de Intencoes (intents/check.py): enum <=> rota <=> handler ----------
from intents import REGISTRY
from intents.check import check as _check_intents
_ierr,_iwarn=_check_intents({'nodes':nodes,'connections':conns},REGISTRY.names(),REGISTRY.internal_names())
for _m in _iwarn: print('intents AVISO',_m,file=sys.stderr)
assert not _ierr, ('intents: registro inconsistente',_ierr)

# ---------- emitir SDK ----------
CRED={'n8n-nodes-base.telegramTrigger':('telegramApi','9wbEyTedyS1LrOAj','Telegram Agente'),
      'n8n-nodes-base.telegram':('telegramApi','9wbEyTedyS1LrOAj','Telegram Agente'),
      'n8n-nodes-base.postgres':('postgres','1xCdaqn8KYskDi8x','Postgres Agente'),
      'n8n-nodes-base.redis':('redis','66NcqCtUSKYiVp5K','Redis Agente'),
      '@n8n/n8n-nodes-langchain.openAi':('openAiApi','q99Ey7lWzPOBs4PJ','OpenAI account')}
def js(v,key=None):
    if isinstance(v,str):
        if key=='jsCode':
            assert '`' not in v and '${' not in v and '\\' not in v, 'hazard in code'
            v=re.sub(r'\n[ \t]+','\n',v)
            return '`'+v+'`'
        if v.startswith('='):
            return 'expr('+json.dumps(v[1:],ensure_ascii=False)+')'
        return json.dumps(v,ensure_ascii=False)
    if isinstance(v,bool): return 'true' if v else 'false'
    if v is None: return 'null'
    if isinstance(v,(int,float)): return json.dumps(v)
    if isinstance(v,list): return '['+','.join(js(x) for x in v)+']'
    if isinstance(v,dict): return '{'+','.join(json.dumps(k)+':'+js(x,k) for k,x in v.items())+'}'
var={n['name']:'n%d'%i for i,n in enumerate(nodes)}
out=["import { workflow, node, trigger, switchCase, ifElse, expr } from '@n8n/workflow-sdk';",""]
for n in nodes:
    t=n['type']; v=var[n['name']]
    cfg={'name':n['name'],'parameters':n['parameters']}
    if t in CRED:
        k,i,nm=CRED[t]; cfg['credentials']={k:{'id':i,'name':nm}}
    cfg['position']=n['position']
    for k in ('onError','retryOnFail','alwaysOutputData'):
        if k in n: cfg[k]=n[k]
    body='{type:'+json.dumps(t)+',version:'+json.dumps(n['typeVersion'])+',config:'+js(cfg)+'}'
    fn='trigger' if t=='n8n-nodes-base.telegramTrigger' else ('switchCase' if t=='n8n-nodes-base.switch' else ('ifElse' if t=='n8n-nodes-base.if' else 'node'))
    out.append('const %s = %s(%s);'%(v,fn,body))
seen=set()
def build(name):
    v=var[name]
    if name in seen: return v
    seen.add(name)
    n=byname[name]; outs=conns.get(name,{}).get('main',[])
    if n['type']=='n8n-nodes-base.switch':
        s=v
        for i,tl in enumerate(outs):
            for t in tl: s+='.onCase(%d,%s)'%(i,build(t['node']))
        return s
    if n['type']=='n8n-nodes-base.if':
        s=v
        for i,tl in enumerate(outs):
            for t in tl: s+='.%s(%s)'%('onTrue' if i==0 else 'onFalse',build(t['node']))
        return s
    tg=[t['node'] for tl in outs for t in tl]
    if not tg: return v
    assert len(tg)==1,(name,tg)
    return v+'.to('+build(tg[0])+')'
trig=[n for n in nodes if n['type']=='n8n-nodes-base.telegramTrigger'][0]['name']
chain=build(trig)
missing=[n['name'] for n in nodes if n['name'] not in seen]
print('missing',missing,file=sys.stderr)
out.append('')
out.append("export default workflow('Y0Xjkwwljvku36ia', 'Agente | Telegram').add("+var[trig]+").to("+chain[len(var[trig])+4:-1]+");")
# ---------- compactar: fragmentos repetidos viram constantes (o update_workflow cola o codigo inteiro) ----------
_txt='\n'.join(out)
_dedupe=[('"credentials":{"telegramApi":{"id":"9wbEyTedyS1LrOAj","name":"Telegram Agente"}}','"credentials":CT','const CT = {"telegramApi":{"id":"9wbEyTedyS1LrOAj","name":"Telegram Agente"}};'),
         ('"credentials":{"postgres":{"id":"1xCdaqn8KYskDi8x","name":"Postgres Agente"}}','"credentials":CP','const CP = {"postgres":{"id":"1xCdaqn8KYskDi8x","name":"Postgres Agente"}};'),
         ('"credentials":{"redis":{"id":"66NcqCtUSKYiVp5K","name":"Redis Agente"}}','"credentials":CR','const CR = {"redis":{"id":"66NcqCtUSKYiVp5K","name":"Redis Agente"}};'),
         ('"credentials":{"openAiApi":{"id":"q99Ey7lWzPOBs4PJ","name":"OpenAI account"}}','"credentials":CO','const CO = {"openAiApi":{"id":"q99Ey7lWzPOBs4PJ","name":"OpenAI account"}};'),
         ('"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":2}','"options":O2','const O2 = {"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":2};'),
         ('"options":{"caseSensitive":true,"leftValue":"","typeValidation":"strict"}','"options":O1','const O1 = {"caseSensitive":true,"leftValue":"","typeValidation":"strict"};'),
         ('"operator":{"type":"string","operation":"equals"}','"operator":OE','const OE = {"type":"string","operation":"equals"};'),
         ('"chatId":expr("{{ $(\'Preparar envio\').first().json.chat_id }}"),','...K1,','const K1 = {"chatId":expr("{{ $(\'Preparar envio\').first().json.chat_id }}")};'),
         ('"text":expr("{{ $(\'Preparar envio\').first().json.html }}"),','...K2,','const K2 = {"text":expr("{{ $(\'Preparar envio\').first().json.html }}")};'),
         ('"replyMarkup":"inlineKeyboard",','...K3,','const K3 = {"replyMarkup":"inlineKeyboard"};'),
         ('"leftValue":expr("{{ $(\'Normalizar update\').first().json.kind }}"),','...K4,','const K4 = {"leftValue":expr("{{ $(\'Normalizar update\').first().json.kind }}")};'),
         ('"onError":"continueRegularOutput",','...K5,','const K5 = {"onError":"continueRegularOutput"};'),
         ('"mode":"runOnceForAllItems","language":"javaScript",','...K6,','const K6 = {"mode":"runOnceForAllItems","language":"javaScript"};')]
_decl=[]
for _a,_b,_c in _dedupe:
    if _a in _txt:
        _txt=_txt.replace(_a,_b); _decl.append(_c)
_i=_txt.index('\n\n')+2
_txt=_txt[:_i]+'\n'.join(_decl)+'\n\n'+_txt[_i:]
open('main.sdk.js','w').write(_txt)
print(len(_txt),'chars')
