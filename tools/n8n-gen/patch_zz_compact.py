byname=_refresh()

# ---------- compactar switches grandes (modo expressao) ----------
import json as _json
def _to_expr_switch(name, keyexpr, extra=None):
    node_=byname[name]
    vals=node_['parameters']['rules']['values']
    m={}
    special={}
    for i,r in enumerate(vals):
        c=r['conditions']['conditions'][0]
        if c['operator']['operation']=='equals' and c['leftValue']==keyexpr:
            m[c['rightValue']]=i
        else:
            special[i]=c
    n=len(vals)
    mj=_json.dumps(m,separators=(',',':'))
    key=keyexpr[3:-3].strip()  # tira '={{' e '}}'
    fb=str(n)
    if extra: fb=extra.replace('@N',str(n))
    node_['parameters']={"mode":"expression","numberOutputs":n+1,"output":"={{ ("+mj+")["+key+"] !== undefined ? ("+mj+")["+key+"] : "+fb+" }}"}
    return special
sp=_to_expr_switch('Roteador de intencao','={{ $json.intent }}')
# regra 'tarefas' (task_action nao vazio) tem indice proprio
tidx=[i for i,c in sp.items() if 'task_action' in c['leftValue']][0]
rot=byname['Roteador de intencao']['parameters']
mj=rot['output'].split('[$json.intent] !==')[0][4:]
n=rot['numberOutputs']
rot['output']="={{ "+mj+"[$json.intent] !== undefined ? "+mj+"[$json.intent] : ($json.task_action ? "+str(tidx)+" : "+str(n-1)+") }}"
sp2=_to_expr_switch('Qual teclado?',"={{ $('Preparar envio').first().json.kb }}")
assert not sp2

# ---------- regras estaticas do prompt vao para o Redis (agente:cfg:rules) ----------
mp=byname[NEW]['parameters']['jsCode']
_a=mp.index("const regras = [\n"); _b=mp.index("\n];\nif (state && state.kind === 'clarify')")
_lines=mp[_a+len("const regras = [\n"):_b].split('\n')
_static=[]; _dyn=[]; _last=None
for _i,_l in enumerate(_lines):
    _t=_l.strip()
    if _t.endswith(','): _t=_t[:-1]
    if _t.startswith("'") and _t.endswith("'") and "' + " not in _t and "(user." not in _t:
        _static.append(_t[1:-1])
    else:
        if "FINANCAS categorias" in _t: _last=_t
        else: _dyn.append(_t)
assert _last and len(_static)>20, (len(_static), _last is None)
import json as _j
open('rules.json','w').write(_j.dumps(_static,ensure_ascii=False))
_new="""let ESTATICAS = [];
try { const rawR = $('Ler regras').first().json.regras; ESTATICAS = rawR ? JSON.parse(rawR) : []; } catch (e) { ESTATICAS = []; }
if (!ESTATICAS.length) { ESTATICAS = ['Se faltar informacao essencial, use intent=clarify. Responda sempre no schema.']; }
const regras = [
"""+"\n".join("  "+d+("," if not d.endswith(",") else "") for d in _dyn).rstrip(",")+"""
].concat(ESTATICAS).concat([
  """+_last+"""
]);"""
mp=mp[:_a]+_new+mp[_b+len("\n];"):]
byname[NEW]['parameters']['jsCode']=mp
nodes.append({"name":"Ler regras","type":"n8n-nodes-base.redis","typeVersion":1,"position":[1900,256],"parameters":{"operation":"get","key":"agente:cfg:rules","propertyName":"regras","keyType":"string"}})
_refresh()
setc('Ler configuracao do modelo',['Ler regras'])
setc('Ler regras',['Tipo de mensagem'])
