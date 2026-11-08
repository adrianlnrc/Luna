import json,re,sys
w=json.load(open('modified.json'))
names={n['name'] for n in w['nodes']}
assert len(names)==len(w['nodes']),'nomes duplicados'
bad=0
for s,v in w['connections'].items():
    if s not in names: print('ORIGEM INEXISTENTE',s); bad+=1
    for outs in v['main']:
        for t in outs:
            if t['node'] not in names: print('DESTINO INEXISTENTE',s,'->',t['node']); bad+=1
trig=[n['name'] for n in w['nodes'] if n['type']=='n8n-nodes-base.telegramTrigger'][0]
seen={trig};q=[trig]
while q:
    x=q.pop()
    for outs in w['connections'].get(x,{}).get('main',[]):
        for t in outs:
            if t['node'] not in seen: seen.add(t['node']);q.append(t['node'])
orf=names-seen
print('orfaos (inalcancaveis):',sorted(orf))
bad+=len(orf)
# referencias $('Nome') em expressoes e codigo
refs=set()
for n in w['nodes']:
    s=json.dumps(n['parameters'],ensure_ascii=False)
    for m in re.finditer(r"\$\('([^']+)'\)",s):
        if m.group(1) not in names: print('REF A NO INEXISTENTE em',n['name'],':',m.group(1)); bad+=1
# switch/if: nº de saidas coerente
for n in w['nodes']:
    outs=w['connections'].get(n['name'],{}).get('main',[])
    if n['type']=='n8n-nodes-base.switch':
        k=(n['parameters']['numberOutputs'] if n['parameters'].get('mode')=='expression' else len(n['parameters']['rules']['values'])+(1 if n['parameters'].get('options',{}).get('fallbackOutput')=='extra' else 0))
        if len(outs)!=k: print('SWITCH saidas',n['name'],len(outs),'regras+fallback',k); bad+=1
    if n['type']=='n8n-nodes-base.if' and len(outs)>2: print('IF com >2 saidas',n['name']); bad+=1
print('nos:',len(names),'problemas:',bad)
sys.exit(1 if bad else 0)
