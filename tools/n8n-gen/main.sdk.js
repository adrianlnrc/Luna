import { workflow, node, trigger, switchCase, ifElse, expr } from '@n8n/workflow-sdk';

const CT = {"telegramApi":{"id":"9wbEyTedyS1LrOAj","name":"Telegram Agente"}};
const CP = {"postgres":{"id":"1xCdaqn8KYskDi8x","name":"Postgres Agente"}};
const CR = {"redis":{"id":"66NcqCtUSKYiVp5K","name":"Redis Agente"}};
const CO = {"openAiApi":{"id":"q99Ey7lWzPOBs4PJ","name":"OpenAI account"}};
const O2 = {"caseSensitive":true,"leftValue":"","typeValidation":"strict","version":2};
const O1 = {"caseSensitive":true,"leftValue":"","typeValidation":"strict"};
const OE = {"type":"string","operation":"equals"};
const K1 = {"chatId":expr("{{ $('Preparar envio').first().json.chat_id }}")};
const K2 = {"text":expr("{{ $('Preparar envio').first().json.html }}")};
const K3 = {"replyMarkup":"inlineKeyboard"};
const K4 = {"leftValue":expr("{{ $('Normalizar update').first().json.kind }}")};
const K5 = {"onError":"continueRegularOutput"};
const K6 = {"mode":"runOnceForAllItems","language":"javaScript"};

const n0 = trigger({type:"n8n-nodes-base.telegramTrigger",version:1.3,config:{"name":"Telegram","parameters":{"updates":["message","callback_query"]},"credentials":CT,"position":[0,256]}});
const n1 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Normalizar update","parameters":{...K6,"jsCode":`const u = $input.first().json;
const m = u.message || null;
const cb = u.callback_query || null;
let kind = 'other', text = '', file_id = '', chat_id = 0, from_id = 0, cb_id = '', cb_data = '', message_id = 0, mime = '', file_name = '', file_size = 0, tg_type = '';
if (cb) {
kind = 'callback'; chat_id = cb.message.chat.id; from_id = cb.from.id; cb_id = cb.id; cb_data = cb.data || ''; message_id = cb.message.message_id;
} else if (m) {
chat_id = m.chat.id; from_id = m.from.id; message_id = m.message_id;
if (m.voice || m.audio) { kind = 'voice'; file_id = (m.voice || m.audio).file_id; }
else if (Array.isArray(m.photo) && m.photo.length) { kind = 'photo'; file_id = m.photo[m.photo.length - 1].file_id; text = m.caption || ''; tg_type = 'photo'; file_size = Number(m.photo[m.photo.length - 1].file_size || 0); }
else if (m.document) {
const mt = String(m.document.mime_type || '').toLowerCase();
file_id = m.document.file_id; text = m.caption || ''; mime = mt; file_name = m.document.file_name || '';
const okTipo = mt === 'application/pdf' || mt === 'image/jpeg' || mt === 'image/png' || mt === 'image/webp' || mt === 'image/gif';
file_size = Number(m.document.file_size || 0); tg_type = 'document';
kind = (okTipo && file_size <= 15000000) ? 'document' : (file_size <= 52428800 ? 'file' : 'unsupported');
}
else if (m.video) {
file_id = m.video.file_id; text = m.caption || ''; mime = String(m.video.mime_type || ''); file_name = m.video.file_name || ''; tg_type = 'video';
file_size = Number(m.video.file_size || 0);
kind = file_size <= 52428800 ? 'file' : 'unsupported';
}
else if (typeof m.text === 'string') { text = m.text; kind = text.startsWith('/') ? 'command' : 'text'; }
}
let reply_text = '';
if (m && m.reply_to_message) { reply_text = String(m.reply_to_message.text || m.reply_to_message.caption || '').slice(0, 300); }
return [{ json: { reply_text: reply_text, update_id: u.update_id, kind: kind, chat_id: chat_id, from_id: from_id, text: text, file_id: file_id, cb_id: cb_id, cb_data: cb_data, message_id: message_id, mime: mime, file_name: file_name, file_size: file_size, tg_type: tg_type } }];`},"position":[224,256]}});
const n2 = node({type:"n8n-nodes-base.redis",version:1,config:{"name":"Marcar update no Redis","parameters":{"operation":"incr","key":expr("agente:upd:{{ $json.update_id }}"),"expire":true,"ttl":600},"credentials":CR,"position":[448,256]}});
const n3 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Checar duplicado","parameters":{...K6,"jsCode":`const n = Number(Object.values($input.first().json)[0]);
const base = $('Normalizar update').first().json;
return [{ json: Object.assign({}, base, { duplicado: n > 1 }) }];`},"position":[672,256]}});
const n4 = ifElse({type:"n8n-nodes-base.if",version:2.3,config:{"name":"Update novo?","parameters":{"conditions":{"options":O2,"conditions":[{"leftValue":expr("{{ $json.duplicado }}"),"operator":{"type":"boolean","operation":"false","singleValue":true},"rightValue":""}],"combinator":"and"}},"position":[896,256]}});
const n5 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Buscar usuario","parameters":{"operation":"executeQuery","query":"SELECT u.id, u.name, u.timezone, u.calendar_key, u.default_lead_minutes, u.supply_alert_days, u.onboarding_step, to_char(u.summary_time,'HH24:MI') AS summary_time, (SELECT string_agg(s.item, ', ') FROM agente.supplies s WHERE s.user_id = u.id AND s.status = 'active') AS supply_items, u.fin_closing_day, (SELECT string_agg(c.name, ', ' ORDER BY c.name) FROM agente.fin_categories c WHERE c.user_id = u.id AND c.kind = 'expense') AS fin_cats, u.nickname, u.no_emoji, agente.f_ai_places(u.id) AS places_txt, agente.f_ai_groups(u.id) AS groups_txt, agente.f_recent_actions_txt(u.id) AS recent_txt, agente.f_mem_prompt_txt(u.id, $2::text) AS mem_txt FROM agente.users u WHERE u.telegram_id = $1::bigint","options":{"queryReplacement":expr("{{ [ $('Normalizar update').first().json.from_id, (['text', 'photo', 'document'].indexOf($('Normalizar update').first().json.kind) >= 0 ? String($('Normalizar update').first().json.text || '') : '') ] }}")}},"credentials":CP,"position":[1120,256]}});
const n6 = node({type:"n8n-nodes-base.redis",version:1,config:{"name":"Ler estado da conversa","parameters":{"operation":"get","key":expr("agente:state:{{ $json.id }}"),"propertyName":"state","keyType":"string"},"credentials":CR,"position":[1344,256]}});
const n7 = node({type:"n8n-nodes-base.redis",version:1,config:{"name":"Ler historico da conversa","parameters":{"operation":"get","key":expr("agente:hist:{{ $('Buscar usuario').first().json.id }}"),"propertyName":"hist","keyType":"string"},"credentials":CR,"position":[1568,256]}});
const n8 = node({type:"n8n-nodes-base.redis",version:1,config:{"name":"Ler configuracao do modelo","parameters":{"operation":"get","key":"agente:cfg:model","propertyName":"modelo","keyType":"string"},"credentials":CR,"position":[1792,256]}});
const n9 = switchCase({type:"n8n-nodes-base.switch",version:3.4,config:{"name":"Tipo de mensagem","parameters":{"mode":"rules","rules":{"values":[{"outputKey":"botao","renameOutput":true,"conditions":{"options":O1,"conditions":[{...K4,"operator":OE,"rightValue":"callback"}],"combinator":"and"}},{"outputKey":"comando","renameOutput":true,"conditions":{"options":O1,"conditions":[{...K4,"operator":OE,"rightValue":"command"}],"combinator":"and"}},{"outputKey":"audio","renameOutput":true,"conditions":{"options":O1,"conditions":[{...K4,"operator":OE,"rightValue":"voice"}],"combinator":"and"}},{"outputKey":"texto","renameOutput":true,"conditions":{"options":O1,"conditions":[{...K4,"operator":OE,"rightValue":"text"}],"combinator":"and"}},{"outputKey":"foto","renameOutput":true,"conditions":{"options":O1,"conditions":[{...K4,"operator":OE,"rightValue":"photo"}],"combinator":"and"}},{"outputKey":"documento","renameOutput":true,"conditions":{"options":O1,"conditions":[{...K4,"operator":OE,"rightValue":"document"}],"combinator":"and"}},{"outputKey":"arquivo nao suportado","renameOutput":true,"conditions":{"options":O1,"conditions":[{...K4,"operator":OE,"rightValue":"unsupported"}],"combinator":"and"}},{"outputKey":"arquivo","renameOutput":true,"conditions":{"options":O1,"conditions":[{...K4,"operator":OE,"rightValue":"file"}],"combinator":"and"}}]}},"position":[2016,208]}});
const n10 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Confirmar clique","parameters":{"resource":"callback","operation":"answerQuery","queryId":expr("{{ $('Normalizar update').first().json.cb_id }}")},"credentials":CT,"position":[4256,0],"onError":"continueRegularOutput"}});
const n11 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Executar botao","parameters":{"operation":"executeQuery","query":"SELECT agente.f_callback($1::bigint, $2::text) AS r","options":{"queryReplacement":expr("{{ [ $('Buscar usuario').first().json.id, $('Normalizar update').first().json.cb_data ] }}")}},"credentials":CP,"position":[4480,0]}});
const n12 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Resposta do botao","parameters":{...K6,"jsCode":`const r = $input.first().json.r || {};
const u = $('Normalizar update').first().json;
return [{ json: { chat_id: u.chat_id, text: r.text || 'Ok.', kb: r.kb || 'none', rid: r.rid || 0, state: r.state || '' } }];`},"position":[4704,0]}});
const n13 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Preparar envio","parameters":{...K6,"jsCode":`const r = $input.first().json;
const NL = String.fromCharCode(10);
let text = String(r.text || 'Ok.');
if (text.length > 3900) { text = text.slice(0, 3900) + '...'; }
let kb = r.kb || 'none';
let rid = r.rid || 0;
let state = r.state || '';
let ia = {};
try { ia = $('Interpretar resposta').first().json || {}; } catch (e) { ia = {}; }
let mu = null;
try { mu = $('Multi: consolidar').first().json; } catch (e) { mu = null; }
const lines = (mu && Array.isArray(mu.multi_lines)) ? mu.multi_lines : [];
const fails = (mu && Array.isArray(mu.multi_fails)) ? mu.multi_fails : [];
const asks = (mu && Array.isArray(mu.multi_ask)) ? mu.multi_ask : [];
if (lines.length || fails.length || asks.length) {
const mainOk = kb === 'none' && text.indexOf('?') < 0 && text.length <= 200 && ia.intent !== 'clarify' && ia.intent !== 'chat';
const bul = [];
if (mainOk && lines.length) { bul.push(text.split(NL).join(' ')); }
lines.forEach(function (l) { bul.push(l); });
let out = '';
if (bul.length) { out = 'Feito:' + NL + bul.map(function (l) { return '- ' + l; }).join(NL); }
if (!(mainOk && lines.length)) { out = (out ? out + NL + NL : '') + text; }
if (fails.length) { out += NL + NL + fails.join(NL); }
if (asks.length) { out += NL + NL + 'Faltou saber ' + asks.join(' e ') + '. Me diz que eu faço.'; }
text = out;
if (asks.length && !state && kb === 'none') {
state = JSON.stringify({ kind: 'clarify', original: 'Falta so ' + asks.join(' e ') + ' (o resto do pedido anterior JA foi feito: nao repita nada, crie apenas o que faltava)' });
}
if (lines.length && kb === 'none' && mu && Number(mu.batch_id) > 0) { kb = 'multi_undo'; rid = Number(mu.batch_id); }
}
const un = String(ia.unsupported_note || '').trim();
if (un.length > 2 && ia.intent !== 'chat' && ia.intent !== 'clarify' && text.indexOf(un) < 0) { text = text + NL + NL + un; }
if (ia.social_event === true && ia.intent === 'create_event' && kb === 'none' && text.indexOf('?') < 0) { text = text + NL + 'Quer chamar alguém?'; }
let extra = '';
try { extra = String($('Interpretar resposta').first().json.extra_requests || '').trim(); } catch (e) { extra = ''; }
while (extra.length && '.!, '.indexOf(extra.charAt(extra.length - 1)) >= 0) { extra = extra.slice(0, -1); }
if (extra.length > 2 && ['null', 'nenhum', 'nenhuma', 'nada', 'none'].indexOf(extra.toLowerCase()) < 0) {
text = text + NL + NL + 'Também vi: ' + extra + '. Me manda isso separado que eu faço.';
}
let mem11 = null;
try { mem11 = $('Memoria: gravar').first().json.mem; } catch (e) { mem11 = null; }
if (Array.isArray(mem11) && mem11.length && ia.intent !== 'memory_manage') {
const anot11 = []; let dup11 = 0;
mem11.forEach(function (m) {
if (m && m.ok === true && m.duplicate !== true && m.text) { anot11.push(String(m.text).replace('Anotei: ', '')); }
else if (m && m.duplicate === true) { dup11++; }
});
const soFato = ia.intent === 'chat' && !String(ia.reply || '').trim();
if (anot11.length) { text = soFato ? 'Anotei: ' + anot11.join('; ') : text + NL + 'Anotei: ' + anot11.join('; '); }
else if (soFato) { text = dup11 ? 'Já estava anotado.' : 'Ok.'; }
}
const html = text.split('**').join('').split('&').join('&amp;').split('<').join('&lt;').split('>').join('&gt;');
return [{ json: { chat_id: r.chat_id, text: text, html: html, kb: kb, rid: rid, state: state } }];`},"position":[4928,1776]}});
const n14 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Resposta do comando","parameters":{...K6,"jsCode":`const u = $('Normalizar update').first().json;
const user = $('Buscar usuario').first().json;
const NL = String.fromCharCode(10);
const cmd = (u.text.split(' ')[0] || '').split('@')[0].toLowerCase();
let dados = {};
try { dados = $('Comando: dados').first().json.r || {}; } catch (e) { dados = {}; }
let x = null;
try { x = $('Comando: dados').first().json.x || null; } catch (e) { x = null; }
let text = '', kb = 'none';
if (u.kind === 'unsupported') {
text = 'Esse arquivo passa de 50 MB, o limite do Telegram para eu guardar e reenviar. Mande um menor.';
} else if (cmd === '/start') {
const linhasStart = ['Oi, ' + user.name + '! Sou o seu assistente pessoal aqui no Telegram. Pode falar por texto ou audio.', '',
'Alguns exemplos:',
'- "me lembre amanha as 9h de passar no mercado"',
'- "gastei 42 no mercado"',
'- "reuniao sexta as 14h, me lembre 1h antes"',
'- "me lembre de tomar losartana todo dia as 8h"',
'- "lista de mercado: arroz, cafe e detergente"', '',
'Pode mandar varios pedidos juntos. Toque em /menu para ver tudo, com exemplos de cada area.',
'(Para entender suas mensagens eu uso a OpenAI.)'];
if (user.onboarding_step !== 'done') {
linhasStart.push('', 'Para comecar: a que horas voce quer receber o resumo da manha?');
kb = 'summary_time';
}
text = linhasStart.join(NL);
} else if (cmd === '/menu' || cmd === '/ajuda' || cmd === '/help') {
text = [
'O que eu faço',
'',
'Toque numa área para ver exemplos. Pode falar do jeito do dia a dia, por texto ou áudio.',
'',
'Errei? Diga: "na verdade o dentista é às 10".',
'',
'Outros exemplos:',
'- "gastei 42 no mercado"',
'- "me lembra amanhã às 9h de ligar pro contador"',
'- "reunião sexta às 14h"',
'',
'Pode mandar vários pedidos juntos: eu faço todos e mostro num resumo "Feito". Se errar, toque em Desfazer tudo.'].join(NL);
kb = 'menu';
} else if (cmd === '/config') {
text = dados.config || 'Nao consegui ler suas preferencias agora. Tente de novo.';
if (x && typeof x.mem_enabled === 'boolean') {
text += NL + NL + 'Memória: ' + (x.mem_enabled ? 'ligada' : 'desligada') + NL + 'Perguntar se salvo: ' + (x.offer_save_enabled ? 'ligado' : 'desligado') + NL + 'Sugestões: ' + (x.suggest_enabled ? 'ligadas' : 'desligadas') + NL + '(Para mudar, é só dizer: "sem sugestões", "para de perguntar se salvo", "desliga a memória" e o contrário.)';
}
} else if (cmd === '/locais') {
text = (x && x.text) || dados.locais || 'Nao consegui ler seus locais agora. Tente de novo.';
} else if (cmd === '/custo') {
text = dados.custo || 'Nao consegui calcular o custo agora. Tente de novo.';
} else if (cmd === '/contatos') {
text = (x && x.text) || dados.contatos || 'Nao consegui ler seus contatos agora. Tente de novo.';
} else if (cmd === '/memoria') {
text = (x && x.text) || 'Nao consegui ler sua memoria agora. Tente de novo.';
} else {
text = 'Nao conheco esse comando. Use /ajuda.';
}
return [{ json: { chat_id: u.chat_id, text: text, kb: kb, rid: 0, state: '' } }];`},"position":[4704,192]}});
const n15 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Baixar audio","parameters":{"resource":"file","operation":"get","fileId":expr("{{ $('Normalizar update').first().json.file_id }}"),"download":true},"credentials":CT,"position":[2240,416]}});
const n16 = node({type:"n8n-nodes-base.extractFromFile",version:1.1,config:{"name":"Audio em base64","parameters":{"operation":"binaryToPropery","binaryPropertyName":"data","destinationKey":"audio_b64"},"position":[2464,416]}});
const n17 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Montar pedido a IA","parameters":{...K6,"jsCode":`let MODELO = 'gpt-6-luna';
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
const u = $('Normalizar update').first().json;
const user = $('Buscar usuario').first().json;
let state = null;
try { const raw = $('Ler estado da conversa').first().json.state; state = raw ? JSON.parse(raw) : null; } catch (e) { state = null; }
let hist = [];
try { const rawH = $('Ler historico da conversa').first().json.hist; hist = rawH ? JSON.parse(rawH) : []; } catch (e) { hist = []; }
const media = $input.first().json.audio_b64 || '';
const isPhoto = u.kind === 'photo';
const isDoc = u.kind === 'document';
const isPdf = isDoc && String(u.mime || '').indexOf('pdf') >= 0;
const isImgDoc = isDoc && !isPdf;
const tz = user.timezone || 'America/Sao_Paulo';
const agora = DateTime.now().setZone(tz).setLocale('pt-BR');
const NL = String.fromCharCode(10);
let ESTATICAS = [];
try { const rawR = $('Ler regras').first().json.regras; ESTATICAS = rawR ? JSON.parse(rawR) : []; } catch (e) { ESTATICAS = []; }
if (!ESTATICAS.length) { ESTATICAS = ['Se faltar informacao essencial, use intent=clarify. Responda sempre no schema.']; }
const regras = [
'Voce e o assistente pessoal de ' + (user.nickname || user.name) + ' no Telegram. Fale portugues do Brasil, curto e simpatico. Seu objetivo e deixar a vida do usuario o mais simples possivel: faca o pedido de UMA mensagem, sem pedir cadastro previo. Voce so INTERPRETA a mensagem e devolve o JSON do schema; quem executa e o sistema.',
'Agora: ' + agora.toFormat('yyyy-MM-dd HH:mm') + ' (' + agora.toFormat('cccc') + '), fuso ' + tz + '. Converta datas relativas (amanha, sexta, daqui a 2 horas) a partir de agora. Um dia da semana sem data e a proxima ocorrencia futura.',
'Itens de estoque/remedio ja cadastrados deste usuario: ' + (user.supply_items || 'nenhum') + '. Se o usuario falar de um deles (mesmo por outro nome, ou numa foto), use EXATAMENTE o nome cadastrado em item.',
(user.no_emoji ? 'NUNCA use emoji em reply.' : 'Emoji so quando combinar, poucos.'),
'LOCAIS E GRUPOS SALVOS deste usuario. Locais (nome = endereco): ' + (user.places_txt || 'nenhum') + '. Grupos: ' + (user.groups_txt || 'nenhum') + '.'
].concat(ESTATICAS).concat([
'FINANCAS categorias: category = nome de uma categoria deste usuario; category_stated=true SOMENTE se o usuario disse a categoria. Categorias deste usuario: ' + (user.fin_cats || 'Alimentação, Mercado, Transporte, Moradia, Saúde, Lazer, Educação, Assinaturas, Compras, Outros') + '. Receitas: Recebimentos, Salário. NUNCA invente valor: se faltar o valor, use intent=clarify e pergunte. Foto de recibo, nota fiscal, cupom ou comprovante: intent=finance, fin_action=add, amount = TOTAL pago (so se estiver legivel com certeza; senao clarify), title = estabelecimento, date = data da nota em YYYY-MM-DD se legivel. Diferenca: "paguei 50 no mercado" e add; "ja paguei o aluguel" e pay.'
]);
if (state && state.kind === 'clarify') {
regras.push('CONTEXTO: voce tinha perguntado algo porque a mensagem anterior do usuario estava incompleta: ' + (state.original || '') + '. Combine as duas SOMENTE se a mensagem atual for claramente a resposta a essa pergunta (so um horario, uma data, um nome, sim ou nao). Se a mensagem atual for um assunto novo ou outro pedido completo, trate como pedido novo e ignore o pedido pendente.');
}
if (state && state.kind === 'snooze') {
regras.push('CONTEXTO: o usuario esta escolhendo o NOVO horario para adiar um lembrete. Responda intent=provide_time com date e time.');
}
const NN = function (t) { return { type: [t, 'null'] }; };
const props = {
intent: { type: 'string', enum: ['create_reminder', 'create_event', 'list_agenda', 'create_supply', 'supply_bought', 'supply_adjust', 'supply_taken', 'supply_schedule', 'set_preference', 'provide_time', 'create_task', 'list_tasks', 'complete_task', 'finance', 'manage_event', 'cancel_reminder', 'contact_manage', 'misc_query', 'document_manage', 'list_manage', 'project_manage', 'note_manage', 'ai_cost', 'research', 'agenda_import', 'agenda_import_edit', 'correct_recent', 'memory_manage', 'clarify', 'chat'] },
transcript: { type: 'string' }, title: { type: 'string' }, date: { type: 'string' }, time: { type: 'string' }, reply: { type: 'string' },
duration_minutes: NN('integer'), location: NN('string'), lead_minutes: NN('integer'), shared: NN('boolean'),
range_start: NN('string'), range_end: NN('string'), item: NN('string'),
item_kind: { type: ['string', 'null'], enum: ['remedio', 'suplemento', null] },
take_time: NN('string'), stop_reminder: NN('boolean'), units_total: NN('integer'), units_per_day: NN('number'),
started_on: NN('string'), alert_days: NN('integer'), units_left: NN('integer'), pause_days: NN('integer'),
pref_lead_minutes: NN('integer'), pref_summary_time: NN('string'), pref_supply_days: NN('integer'), pref_nickname: NN('string'), pref_work_start: NN('string'), pref_work_end: NN('string'),
ev_action: { type: ['string', 'null'], enum: ['move', 'cancel', 'free', 'promote', null] },
repeat_freq: { type: ['string', 'null'], enum: ['daily', 'weekly', 'monthly', 'yearly', null] }, repeat_until: NN('string'), repeat_count: NN('integer'),
link_event: NN('string'), invitees: { type: ['array', 'null'], items: { type: 'string' } }, meet: NN('boolean'),
contact_action: { type: ['string', 'null'], enum: ['save', 'list', 'remove', 'group_save', 'group_list', 'group_remove', 'place_save', 'place_list', 'place_remove', null] },
contact_name: NN('string'), contact_email: NN('string'), group_name: NN('string'), group_members: { type: ['array', 'null'], items: { type: 'string' } },
query_kind: { type: ['string', 'null'], enum: ['reminder_history', 'tasks_closed', 'calendar_link', null] },
doc_action: { type: ['string', 'null'], enum: ['save', 'find', 'send_folder', 'move', 'rename', 'delete', 'list_folders', 'create_folder', 'expiry_set', null] },
folder: NN('string'), folder_to: NN('string'), doc_query: NN('string'), expires_on: NN('string'),
list_action: { type: ['string', 'null'], enum: ['create', 'show', 'add', 'remove', 'check', 'uncheck', 'clear', 'delete', 'lists', null] },
list_name: NN('string'), list_items: { type: ['array', 'null'], items: { type: 'string' } },
project_action: { type: ['string', 'null'], enum: ['create', 'show', 'list', 'add_tasks', 'complete_task', 'reopen_task', 'set_urgent', 'set_due', 'rename', 'delete', 'overdue', null] },
project_name: NN('string'), project_tasks: { type: ['array', 'null'], items: { type: 'string' } }, task_name: NN('string'), urgent: NN('boolean'),
note_action: { type: ['string', 'null'], enum: ['save', 'search', 'list', 'delete', null] },
note_text: NN('string'), note_query: NN('string'),
card: NN('string'), card_closing_day: NN('integer'), card_due_day: NN('integer'), card_limit: NN('number'), month: NN('string'), pref_no_emoji: NN('boolean'), pref_timezone: NN('string'), pref_evening: NN('string'), pref_morning: NN('string'),
fin_action: { type: ['string', 'null'], enum: ['add', 'pay', 'correct', 'remove', 'summary', 'compare', 'top', 'by_day', 'budget_set', 'budget_status', 'category_create', 'category_list', 'closing_set', 'report', 'owed', 'limit_set', 'limit_status', 'limit_clear', 'income_set', 'plan_status', 'goal_create', 'goal_deposit', 'goal_withdraw', 'goal_status', 'goal_edit', 'goal_remove', 'card_create', 'card_edit', 'card_remove', 'card_list', 'card_status', 'category_total', 'method_total', 'left_to_close', 'committed', null] },
fin_kind: { type: ['string', 'null'], enum: ['expense', 'income', null] },
amount: NN('number'), category: NN('string'), category_stated: NN('boolean'),
method: { type: ['string', 'null'], enum: ['pix', 'debito', 'credito', 'dinheiro', 'boleto', null] },
installments: NN('integer'), paid: NN('boolean'), recurring_day: NN('integer'), person: NN('string'),
period: { type: ['string', 'null'], enum: ['current', 'previous', 'today', 'yesterday', 'week', null] },
keywords: NN('string'), budget_amount: NN('number'), closing_day: NN('integer'),
report_format: { type: ['string', 'null'], enum: ['csv', 'xlsx', 'pdf', null] },
extra_requests: NN('string'),
fin_items: { type: ['array', 'null'], items: { type: 'object', properties: { title: { type: 'string' }, amount: { type: 'number' }, category: { type: ['string', 'null'] } }, required: ['title', 'amount', 'category'], additionalProperties: false } },
supply_action: { type: ['string', 'null'], enum: ['rename', 'delete', null] }, new_name: NN('string'),
research_query: NN('string'),
imp_action: { type: ['string', 'null'], enum: ['edit', 'remove', 'confirm', 'cancel', null] }, imp_n: NN('integer'), imp_end: NN('string'),
recent_id: NN('integer'), unsupported_note: NN('string'), social_event: NN('boolean'),
more_actions: { type: ['array', 'null'], items: { type: 'object', properties: {
kind: { type: 'string', enum: ['lembrete', 'compromisso', 'tarefa', 'gasto', 'nota', 'lista', 'tomei'] }, title: { type: 'string' },
date: NN('string'), time: NN('string'), duration_minutes: NN('integer'), lead_minutes: NN('integer'), location: NN('string'),
amount: NN('number'), list_name: NN('string'), items: { type: ['array', 'null'], items: { type: 'string' } } },
required: ['kind', 'title', 'date', 'time', 'duration_minutes', 'lead_minutes', 'location', 'amount', 'list_name', 'items'], additionalProperties: false } },
mem_facts: { type: ['array', 'null'], items: { type: 'object', properties: { texto: { type: 'string' }, tipo: { type: 'string', enum: ['habito', 'preferencia', 'fato', 'relacao'] } },
required: ['texto', 'tipo'], additionalProperties: false } },
new_person: NN('string'), new_person_rel: NN('string'), new_place: NN('string'),
mem_action: { type: ['string', 'null'], enum: ['forget', 'list', 'switch_on', 'switch_off', 'offer_yes', 'offer_no', null] }, mem_ref: NN('string')
};
const schema = { type: 'object', properties: props, required: Object.keys(props), additionalProperties: false };
let atual = u.text || '';
if (u.kind === 'voice') { atual = String($input.first().json.text || '').trim(); }
if (isPhoto && !atual) { atual = 'Imagem enviada pelo usuario, sem legenda.'; }
if (isDoc && !atual) { atual = 'Arquivo enviado pelo usuario, sem legenda.'; }
const agoraMs = Date.now();
const recentes = hist.filter(function (h) { return h && h.t && (agoraMs - h.ts) < 6 * 3600 * 1000; });
while (recentes.length && recentes[0].r !== 'user') { recentes.shift(); }
const linhas = recentes.map(function (h) { return (h.r === 'model' ? 'Assistente: ' : 'Usuario: ') + h.t; });
let prompt = '';
if (linhas.length) { prompt = 'CONVERSA RECENTE (mais antiga primeiro):' + NL + linhas.join(NL) + NL + NL; }
if (user.recent_txt) { prompt += 'ACOES RECENTES (mais recente primeiro):' + NL + user.recent_txt + NL + NL; }
if (u.reply_text) { prompt += 'RESPONDIDA (o usuario respondeu a esta mensagem sua, via reply do Telegram):' + NL + u.reply_text + NL + NL; }
if (user.mem_txt) { prompt += user.mem_txt + NL + NL; }
if (state && state.kind === 'offer' && Number(state.ts) > 0 && (agoraMs - Number(state.ts)) < 900000) {
prompt += 'OFERTA PENDENTE (voce perguntou se salva' + (state.pessoa ? ' a pessoa ' + state.pessoa : '') + (state.lugar ? ' e o lugar ' + state.lugar : '') + (state.accepted ? '; ja salvo, so falta o e-mail ou endereco' : '') + '). Se a mensagem responde a isso, use memory_manage (offer_yes ou offer_no).' + NL + NL;
}
if (state && state.kind === 'suggest' && Number(state.ts) > 0 && (agoraMs - Number(state.ts)) < 3600000) {
prompt += 'SUGESTAO PENDENTE (voce acabou de perguntar): ' + String(state.text || '') + ' dados=' + JSON.stringify(state.data || {}) + '. Se aceitar (sim, pode): conta = finance com fin_action=add, title, amount e recurring_day dos dados; lembrete = create_reminder com o title dos dados e repeat_freq=weekly (sem hora, clarify). Se recusar, responda curto e nao insista.' + NL + NL;
}
prompt += 'MENSAGEM ATUAL DO USUARIO' + (u.kind === 'voice' ? ' (transcricao de audio)' : '') + ':' + NL + atual;
if (isPhoto) { prompt += NL + '(Uma imagem esta anexada a esta mensagem.)'; }
if (isDoc) { prompt += NL + '(Um arquivo ' + (isPdf ? 'PDF' : 'de imagem') + (u.file_name ? ' chamado ' + u.file_name : '') + ' esta anexado a esta mensagem.)'; }
return [{ json: { modelo: MODELO, instrucoes: regras.join(NL), prompt: prompt, schema_json: JSON.stringify(schema),
image_url: (media && (isPhoto || isImgDoc)) ? 'data:' + (isImgDoc ? u.mime : 'image/jpeg') + ';base64,' + media : '', texto_atual: atual, state: state,
file_b64: (media && isPdf) ? media : '', file_name: u.file_name || 'documento.pdf',
history_size: recentes.length, via_audio: u.kind === 'voice', via_photo: (isPhoto || isImgDoc) && !!media, via_pdf: isPdf && !!media } }];`},"position":[2688,2032]}});
const n18 = node({type:"n8n-nodes-base.redis",version:1,config:{"name":"Limpar estado","parameters":{"operation":"delete","key":expr("agente:state:{{ $('Buscar usuario').first().json.id }}")},"credentials":CR,"position":[2912,2032]}});
const n19 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Mostrar digitando","parameters":{"resource":"message","operation":"sendChatAction","chatId":expr("{{ $('Normalizar update').first().json.chat_id }}"),"action":"typing"},"credentials":CT,"position":[3136,2032],"onError":"continueRegularOutput"}});
const n20 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Interpretar resposta","parameters":{...K6,"jsCode":`const r = $input.first().json;
const u = $('Normalizar update').first().json;
const user = $('Buscar usuario').first().json;
const ctx = $('Montar pedido a IA').first().json;
const tz = user.timezone || 'America/Sao_Paulo';
const base = { user_id: user.id, user_name: user.name, tz: tz, calendar_key: user.calendar_key || '', chat_id: u.chat_id, source: ctx.via_audio ? 'audio' : 'text', original_text: u.text };
{
let tipoIA = 'texto';
if (ctx.via_pdf === true) { tipoIA = 'pdf'; } else if (ctx.via_photo === true) { tipoIA = 'foto'; } else if (ctx.via_audio === true) { tipoIA = 'voz'; }
base.ai_kind = tipoIA;
base.ai_model = String(ctx.modelo || '');
base.ai_tin = null; base.ai_tout = null; base.ai_est = false;
if (r && r.usage && typeof r.usage.input_tokens === 'number') {
base.ai_tin = r.usage.input_tokens;
base.ai_tout = (typeof r.usage.output_tokens === 'number') ? r.usage.output_tokens : 0;
}
}
let g = null;
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
if (!g || !g.intent) {
let errTxt = '';
if (r && r.error) { errTxt = typeof r.error === 'string' ? r.error : JSON.stringify(r.error); }
const quota = /quota|too many requests|rate limit|429|insufficient|billing/i.test(errTxt);
const modeloOff = /model_not_found|does not exist|no longer available|not found|could not be found/i.test(errTxt);
let msg = 'Tive um problema para entender agora. Pode tentar de novo em instantes?';
if (quota) { msg = 'Atingi o limite de uso da OpenAI (credito ou cota). Verifique o saldo da conta para eu voltar a responder.'; }
else if (modeloOff) { msg = 'O modelo configurado (' + ctx.modelo + ') nao esta disponivel. Preciso que o administrador troque o modelo.'; }
return [{ json: Object.assign({}, base, { intent: 'chat', llm_error: true, llm_detail: errTxt.slice(0, 300), reply: msg }) }];
}
Object.keys(g).forEach(function (k) { if (g[k] === null) { delete g[k]; } });
if (!g.transcript) { g.transcript = ctx.texto_atual || ''; }
const out = Object.assign({}, base, g);
if (out.ai_tin === null) {
out.ai_tin = Math.ceil((String(ctx.instrucoes || '').length + String(ctx.prompt || '').length + String(ctx.schema_json || '').length) / 4);
out.ai_tout = Math.ceil(JSON.stringify(g).length / 4);
out.ai_est = true;
}
['title', 'date', 'time', 'reply', 'item', 'location'].forEach(function (k) { if (out[k] === null || out[k] === undefined) { out[k] = ''; } });
if (typeof out.units_total === 'number' && out.units_total <= 0) { delete out.units_total; }
if (typeof out.units_per_day === 'number' && out.units_per_day <= 0) { delete out.units_per_day; }
if (typeof out.units_left === 'number' && out.units_left < 0) { delete out.units_left; }
if (typeof out.duration_minutes === 'number' && out.duration_minutes <= 0) { delete out.duration_minutes; }
if (typeof out.lead_minutes === 'number' && out.lead_minutes < 0) { delete out.lead_minutes; }
const now = DateTime.now().setZone(tz);
const okDate = /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/;
const okTime = /^[0-9]{1,2}:[0-9]{2}$/;
const st = ctx.state;
if (st && st.kind === 'snooze' && (g.intent === 'provide_time' || g.intent === 'create_reminder' || g.intent === 'clarify') && (g.time || /[0-9]/.test(String(u.text || '')))) {
out.intent = 'provide_time'; out.rid = st.reminder_id;
}
if (out.intent === 'create_reminder' && out.link_event && !(out.time && okTime.test(out.time))) {
out.intent = 'link_reminder';
out.lr_json = JSON.stringify({ title: out.title || '', link_event: out.link_event, person: out.person || '', lead_minutes: (typeof out.lead_minutes === 'number' && out.lead_minutes > 0) ? out.lead_minutes : null, source: ctx.via_audio ? 'audio' : 'text' });
}
const trSemAcento = function (s) {
const de = 'áàâãäéèêëíìîïóòôõöúùûüç';
const para = 'aaaaaeeeeiiiiooooouuuuc';
let r = '';
String(s || '').toLowerCase().split('').forEach(function (ch) { const k = de.indexOf(ch); r += k >= 0 ? para.charAt(k) : ch; });
return r.trim();
};
const trListaTracos = function (txt) {
const NL = String.fromCharCode(10);
const linhas = String(txt || '').split(NL);
const marcas = '-•*–';
const itens = [];
let primeira = -1;
for (let i = 0; i < linhas.length; i++) {
const t = linhas[i].trim();
if (t === '' || marcas.indexOf(t.charAt(0)) < 0) { continue; }
let k = 0;
while (k < t.length && (marcas.indexOf(t.charAt(k)) >= 0 || t.charAt(k) === ' ')) { k++; }
let item = t.slice(k).trim();
while (item.length > 0 && ',;'.indexOf(item.charAt(item.length - 1)) >= 0) { item = item.slice(0, item.length - 1).trim(); }
if (item === '') { continue; }
if (primeira < 0) { primeira = i; }
itens.push(item);
}
if (itens.length < 2) { return null; }
let cab = '';
for (let j = primeira - 1; j >= 0; j--) {
if (linhas[j].trim() !== '') { cab = linhas[j].trim(); break; }
}
while (cab.length > 0 && ':.-'.indexOf(cab.charAt(cab.length - 1)) >= 0) { cab = cab.slice(0, cab.length - 1).trim(); }
let nome = cab.replace(/^((a|o|minha|nossa) )*lista ((de|da|do|dos|das) )?/i, '').trim();
const chave = trSemAcento(nome).split(' ').filter(function (x) { return x !== ''; }).join(' ');
const padroes = ['', 'lista', 'mercado', 'compras', 'compra', 'supermercado', 'super', 'feira', 'feiras', 'mercados', 'preciso comprar', 'comprar', 'pra comprar', 'para comprar', 'falta', 'faltam', 'anota', 'anota ai', 'anota ai na lista'];
const apelidos = ['mercado', 'compras', 'compra', 'supermercado', 'super', 'feira', 'feiras', 'mercados'];
if (padroes.indexOf(chave) >= 0 || chave.split(' ').length > 4 || apelidos.indexOf(chave.split(' ')[0]) >= 0) { nome = ''; }
return { itens: itens, nome: nome };
};
if (out.source === 'text' && u.kind === 'text') {
const trLista = trListaTracos(u.text);
if (trLista) {
out.intent = 'list_manage';
out.list_action = 'add';
out.list_items = trLista.itens;
out.list_name = trLista.nome || null;
}
}
const needsTime = ['create_reminder', 'create_event', 'provide_time'].indexOf(out.intent) >= 0;
if (needsTime) {
const txt = String(out.transcript || u.text || '').toLowerCase();
let tm = out.time && okTime.test(out.time) ? out.time : '';
let dd = out.date && okDate.test(out.date) ? out.date : '';
let ultimo = null;
try {
const rawH = $('Ler historico da conversa').first().json.hist;
const hh = rawH ? JSON.parse(rawH) : [];
for (let i = hh.length - 1; i >= 0 && !ultimo; i--) {
const m = /[[]agendado: ([0-9-]{10}) ([0-9:]{5})[]]/.exec(String(hh[i].t || ''));
if (m) { ultimo = { d: m[1], t: m[2] }; }
}
} catch (e) { ultimo = null; }
if (!tm) {
let m1 = /(?:as|às|a)[ ]*([0-9]{1,2})[ ]*(?:h|:)[ ]*([0-9]{2})?/i.exec(txt);
if (!m1) { m1 = /([0-9]{1,2})[ ]*(?:h|:)([0-9]{2})?/i.exec(txt); }
if (m1) { tm = m1[1] + ':' + (m1[2] ? m1[2] : '00'); }
}
const mesmo = /mesm[oa][ ]*(horario|hora|dia)/i.test(txt) || /mesm[oa][ ]*(horário)/i.test(txt);
if (!tm && mesmo && ultimo) { tm = ultimo.t; if (!dd) { dd = ultimo.d; } }
if (!dd) {
if (txt.indexOf('depois de amanh') >= 0) { dd = now.plus({ days: 2 }).toFormat('yyyy-MM-dd'); }
else if (txt.indexOf('amanh') >= 0) { dd = now.plus({ days: 1 }).toFormat('yyyy-MM-dd'); }
else if (txt.indexOf('hoje') >= 0) { dd = now.toFormat('yyyy-MM-dd'); }
else if (mesmo && ultimo) { dd = ultimo.d; }
}
if (!tm) {
out.intent = 'clarify'; out.reply = out.reply || 'Que horas? Me diga o horario exato.';
} else {
const hhmm = tm.length === 4 ? '0' + tm : tm;
let d = dd || null;
if (!d) { const t = DateTime.fromISO(now.toFormat('yyyy-MM-dd') + 'T' + hhmm, { zone: tz }); d = (t > now ? t : t.plus({ days: 1 })).toFormat('yyyy-MM-dd'); }
const due = DateTime.fromISO(d + 'T' + hhmm, { zone: tz });
if (!due.isValid) { out.intent = 'clarify'; out.reply = 'Nao entendi a data e a hora. Pode repetir?'; }
else if (due <= now) { out.intent = 'clarify'; out.reply = 'Esse horario ja passou. Para quando eu agendo?'; }
else {
out.due_iso = due.toISO(); out.due_label = due.setLocale('pt-BR').toFormat("ccc dd/MM 'as' HH:mm");
out.end_iso = due.plus({ minutes: out.duration_minutes || 60 }).toISO();
}
}
}
if (out.intent === 'list_agenda') {
const today = now.toFormat('yyyy-MM-dd');
const a = out.range_start && okDate.test(out.range_start) ? out.range_start : today;
const b = out.range_end && okDate.test(out.range_end) ? out.range_end : a;
const ini = DateTime.fromISO(a, { zone: tz }).startOf('day');
const fim = DateTime.fromISO(b, { zone: tz }).startOf('day').plus({ days: 1 });
out.time_min = ini.toISO(); out.time_max = fim.toISO();
out.range_label = a === b ? ini.toFormat('dd/MM') : ini.toFormat('dd/MM') + ' a ' + fim.minus({ days: 1 }).toFormat('dd/MM');
}
let tt = '';
if (out.take_time && okTime.test(out.take_time)) { tt = out.take_time.length === 4 ? '0' + out.take_time : out.take_time; }
if (!tt && (out.intent === 'create_supply' || out.intent === 'supply_schedule') && out.time && okTime.test(out.time)) { tt = out.time.length === 4 ? '0' + out.time : out.time; }
out.take_time = tt;
out.item_kind = out.item_kind === 'remedio' ? 'remedio' : '';
if (out.intent === 'supply_schedule' && out.stop_reminder !== true && !tt) {
out.intent = 'clarify'; out.reply = out.reply || 'A que horas voce quer ser lembrado de tomar?';
}
out.task_due = (out.intent === 'create_task' && out.date && okDate.test(out.date)) ? out.date : '';
out.task_action = out.intent === 'create_task' ? 'add' : (out.intent === 'list_tasks' ? 'list' : (out.intent === 'complete_task' ? 'complete' : ''));
out.lead_str = (out.lead_minutes === undefined || out.lead_minutes === null) ? '' : String(out.lead_minutes);
out.shared = out.shared === true;
out.title = out.title || '';
if (out.intent === 'create_event') {
const rfq = (out.repeat_freq === 'daily' || out.repeat_freq === 'weekly' || out.repeat_freq === 'monthly') ? out.repeat_freq : '';
out.rp_freq = rfq;
out.rp_until = (rfq && out.repeat_until && okDate.test(out.repeat_until)) ? out.repeat_until : '';
out.rp_count = (rfq && !out.rp_until && typeof out.repeat_count === 'number' && out.repeat_count > 0) ? String(Math.floor(out.repeat_count)) : '';
}
if (out.intent === 'manage_event') {
const act = (out.ev_action === 'move' || out.ev_action === 'cancel' || out.ev_action === 'free' || out.ev_action === 'promote') ? out.ev_action : '';
if (!act) {
out.intent = 'clarify'; out.reply = out.reply || 'O que voce quer fazer na agenda: mover, cancelar, ver horario livre ou transformar um lembrete em compromisso?';
} else {
const txtm = String(out.transcript || u.text || '').toLowerCase();
const rs = (out.range_start && okDate.test(out.range_start)) ? out.range_start : '';
const rb = (out.range_end && okDate.test(out.range_end)) ? out.range_end : '';
const dd = (out.date && okDate.test(out.date)) ? out.date : '';
const mg = { act: act, title: out.title || '', calendar_key: out.calendar_key || '' };
let ini = now.startOf('day');
let fim = now.startOf('day').plus({ days: 60 });
if (act === 'promote') {
ini = now; fim = now.plus({ minutes: 60 });
if (out.duration_minutes) { mg.duration_minutes = out.duration_minutes; }
} else if (act === 'free') {
let a0 = rs || dd || now.toFormat('yyyy-MM-dd');
let b0 = rb || a0;
if (b0 < a0) { const tmp = a0; a0 = b0; b0 = tmp; }
ini = DateTime.fromISO(a0, { zone: tz }).startOf('day');
fim = DateTime.fromISO(b0, { zone: tz }).startOf('day').plus({ days: 1 });
if (fim > ini.plus({ days: 7 })) { fim = ini.plus({ days: 7 }); }
const pt = String(out.time || '').toLowerCase();
let part = '';
if (pt.indexOf('manh') >= 0) { part = 'manha'; }
else if (pt.indexOf('tarde') >= 0) { part = 'tarde'; }
else if (pt.indexOf('noite') >= 0) { part = 'noite'; }
else if (/^[0-9]{1,2}:[0-9]{2}-[0-9]{1,2}:[0-9]{2}$/.test(pt)) { part = pt; }
else if (/(^|[^a-z])manh/.test(txtm)) { part = 'manha'; }
else if (txtm.indexOf('tarde') >= 0) { part = 'tarde'; }
else if (txtm.indexOf('noite') >= 0) { part = 'noite'; }
mg.part = part;
mg.min_minutes = out.duration_minutes || 30;
} else {
const a0 = rs || dd;
const b0 = rb || a0;
if (act === 'cancel') {
if (a0) { ini = DateTime.fromISO(a0, { zone: tz }).startOf('day'); fim = DateTime.fromISO(b0, { zone: tz }).startOf('day').plus({ days: 1 }); }
} else {
const a1 = rs;
const b1 = rb || rs;
if (a1) { ini = DateTime.fromISO(a1, { zone: tz }).startOf('day'); fim = DateTime.fromISO(b1, { zone: tz }).startOf('day').plus({ days: 1 }); }
let tm = (out.time && okTime.test(out.time)) ? out.time : '';
if (!tm) {
const re1 = /([0-9]{1,2})[ ]*(?:h|:)[ ]*([0-9]{2})?/gi;
let mm = re1.exec(txtm);
while (mm) { tm = mm[1] + ':' + (mm[2] ? mm[2] : '00'); mm = re1.exec(txtm); }
}
if (!tm) {
out.intent = 'clarify'; out.reply = 'Para que horario eu movo "' + (out.title || 'o compromisso') + '"?';
} else {
const hhmm = tm.length === 4 ? '0' + tm : tm;
mg.new_time = hhmm;
if (out.duration_minutes) { mg.duration_minutes = out.duration_minutes; }
if (dd) {
const nd = DateTime.fromISO(dd + 'T' + hhmm, { zone: tz });
if (!nd.isValid) { out.intent = 'clarify'; out.reply = 'Nao entendi a nova data e hora. Pode repetir?'; }
else if (nd <= now) { out.intent = 'clarify'; out.reply = 'Esse horario novo ja passou. Para quando eu movo?'; }
else {
mg.new_start = nd.toISO();
if (nd.startOf('day') < ini) { ini = nd.startOf('day'); }
if (nd.startOf('day').plus({ days: 1 }) > fim) { fim = nd.startOf('day').plus({ days: 1 }); }
}
}
}
}
}
if (out.intent === 'manage_event') {
out.time_min = ini.toISO(); out.time_max = fim.toISO();
mg.win_start = out.time_min; mg.win_end = out.time_max;
out.mg = mg;
}
}
}
if (out.intent === 'create_reminder') {
out.repeat_json = JSON.stringify({
freq: out.repeat_freq || '',
until: (out.repeat_until && okDate.test(out.repeat_until)) ? out.repeat_until : '',
count: (typeof out.repeat_count === 'number' && out.repeat_count > 0) ? out.repeat_count : ''
});
}
if (out.intent === 'misc_query') {
out.misc_json = JSON.stringify({ kind: out.query_kind || '', title: out.title || '' });
out.closed_min = now.startOf('week').toUTC().toISO();
}
const semAcento = function (s) {
const de = 'áàâãäéèêëíìîïóòôõöúùûüç';
const para = 'aaaaaeeeeiiiiooooouuuuc';
let r = '';
String(s || '').toLowerCase().split('').forEach(function (ch) { const k = de.indexOf(ch); r += k >= 0 ? para.charAt(k) : ch; });
return r.trim();
};
const tiraArtigo = function (s) { return semAcento(s).replace(/^(a|o|na|no|da|do|de|em)[ ]+/, ''); };
const localNome = function (loc) {
const t = String(loc || '').trim();
if (t === '' || t.length > 40 || /[0-9]/.test(t)) { return false; }
return !/(^|[^a-z])(online|zoom|meet|teams|remoto|telefone)([^a-z]|$)/.test(semAcento(t));
};
const localDesconhecido = function (loc) {
if (!localNome(loc)) { return false; }
const alvo = tiraArtigo(loc);
if (alvo === '') { return false; }
const salvos = String(user.places_txt || '').split('; ');
for (let i = 0; i < salvos.length; i++) {
const nm = salvos[i].split(' = ')[0];
if (tiraArtigo(nm) === alvo) { return false; }
}
return true;
};
if (out.intent === 'create_event' && out.due_iso) {
const convidados = Array.isArray(out.invitees) ? out.invitees.filter(function (x) { return String(x || '').trim() !== ''; }) : [];
if (convidados.length > 0 || out.meet === true || localDesconhecido(out.location)) {
out.intent = 'invite_event';
out.invite_json = JSON.stringify({
summary: out.title || '', start: out.due_iso, end: out.end_iso || '', location: out.location || '',
meet: out.meet === true, invitees: convidados, repeat_freq: out.repeat_freq || '', repeat_until: out.repeat_until || '',
repeat_count: out.repeat_count || null, lead_str: out.lead_str || '',
source: (u.kind === 'photo' || u.kind === 'document') ? 'photo' : (ctx.via_audio ? 'audio' : 'text')
});
}
}
if (out.intent === 'contact_manage') {
out.contact_json = JSON.stringify({
contact_action: out.contact_action || '', contact_name: out.contact_name || '', contact_email: out.contact_email || '', place_address: out.location || '',
group_name: out.group_name || '', group_members: Array.isArray(out.group_members) ? out.group_members : [],
text: String(out.transcript || u.text || '')
});
}
if (out.intent === 'document_manage') {
out.docs_json = JSON.stringify({
action: out.doc_action || '', title: out.title || '', query: out.doc_query || '', folder: out.folder || '', folder_to: out.folder_to || '',
expires_on: (out.expires_on && okDate.test(out.expires_on)) ? out.expires_on : '', alert_days: out.alert_days || null,
file_id: (u.kind === 'photo' || u.kind === 'document') ? (u.file_id || '') : ''
});
}
if (out.intent === 'list_manage') {
out.list_json = JSON.stringify({
list_action: out.list_action || '', list_name: out.list_name || '',
list_items: Array.isArray(out.list_items) ? out.list_items.filter(function (x) { return String(x || '').trim() !== ''; }) : [],
text: String(out.transcript || u.text || '')
});
}
if (out.intent === 'note_manage') {
out.note_json = JSON.stringify({
note_action: out.note_action || '', note_text: out.note_text || '', note_query: out.note_query || '',
text: String(out.transcript || u.text || '')
});
}
if (out.intent === 'project_manage') {
out.proj_json = JSON.stringify({
action: out.project_action || '',
name: out.project_name || '',
title: out.title || '',
task: out.task_name || '',
tasks: Array.isArray(out.project_tasks) ? out.project_tasks.filter(function (x) { return String(x || '').trim() !== ''; }) : [],
due: (out.date && okDate.test(out.date)) ? out.date : '',
urgent: (typeof out.urgent === 'boolean') ? out.urgent : null
});
}
if (out.intent === 'research') {
let pq = String(out.research_query || '').trim();
if (pq === '') { pq = String(out.transcript || u.text || '').trim(); }
out.research_query = pq.slice(0, 500);
}
if (out.intent === 'agenda_import' && ctx.via_photo !== true) {
out.intent = 'chat';
out.reply = 'Para importar a sua agenda, mande a foto da página inteira, bem iluminada e sem reflexo. Eu leio e mostro tudo antes de criar.';
}
if (out.intent === 'agenda_import_edit') {
const iact = (out.imp_action === 'edit' || out.imp_action === 'remove' || out.imp_action === 'confirm' || out.imp_action === 'cancel') ? out.imp_action : 'edit';
const hm2 = function (v) { return (v && okTime.test(v)) ? (v.length === 4 ? '0' + v : v) : ''; };
out.imp_json = JSON.stringify({ act: iact, n: (typeof out.imp_n === 'number') ? out.imp_n : null, title: out.title || '',
date: (out.date && okDate.test(out.date)) ? out.date : '', time: hm2(out.time), end: hm2(out.imp_end) });
}
if (out.intent === 'correct_recent') {
const hm3 = function (v) { return (v && okTime.test(v)) ? (v.length === 4 ? '0' + v : v) : ''; };
out.corr_json = JSON.stringify({ recent_id: (typeof out.recent_id === 'number') ? out.recent_id : null, title: out.title || '',
date: (out.date && okDate.test(out.date)) ? out.date : '', time: hm3(out.time), note_text: out.note_text || '' });
}
const cl11 = function (s, n) { return String(s === undefined || s === null ? '' : s).split(String.fromCharCode(10)).join(' ').trim().slice(0, n); };
{
const tipos11 = ['habito', 'preferencia', 'fato', 'relacao'];
const mf11 = [];
(Array.isArray(out.mem_facts) ? out.mem_facts : []).forEach(function (x) {
if (!x || mf11.length >= 2) { return; }
const t11 = cl11(x.texto, 200);
if (t11.length < 4) { return; }
mf11.push({ texto: t11, tipo: tipos11.indexOf(x.tipo) >= 0 ? x.tipo : 'fato' });
});
out.mem_json = out.intent === 'memory_manage' ? '[]' : JSON.stringify(mf11);
out.offer_json = JSON.stringify({ pessoa: cl11(out.new_person, 60), rel: cl11(out.new_person_rel, 40), lugar: cl11(out.new_place, 60) });
}
if (out.intent === 'memory_manage') {
const acts11 = ['forget', 'list', 'switch_on', 'switch_off', 'offer_yes', 'offer_no'];
if (acts11.indexOf(out.mem_action) < 0) {
out.intent = 'clarify'; out.reply = out.reply || 'Quer que eu esqueça algo, mostre o que anotei ou ligue ou desligue algum recurso?';
} else {
out.mm_json = JSON.stringify({ action: out.mem_action, ref: cl11(out.mem_ref, 120), email: cl11(out.contact_email, 120), address: cl11(out.location, 200) });
}
}
if (out.intent === 'finance') {
out.fin_json = JSON.stringify({
action: out.fin_action || '', kind: out.fin_kind || 'expense', amount: out.amount === undefined ? null : out.amount,
title: out.title || '', category: out.category || '', category_stated: out.category_stated === true,
method: out.method || '', installments: out.installments || 1, paid: out.paid === false ? false : true,
date: (out.date && okDate.test(out.date)) ? out.date : '', recurring_day: out.recurring_day || null,
person: out.person || '', period: out.period || 'current', keywords: out.keywords || '',
budget_amount: out.budget_amount === undefined ? null : out.budget_amount, closing_day: out.closing_day || null,
card: out.card || '', card_closing_day: out.card_closing_day || null, card_due_day: out.card_due_day || null, card_limit: out.card_limit === undefined ? null : out.card_limit, month: out.month || '', alert_days: out.alert_days || null, report_format: out.report_format || '',
items: Array.isArray(out.fin_items) ? out.fin_items.filter(function (x) { return x && Number(x.amount) > 0; }) : [],
source: (u.kind === 'photo' || u.kind === 'document') ? 'photo' : (ctx.via_audio ? 'audio' : 'text'), reply: out.reply || ''
});
}
return [{ json: out }];`},"position":[3584,2032]}});
const n21 = switchCase({type:"n8n-nodes-base.switch",version:3.4,config:{"name":"Roteador de intencao","parameters":{"mode":"expression","numberOutputs":29,"output":expr("{{ ({\"create_reminder\":0,\"create_event\":1,\"list_agenda\":2,\"create_supply\":3,\"supply_bought\":4,\"supply_adjust\":5,\"set_preference\":6,\"provide_time\":7,\"supply_taken\":9,\"supply_schedule\":10,\"finance\":11,\"manage_event\":12,\"link_reminder\":13,\"misc_query\":14,\"cancel_reminder\":15,\"contact_manage\":16,\"invite_event\":17,\"document_manage\":18,\"list_manage\":19,\"note_manage\":20,\"project_manage\":21,\"ai_cost\":22,\"research\":23,\"agenda_import\":24,\"agenda_import_edit\":25,\"correct_recent\":26,\"memory_manage\":27})[$json.intent] !== undefined ? ({\"create_reminder\":0,\"create_event\":1,\"list_agenda\":2,\"create_supply\":3,\"supply_bought\":4,\"supply_adjust\":5,\"set_preference\":6,\"provide_time\":7,\"supply_taken\":9,\"supply_schedule\":10,\"finance\":11,\"manage_event\":12,\"link_reminder\":13,\"misc_query\":14,\"cancel_reminder\":15,\"contact_manage\":16,\"invite_event\":17,\"document_manage\":18,\"list_manage\":19,\"note_manage\":20,\"project_manage\":21,\"ai_cost\":22,\"research\":23,\"agenda_import\":24,\"agenda_import_edit\":25,\"correct_recent\":26,\"memory_manage\":27})[$json.intent] : ($json.task_action ? 8 : 28) }}")},"position":[3808,1872]}});
const n22 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Criar lembrete","parameters":{"operation":"executeQuery","query":"SELECT agente.f_reminder_create_ex($1::bigint,$2::text,$3::timestamptz,$4::boolean,NULLIF($5::text,'')::int,$6::text,$7::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.title, $('Interpretar resposta').first().json.due_iso, $('Interpretar resposta').first().json.shared, $('Interpretar resposta').first().json.lead_str, $('Interpretar resposta').first().json.source, ($('Interpretar resposta').first().json.repeat_json || '{}') ] }}")}},"credentials":CP,"position":[4480,448]}});
const n23 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Resposta do lembrete","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
let text = '';
let kb = 'none';
if (r.duplicate) {
text = 'Já tinha esse lembrete: "' + a.title + '" - ' + a.due_label + '.';
} else {
text = 'Lembrete criado: "' + a.title + '" - ' + a.due_label + (a.shared ? ' (para voces dois)' : '') + '.' + (r.repeat_text ? ' Repete ' + r.repeat_text + '.' : '');
const lm = Number(a.lead_str || 0);
if (lm > 0) {
const lab = (lm >= 1440 && lm % 1440 === 0) ? (lm / 1440) + ' dia(s)' : ((lm >= 60 && lm % 60 === 0) ? (lm / 60) + 'h' : lm + ' min');
text += ' Aviso ' + lab + ' antes.';
}
if (r.ask_lead) { text += String.fromCharCode(10) + 'Quer que eu te lembre antes? (Dica: diga "sempre me avise 30 min antes" e eu nao pergunto mais.)'; kb = 'lead'; }
}
return [{ json: { chat_id: a.chat_id, text: text, kb: kb, rid: r.reminder_id || 0, state: '' } }];`},"position":[4704,448]}});
const n24 = switchCase({type:"n8n-nodes-base.switch",version:3.4,config:{"name":"Qual calendario? (criar)","parameters":{"mode":"rules","rules":{"values":[{"outputKey":"adrian","renameOutput":true,"conditions":{"options":O1,"conditions":[{"leftValue":expr("{{ $json.calendar_key }}"),"operator":OE,"rightValue":"adrian"}],"combinator":"and"}},{"outputKey":"maria","renameOutput":true,"conditions":{"options":O1,"conditions":[{"leftValue":expr("{{ $json.calendar_key }}"),"operator":OE,"rightValue":"maria"}],"combinator":"and"}}]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"sem calendario"}},"position":[4032,784]}});
const n25 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Agenda Adrian - criar evento","parameters":{"source":"database","mode":"once","workflowId":{"__rl":true,"mode":"id","value":"bBJo78YVQ1cOMX09"},"workflowInputs":{"mappingMode":"defineBelow","value":{"action":"create","summary":expr("{{ $('Interpretar resposta').first().json.title }}"),"start":expr("{{ $('Interpretar resposta').first().json.due_iso }}"),"end":expr("{{ $('Interpretar resposta').first().json.end_iso }}"),"location":expr("{{ $('Interpretar resposta').first().json.location || '' }}"),"attendees":expr("{{ $('Interpretar resposta').first().json.attendees_csv || '' }}"),"send_updates":"all","force":"false","meet":"false","repeat_freq":expr("{{ $('Interpretar resposta').first().json.rp_freq || '' }}"),"repeat_until":expr("{{ $('Interpretar resposta').first().json.rp_until || '' }}"),"repeat_count":expr("{{ $('Interpretar resposta').first().json.rp_count || '' }}")}}},"position":[4256,608]}});
const n26 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Agenda Maria Clara - criar evento","parameters":{"source":"database","mode":"once","workflowId":{"__rl":true,"mode":"id","value":"6bXuicjujajBuXbd"},"workflowInputs":{"mappingMode":"defineBelow","value":{"action":"create","summary":expr("{{ $('Interpretar resposta').first().json.title }}"),"start":expr("{{ $('Interpretar resposta').first().json.due_iso }}"),"end":expr("{{ $('Interpretar resposta').first().json.end_iso }}"),"location":expr("{{ $('Interpretar resposta').first().json.location || '' }}"),"attendees":expr("{{ $('Interpretar resposta').first().json.attendees_csv || '' }}"),"send_updates":"all","force":"false","meet":"false","repeat_freq":expr("{{ $('Interpretar resposta').first().json.rp_freq || '' }}"),"repeat_until":expr("{{ $('Interpretar resposta').first().json.rp_until || '' }}"),"repeat_count":expr("{{ $('Interpretar resposta').first().json.rp_count || '' }}")}}},"position":[4256,800]}});
const n27 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Calendario nao conectado","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
return [{ json: { chat_id: a.chat_id, text: 'Seu Google Calendar ainda nao esta conectado ao agente. Por enquanto posso criar lembretes, que eu aviso por aqui.', kb: 'none', rid: 0, state: '' } }];`},"position":[4704,976]}});
const n28 = switchCase({type:"n8n-nodes-base.switch",version:3.4,config:{"name":"Qual calendario? (consulta)","parameters":{"mode":"rules","rules":{"values":[{"outputKey":"adrian","renameOutput":true,"conditions":{"options":O1,"conditions":[{"leftValue":expr("{{ $json.calendar_key }}"),"operator":OE,"rightValue":"adrian"}],"combinator":"and"}},{"outputKey":"maria","renameOutput":true,"conditions":{"options":O1,"conditions":[{"leftValue":expr("{{ $json.calendar_key }}"),"operator":OE,"rightValue":"maria"}],"combinator":"and"}}]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"sem calendario"}},"position":[4032,1264]}});
const n29 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Agenda Adrian - listar","parameters":{"source":"database","mode":"once","workflowId":{"__rl":true,"mode":"id","value":"bBJo78YVQ1cOMX09"},"workflowInputs":{"mappingMode":"defineBelow","value":{"action":"list","timeMin":expr("{{ $('Interpretar resposta').first().json.time_min }}"),"timeMax":expr("{{ $('Interpretar resposta').first().json.time_max }}")}}},"position":[4256,1120]}});
const n30 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Lembretes do periodo","parameters":{"operation":"executeQuery","query":"SELECT agente.f_agenda_db($1::bigint,$2::timestamptz,$3::timestamptz) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.time_min, $('Interpretar resposta').first().json.time_max ] }}")}},"credentials":CP,"position":[4480,1280]}});
const n31 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Agenda Maria Clara - listar","parameters":{"source":"database","mode":"once","workflowId":{"__rl":true,"mode":"id","value":"6bXuicjujajBuXbd"},"workflowInputs":{"mappingMode":"defineBelow","value":{"action":"list","timeMin":expr("{{ $('Interpretar resposta').first().json.time_min }}"),"timeMax":expr("{{ $('Interpretar resposta').first().json.time_max }}")}}},"position":[4256,1312]}});
const n32 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Criar estoque","parameters":{"operation":"executeQuery","query":"SELECT agente.f_create_supply($1::bigint,$2::text,NULLIF($3::text,'')::int,NULLIF($4::text,'')::numeric,NULLIF($5::text,'')::date,NULLIF($6::text,'')::int,NULLIF($7::text,''),NULLIF($8::text,'')::time,NULLIF($9::text,'')::int) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.item || '', $('Interpretar resposta').first().json.units_total === undefined ? '' : String($('Interpretar resposta').first().json.units_total), $('Interpretar resposta').first().json.units_per_day === undefined ? '' : String($('Interpretar resposta').first().json.units_per_day), $('Interpretar resposta').first().json.started_on || '', $('Interpretar resposta').first().json.alert_days === undefined ? '' : String($('Interpretar resposta').first().json.alert_days), $('Interpretar resposta').first().json.item_kind, $('Interpretar resposta').first().json.take_time, $('Interpretar resposta').first().json.units_left === undefined ? '' : String($('Interpretar resposta').first().json.units_left) ] }}")}},"credentials":CP,"position":[4480,1584]}});
const n33 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Resposta do estoque novo","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
const NL = String.fromCharCode(10);
let text = 'Anotado: ' + r.item + (r.kind === 'remedio' ? ' (remedio)' : '') + '.';
let state = '';
if (r.take_time) { text += NL + 'Lembro de tomar todo dia as ' + r.take_time + ' e repito a cada 10 minutos ate voce tocar Tomei.'; }
if (r.needs_total && r.ask_total) {
text += NL + 'Quantos comprimidos tem na cartela agora? (Pode mandar uma foto.)';
state = JSON.stringify({ kind: 'clarify', original: a.transcript || a.original_text || '' });
} else if (r.needs_total) {
text += '';
} else {
text += NL + 'Restam ' + Math.round(Number(r.units_left)) + ' e acaba em ' + r.runs_out_on + '. O aviso de compra entra no resumo da manha a partir de ' + r.alert_on + '.';
if (!r.take_time) { text += NL + 'Quer lembrete na hora de tomar? Diga: me lembre de tomar ' + r.item + ' as 8h.'; }
}
return [{ json: { chat_id: a.chat_id, kb: 'none', rid: 0, state: state, text: text } }];`},"position":[4704,1584]}});
const n34 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Registrar compra","parameters":{"operation":"executeQuery","query":"SELECT agente.f_supply_bought($1::bigint,$2::text) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.item || '' ] }}")}},"credentials":CP,"position":[4480,1776]}});
const n35 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Resposta da compra","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
const text = r.found ? 'Anotado! Recomecei a contagem de ' + r.item + (r.units_total ? ': ' + r.units_total + ' unidades' : '') + '. Paro de avisar da compra.' : 'Nao achei esse item. Me diga o nome, por exemplo: comprei a losartana.';
return [{ json: { chat_id: a.chat_id, text: text, kb: 'none', rid: 0, state: '' } }];`},"position":[4704,1776]}});
const n36 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Ajustar estoque","parameters":{"operation":"executeQuery","query":"SELECT agente.f_supply_manage($1::bigint,$2::text,NULLIF($3::text,'')::int,NULLIF($4::text,'')::int,NULLIF($5::text,''),NULLIF($6::text,'')) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.item || '', $('Interpretar resposta').first().json.units_left === undefined ? '' : String($('Interpretar resposta').first().json.units_left), $('Interpretar resposta').first().json.pause_days === undefined ? '' : String($('Interpretar resposta').first().json.pause_days), $('Interpretar resposta').first().json.supply_action || '', $('Interpretar resposta').first().json.new_name || '' ] }}")}},"credentials":CP,"position":[4480,1968]}});
const n37 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Resposta do ajuste","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
let text = '';
let kb = 'none';
let rid = 0;
if (r.action === 'rename') {
if (r.need_name) { text = 'Qual o novo nome do remedio?'; }
else if (!r.found) { text = 'Nao achei um item para renomear. Se quiser cadastrar, diga: me lembre de tomar NOME todo dia as 8h.'; }
else if (r.conflict) { text = 'Ja existe um item chamado ' + r.item + '. Quer apagar o outro?'; }
else { text = 'Pronto: ' + r.old_item + ' agora se chama ' + r.item + (r.take_time ? ' (lembrete diario as ' + r.take_time + ' mantido)' : '') + '.'; }
} else if (r.action === 'delete') {
if (!r.found) { text = 'Nao achei esse remedio. Me diga o nome, por exemplo: apaga o remedio sertralina.'; }
else { text = 'Apagar ' + r.item + (r.take_time ? ' e o lembrete de tomar as ' + r.take_time : '') + '?'; kb = 'sup_del'; rid = r.sid || 0; }
} else {
text = r.found ? 'Ajustado: ' + r.item + ' - restam ' + Math.round(Number(r.units_left)) + ', acaba em ' + r.runs_out_on + ' (aviso em ' + r.alert_on + ').' : 'Nao achei esse item. Me diga o nome, por exemplo: tenho 12 na cartela de losartana.';
}
return [{ json: { chat_id: a.chat_id, text: text, kb: kb, rid: rid, state: '' } }];`},"position":[4704,1968]}});
const n38 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Salvar preferencias","parameters":{"operation":"executeQuery","query":"SELECT agente.f_set_prefs($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, JSON.stringify({ lead: $('Interpretar resposta').first().json.pref_lead_minutes, summary: $('Interpretar resposta').first().json.pref_morning === 'off' ? 'off' : ($('Interpretar resposta').first().json.pref_summary_time || ($('Interpretar resposta').first().json.pref_morning === 'on' ? 'on' : null)), supply_days: $('Interpretar resposta').first().json.pref_supply_days, nickname: $('Interpretar resposta').first().json.pref_nickname, no_emoji: $('Interpretar resposta').first().json.pref_no_emoji, timezone: $('Interpretar resposta').first().json.pref_timezone, evening: $('Interpretar resposta').first().json.pref_evening, work_start: $('Interpretar resposta').first().json.pref_work_start, work_end: $('Interpretar resposta').first().json.pref_work_end }) ] }}")}},"credentials":CP,"position":[4480,2160]}});
const n39 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Resposta das preferencias","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
return [{ json: { chat_id: a.chat_id, kb: 'none', rid: 0, state: '', text: r.text || 'Nao consegui salvar agora. Tente de novo.' } }];`},"position":[4704,2160]}});
const n40 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Remarcar lembrete","parameters":{"operation":"executeQuery","query":"SELECT agente.f_provide_time($1::bigint,$2::bigint,$3::timestamptz) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.rid, $('Interpretar resposta').first().json.due_iso ] }}")}},"credentials":CP,"position":[4480,2352]}});
const n41 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Resposta do novo horario","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
return [{ json: { chat_id: a.chat_id, text: r.text || 'Ok.', kb: r.kb || 'none', rid: 0, state: '' } }];`},"position":[4704,2352]}});
const n42 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Google Tasks","parameters":{"source":"database","mode":"once","workflowId":{"__rl":true,"mode":"id","value":"dnVm8cfVhpqXGWmr"},"workflowInputs":{"mappingMode":"defineBelow","value":{"calendar_key":expr("{{ $('Interpretar resposta').first().json.calendar_key }}"),"action":expr("{{ $('Interpretar resposta').first().json.task_action }}"),"title":expr("{{ $('Interpretar resposta').first().json.title }}"),"due":expr("{{ $('Interpretar resposta').first().json.task_due }}")}}},"position":[4480,2544]}});
const n43 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Resposta das tarefas","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json || {};
const NL = String.fromCharCode(10);
let text = '';
if (r.not_connected) {
text = 'Suas tarefas do Google ainda nao estao conectadas ao agente.';
} else if (a.intent === 'create_task') {
text = 'Anotei na sua lista de tarefas: "' + (r.title || a.title) + '"' + (a.task_due ? ' (prazo ' + a.task_due.slice(8, 10) + '/' + a.task_due.slice(5, 7) + ')' : '') + '.';
} else if (a.intent === 'list_tasks') {
const tarefas = r.tasks || [];
text = tarefas.length ? 'Suas tarefas pendentes:' + NL + tarefas.map(function (t) { return '- ' + t.title + (t.due ? ' (prazo ' + t.due.slice(8, 10) + '/' + t.due.slice(5, 7) + ')' : ''); }).join(NL) : 'Voce nao tem tarefas pendentes.';
} else if (r.not_found) {
text = 'Nao achei uma tarefa pendente parecida com "' + (r.title || a.title) + '". Diga "o que tenho nas tarefas?" para ver a lista.';
} else {
text = 'Tarefa concluida: ' + (r.title || a.title) + '.';
}
return [{ json: { chat_id: a.chat_id, text: text, kb: 'none', rid: 0, state: '' } }];`},"position":[4704,2544]}});
const n44 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Registrar dose tomada","parameters":{"operation":"executeQuery","query":"SELECT agente.f_supply_taken($1::bigint,$2::text) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.item || '' ] }}")}},"credentials":CP,"position":[4480,2736]}});
const n45 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Resposta da dose","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
let text = '';
if (!r.found) { text = 'Nao achei esse item. Para cadastrar e ja ligar o lembrete, diga: me lembre de tomar losartana todo dia as 8h.'; }
else if (!r.tracking) { text = 'Anotei. Mas ' + r.item + ' ainda nao tem lembrete de tomar, entao a contagem segue por dias. Para eu controlar cada dose, diga: me lembre de tomar ' + r.item + ' as 8h.'; }
else if (r.units_left === null || r.units_left === undefined) { text = 'Anotado: tomou ' + r.item + '. Quantos comprimidos tem na cartela agora? Assim eu aviso quando for comprar.'; }
else { text = 'Anotado: tomou ' + r.item + '. Restam ' + Math.round(Number(r.units_left)) + ' (acaba em ' + r.runs_out_on + ').'; }
return [{ json: { chat_id: a.chat_id, text: text, kb: 'none', rid: 0, state: '' } }];`},"position":[4704,2736]}});
const n46 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Agendar lembrete de tomar","parameters":{"operation":"executeQuery","query":"SELECT agente.f_supply_schedule($1::bigint,$2::text,NULLIF($3::text,''),$4::boolean,NULLIF($5::text,'')) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.item || '', $('Interpretar resposta').first().json.take_time || '', $('Interpretar resposta').first().json.stop_reminder === true, $('Interpretar resposta').first().json.item_kind || '' ] }}")}},"credentials":CP,"position":[4480,2928]}});
const n47 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Resposta do horario de tomar","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
const NL = String.fromCharCode(10);
let text = '';
let state = '';
if (!r.found) { text = 'Nao achei esse item para parar o lembrete. Me diga o nome.'; }
else if (r.cleared) { text = 'Parei os lembretes de tomar ' + r.item + '. A contagem volta a seguir por dias.'; }
else {
text = 'Anotado: ' + r.item + (r.kind === 'remedio' ? ' (remedio)' : '') + '. Lembro de tomar todo dia as ' + r.take_time + ' e repito a cada 10 minutos ate voce tocar Tomei.';
if (r.needs_total && r.ask_total) {
text += NL + 'Quantos comprimidos tem na cartela agora? (Pode mandar uma foto.) Assim eu aviso quando for comprar.';
state = JSON.stringify({ kind: 'clarify', original: a.transcript || a.original_text || '' });
} else if (r.needs_total) {
text += '';
} else {
text += NL + 'Restam ' + Math.round(Number(r.units_left)) + ' e acaba em ' + r.runs_out_on + '.';
}
}
return [{ json: { chat_id: a.chat_id, text: text, kb: 'none', rid: 0, state: state } }];`},"position":[4704,2928]}});
const n48 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Resposta direta","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const u = $('Normalizar update').first().json;
let state = '';
if (a.intent === 'clarify') { state = JSON.stringify({ kind: 'clarify', original: a.transcript || u.text || '' }); }
return [{ json: { chat_id: a.chat_id, text: a.reply || 'Nao entendi. Pode explicar de outro jeito? (/ajuda)', kb: 'none', rid: 0, state: state } }];`},"position":[4704,3120]}});
const n49 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Resposta da agenda","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || { reminders: [], supplies: [] };
const NL = String.fromCharCode(10);
let eventos = [];
try { eventos = $('Agenda Adrian - listar').first().json.events || []; } catch (e) { eventos = []; }
if (!eventos.length) { try { eventos = $('Agenda Maria Clara - listar').first().json.events || []; } catch (e) { eventos = []; } }
const tz = a.tz;
const linhas = [];
eventos.forEach(function (e) {
const quando = e.all_day ? 'dia todo' : DateTime.fromISO(e.start, { zone: tz }).toFormat('dd/MM HH:mm');
linhas.push('- ' + quando + '  ' + e.title + (e.location ? ' (' + e.location + ')' : ''));
});
const lembretes = (r.reminders || []).map(function (x) { return '- ' + x.due + '  ' + x.title; });
const estoque = (r.supplies || []).map(function (s) { return '- ' + s.item + ': restam ' + Math.round(Number(s.units_left)) + ', acaba em ' + s.runs_out_on; });
const partes = ['Sua agenda (' + a.range_label + '):'];
partes.push(linhas.length ? 'Compromissos:' + NL + linhas.join(NL) : 'Compromissos: nenhum.');
partes.push(lembretes.length ? 'Lembretes:' + NL + lembretes.join(NL) : 'Lembretes: nenhum.');
if (estoque.length) { partes.push('Hora de comprar (diga "comprei" quando comprar):' + NL + estoque.join(NL)); }
return [{ json: { chat_id: a.chat_id, text: partes.join(NL + NL), kb: 'none', rid: 0, state: '' } }];`},"position":[4704,1280]}});
const n50 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Montar historico","parameters":{...K6,"jsCode":`const p = $('Preparar envio').first().json;
const u = $('Normalizar update').first().json;
let hist = [];
try { const raw = $('Ler historico da conversa').first().json.hist; hist = raw ? JSON.parse(raw) : []; } catch (e) { hist = []; }
const agoraMs = Date.now();
hist = hist.filter(function (h) { return h && h.t && (agoraMs - h.ts) < 6 * 3600 * 1000; });
let falhou = false;
let agendado = '';
try {
const ia = $('Interpretar resposta').first().json;
falhou = ia.llm_error === true;
if (ia.due_iso && (ia.intent === 'create_reminder' || ia.intent === 'create_event' || ia.intent === 'provide_time')) {
agendado = ' [agendado: ' + String(ia.due_iso).slice(0, 10) + ' ' + String(ia.due_iso).slice(11, 16) + ']';
}
} catch (e) { falhou = false; }
if ((u.kind === 'text' || u.kind === 'voice' || u.kind === 'photo' || u.kind === 'document' || u.kind === 'file') && !falhou) {
let userText = u.text || '';
try { const a = $('Interpretar resposta').first().json; if (a.transcript) { userText = a.transcript; } } catch (e) {}
if (u.kind === 'photo') { userText = '[foto] ' + userText; }
if (u.kind === 'document') { userText = '[arquivo] ' + userText; }
if (u.kind === 'file') { userText = '[arquivo ' + (u.file_name || '') + '] ' + userText; }
if (userText) {
hist.push({ r: 'user', t: String(userText).slice(0, 600), ts: agoraMs });
hist.push({ r: 'model', t: String(p.text || '').slice(0, 560) + agendado, ts: agoraMs });
}
}
hist = hist.slice(-40);
return [{ json: { chat_id: p.chat_id, hist: JSON.stringify(hist) } }];`},"position":[5152,1776]}});
const n51 = node({type:"n8n-nodes-base.redis",version:1,config:{"name":"Guardar historico","parameters":{"operation":"set","key":expr("agente:hist:{{ $('Buscar usuario').first().json.id }}"),"value":expr("{{ $json.hist }}"),"keyType":"string"},"credentials":CR,"position":[5376,1776]}});
const n52 = ifElse({type:"n8n-nodes-base.if",version:2.3,config:{"name":"Guardar estado?","parameters":{"conditions":{"options":O2,"conditions":[{"leftValue":expr("{{ $('Preparar envio').first().json.state }}"),"operator":{"type":"string","operation":"notEmpty","singleValue":true},"rightValue":""}],"combinator":"and"}},"position":[5600,1776]}});
const n53 = node({type:"n8n-nodes-base.redis",version:1,config:{"name":"Guardar estado","parameters":{"operation":"set","key":expr("agente:state:{{ $('Buscar usuario').first().json.id }}"),"value":expr("{{ $('Preparar envio').first().json.state }}"),"keyType":"string"},"credentials":CR,"position":[5824,1696]}});
const n54 = switchCase({type:"n8n-nodes-base.switch",version:3.4,config:{"name":"Qual teclado?","parameters":{"mode":"expression","numberOutputs":28,"output":expr("{{ ({\"lead\":0,\"snooze\":1,\"summary_time\":2,\"fin_undo\":3,\"fin_confirm\":4,\"fin_delete\":5,\"ag_confirm\":6,\"ag_pick2\":7,\"ag_pick3\":8,\"ag_scope\":9,\"ag_conflict\":10,\"ag_invite\":11,\"ex_card_del\":12,\"ct_confirm\":13,\"dc_del\":14,\"dc_fdel\":15,\"ls_confirm\":16,\"pj_tasks\":17,\"pj_del\":18,\"menu\":19,\"place_ask\":20,\"sup_del\":21,\"fin_recibo\":22,\"agimp\":23,\"multi_undo\":24,\"menu_area\":25,\"menu_mais\":26})[$('Preparar envio').first().json.kb] !== undefined ? ({\"lead\":0,\"snooze\":1,\"summary_time\":2,\"fin_undo\":3,\"fin_confirm\":4,\"fin_delete\":5,\"ag_confirm\":6,\"ag_pick2\":7,\"ag_pick3\":8,\"ag_scope\":9,\"ag_conflict\":10,\"ag_invite\":11,\"ex_card_del\":12,\"ct_confirm\":13,\"dc_del\":14,\"dc_fdel\":15,\"ls_confirm\":16,\"pj_tasks\":17,\"pj_del\":18,\"menu\":19,\"place_ask\":20,\"sup_del\":21,\"fin_recibo\":22,\"agimp\":23,\"multi_undo\":24,\"menu_area\":25,\"menu_mais\":26})[$('Preparar envio').first().json.kb] : 27 }}")},"position":[6048,1744]}});
const n55 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com aviso antes","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Nao","additionalFields":{"callback_data":expr("lead:{{ $('Preparar envio').first().json.rid }}:0")}},{"text":"15 min","additionalFields":{"callback_data":expr("lead:{{ $('Preparar envio').first().json.rid }}:15")}},{"text":"1 hora","additionalFields":{"callback_data":expr("lead:{{ $('Preparar envio').first().json.rid }}:60")}},{"text":"1 dia","additionalFields":{"callback_data":expr("lead:{{ $('Preparar envio').first().json.rid }}:1440")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,1488]}});
const n56 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com opcoes de adiar","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Mesmo horario","additionalFields":{"callback_data":expr("snzs:{{ $('Preparar envio').first().json.rid }}")}},{"text":"Outro horario","additionalFields":{"callback_data":expr("snzo:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,1680]}});
const n57 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com hora do resumo","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"07:00","additionalFields":{"callback_data":"sum:07:00"}},{"text":"07:30","additionalFields":{"callback_data":"sum:07:30"}},{"text":"08:00","additionalFields":{"callback_data":"sum:08:00"}},{"text":"09:00","additionalFields":{"callback_data":"sum:09:00"}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,1872]}});
const n58 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar texto","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,2064]}});
const n59 = ifElse({type:"n8n-nodes-base.if",version:2.2,config:{"name":"E audio?","parameters":{"conditions":{"options":O2,"conditions":[{...K4,"operator":OE,"rightValue":"voice"}],"combinator":"and"}},"position":[900,500]}});
const n60 = node({type:"@n8n/n8n-nodes-langchain.openAi",version:2.3,config:{"name":"Transcrever audio","parameters":{"resource":"audio","operation":"transcribe","binaryPropertyName":"data","options":{"language":"pt"}},"credentials":CO,"position":[1100,500],"onError":"continueRegularOutput"}});
const n61 = ifElse({type:"n8n-nodes-base.if",version:2.2,config:{"name":"Tem foto?","parameters":{"conditions":{"options":O2,"conditions":[{"leftValue":expr("{{ $('Montar pedido a IA').first().json.via_photo }}"),"operator":{"type":"boolean","operation":"true","singleValue":true},"rightValue":""}],"combinator":"and"}},"position":[2200,500]}});
const n62 = node({type:"@n8n/n8n-nodes-langchain.openAi",version:2.3,config:{"name":"OpenAI interpreta texto","parameters":{"resource":"text","operation":"response","modelId":{"__rl":true,"mode":"id","value":expr("{{ $('Montar pedido a IA').first().json.modelo }}")},"responses":{"values":[{"type":"text","role":"user","content":expr("{{ $('Montar pedido a IA').first().json.prompt }}")}]},"simplify":false,"options":{"instructions":expr("{{ $('Montar pedido a IA').first().json.instrucoes }}"),"maxTokens":1500,"store":false,"textFormat":{"textOptions":{"type":"json_schema","name":"interpretacao","schema":expr("{{ $('Montar pedido a IA').first().json.schema_json }}"),"strict":true}}}},"credentials":CO,"position":[2450,560],...K5,"retryOnFail":true}});
const n63 = node({type:"@n8n/n8n-nodes-langchain.openAi",version:2.3,config:{"name":"OpenAI interpreta foto","parameters":{"resource":"text","operation":"response","modelId":{"__rl":true,"mode":"id","value":expr("{{ $('Montar pedido a IA').first().json.modelo }}")},"responses":{"values":[{"type":"text","role":"user","content":expr("{{ $('Montar pedido a IA').first().json.prompt }}")},{"type":"image","role":"user","imageType":"url","imageUrl":expr("{{ $('Montar pedido a IA').first().json.image_url }}"),"imageDetail":"auto"}]},"simplify":false,"options":{"instructions":expr("{{ $('Montar pedido a IA').first().json.instrucoes }}"),"maxTokens":1500,"store":false,"textFormat":{"textOptions":{"type":"json_schema","name":"interpretacao","schema":expr("{{ $('Montar pedido a IA').first().json.schema_json }}"),"strict":true}}}},"credentials":CO,"position":[2450,420],...K5,"retryOnFail":true}});
const n64 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Executar financas","parameters":{"operation":"executeQuery","query":"SELECT agente.f_fin($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.fin_json ] }}")}},"credentials":CP,"position":[4480,3312]}});
const n65 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Resposta das financas","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
return [{ json: { chat_id: a.chat_id, text: r.text || 'Nao consegui registrar agora. Tente de novo.', kb: r.kb || 'none', rid: r.rid || 0, state: '' } }];`},"position":[4704,3312]}});
const n66 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com desfazer","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Desfazer","additionalFields":{"callback_data":expr("fundo:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,2256]}});
const n67 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com confirmar","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Confirmar","additionalFields":{"callback_data":expr("fok:{{ $('Preparar envio').first().json.rid }}")}},{"text":"Cancelar","additionalFields":{"callback_data":expr("fno:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,2448]}});
const n68 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com apagar","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Sim, apagar","additionalFields":{"callback_data":expr("fdel:{{ $('Preparar envio').first().json.rid }}")}},{"text":"Nao","additionalFields":{"callback_data":expr("fkeep:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,2640]}});
const n69 = ifElse({type:"n8n-nodes-base.if",version:2.2,config:{"name":"Tem PDF?","parameters":{"conditions":{"options":O2,"conditions":[{"leftValue":expr("{{ $('Montar pedido a IA').first().json.via_pdf }}"),"operator":{"type":"boolean","operation":"true","singleValue":true},"rightValue":""}],"combinator":"and"}},"position":[2200,700]}});
const n70 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Preparar PDF","parameters":{...K6,"jsCode":`const m = $('Montar pedido a IA').first().json;
const bin = await this.helpers.prepareBinaryData(Buffer.from(String(m.file_b64), 'base64'), m.file_name || 'documento.pdf', 'application/pdf');
return [{ json: { ok: true }, binary: { data: bin } }];`},"position":[2450,800]}});
const n71 = node({type:"@n8n/n8n-nodes-langchain.openAi",version:2.3,config:{"name":"OpenAI interpreta PDF","parameters":{"resource":"text","operation":"response","modelId":{"__rl":true,"mode":"id","value":expr("{{ $('Montar pedido a IA').first().json.modelo }}")},"responses":{"values":[{"type":"text","role":"user","content":expr("{{ $('Montar pedido a IA').first().json.prompt }}")},{"type":"file","role":"user","fileType":"base64","binaryPropertyName":"data","fileName":expr("{{ $('Montar pedido a IA').first().json.file_name }}")}]},"simplify":false,"options":{"instructions":expr("{{ $('Montar pedido a IA').first().json.instrucoes }}"),"maxTokens":1500,"store":false,"textFormat":{"textOptions":{"type":"json_schema","name":"interpretacao","schema":expr("{{ $('Montar pedido a IA').first().json.schema_json }}"),"strict":true}}}},"credentials":CO,"position":[2700,800],...K5,"retryOnFail":true}});
const n72 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Agenda: concluir criacao","parameters":{"operation":"executeQuery","query":"SELECT agente.f_agenda_after_create($1::bigint, $2::jsonb, $3::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, JSON.stringify({ title: $('Interpretar resposta').first().json.title, due_iso: $('Interpretar resposta').first().json.due_iso, end_iso: $('Interpretar resposta').first().json.end_iso, location: $('Interpretar resposta').first().json.location || '', lead_str: $('Interpretar resposta').first().json.lead_str, source: $('Interpretar resposta').first().json.source, calendar_key: $('Interpretar resposta').first().json.calendar_key, repeat_freq: $('Interpretar resposta').first().json.rp_freq || '', repeat_until: $('Interpretar resposta').first().json.rp_until || '', repeat_count: $('Interpretar resposta').first().json.rp_count || '', attendees: $('Interpretar resposta').first().json.attendees_csv || '', meet: 'false' }), JSON.stringify($input.first().json) ] }}")}},"credentials":CP,"position":[4480,3600]}});
const n73 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Agenda: resposta da criacao","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
return [{ json: { chat_id: a.chat_id, text: r.text || 'Nao consegui registrar o compromisso agora. Tente de novo.', kb: r.kb || 'none', rid: r.rid || 0, state: r.state || '' } }];`},"position":[4704,3600]}});
const n74 = ifElse({type:"n8n-nodes-base.if",version:2.2,config:{"name":"Agenda: gerir?","parameters":{"conditions":{"options":O2,"conditions":[{"leftValue":expr("{{ $('Interpretar resposta').first().json.intent }}"),"operator":OE,"rightValue":"manage_event"}],"combinator":"and"}},"position":[4260,3900]}});
const n75 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Agenda: gerir agenda","parameters":{"operation":"executeQuery","query":"SELECT agente.f_agenda_manage($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, JSON.stringify(Object.assign({}, $('Interpretar resposta').first().json.mg || {}, { ok: $input.first().json.ok, error: $input.first().json.error, events: $input.first().json.events || [] })) ] }}")}},"credentials":CP,"position":[4480,3800]}});
const n76 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Agenda: resposta da gestao","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
return [{ json: { chat_id: a.chat_id, text: r.text || 'Nao consegui mexer na agenda agora. Tente de novo.', kb: r.kb || 'none', rid: r.rid || 0, state: r.state || '' } }];`},"position":[4704,3800]}});
const n77 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Agenda: ligar lembrete","parameters":{"operation":"executeQuery","query":"SELECT agente.f_reminder_link($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.lr_json ] }}")}},"credentials":CP,"position":[4480,4000]}});
const n78 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Agenda: resposta do lembrete ligado","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
return [{ json: { chat_id: a.chat_id, text: r.text || 'Nao consegui ligar o lembrete agora. Tente de novo.', kb: r.kb || 'none', rid: r.rid || 0, state: r.state || '' } }];`},"position":[4704,4000]}});
const n79 = ifElse({type:"n8n-nodes-base.if",version:2.2,config:{"name":"Agenda: acao externa?","parameters":{"conditions":{"options":O2,"conditions":[{"leftValue":expr("{{ !!($json.r && $json.r.cal) }}"),"operator":{"type":"boolean","operation":"true","singleValue":true},"rightValue":""}],"combinator":"and"}},"position":[900,3500]}});
const n80 = switchCase({type:"n8n-nodes-base.switch",version:3.4,config:{"name":"Agenda: qual calendario (acao)","parameters":{"mode":"rules","rules":{"values":[{"outputKey":"adrian","renameOutput":true,"conditions":{"options":O1,"conditions":[{"leftValue":expr("{{ $json.r.cal.calendar_key }}"),"operator":OE,"rightValue":"adrian"}],"combinator":"and"}},{"outputKey":"maria","renameOutput":true,"conditions":{"options":O1,"conditions":[{"leftValue":expr("{{ $json.r.cal.calendar_key }}"),"operator":OE,"rightValue":"maria"}],"combinator":"and"}}]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"sem calendario"}},"position":[1100,3500]}});
const n81 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Agenda Adrian - executar acao","parameters":{"source":"database","mode":"once","workflowId":{"__rl":true,"mode":"id","value":"bBJo78YVQ1cOMX09"},"workflowInputs":{"mappingMode":"defineBelow","value":{"action":expr("{{ $('Executar botao').first().json.r.cal.op }}"),"summary":expr("{{ $('Executar botao').first().json.r.cal.summary || '' }}"),"start":expr("{{ $('Executar botao').first().json.r.cal.start || '' }}"),"end":expr("{{ $('Executar botao').first().json.r.cal.end || '' }}"),"location":expr("{{ $('Executar botao').first().json.r.cal.location || '' }}"),"attendees":expr("{{ $('Executar botao').first().json.r.cal.attendees || '' }}"),"event_id":expr("{{ $('Executar botao').first().json.r.cal.event_id || '' }}"),"send_updates":expr("{{ $('Executar botao').first().json.r.cal.send_updates || '' }}"),"force":expr("{{ $('Executar botao').first().json.r.cal.force || '' }}"),"meet":expr("{{ $('Executar botao').first().json.r.cal.meet || '' }}"),"repeat_freq":expr("{{ $('Executar botao').first().json.r.cal.repeat_freq || '' }}"),"repeat_until":expr("{{ $('Executar botao').first().json.r.cal.repeat_until || '' }}"),"repeat_count":expr("{{ $('Executar botao').first().json.r.cal.repeat_count || '' }}"),"response":expr("{{ $('Executar botao').first().json.r.cal.response || '' }}")}}},"position":[1300,3400],"onError":"continueRegularOutput"}});
const n82 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Agenda Maria Clara - executar acao","parameters":{"source":"database","mode":"once","workflowId":{"__rl":true,"mode":"id","value":"6bXuicjujajBuXbd"},"workflowInputs":{"mappingMode":"defineBelow","value":{"action":expr("{{ $('Executar botao').first().json.r.cal.op }}"),"summary":expr("{{ $('Executar botao').first().json.r.cal.summary || '' }}"),"start":expr("{{ $('Executar botao').first().json.r.cal.start || '' }}"),"end":expr("{{ $('Executar botao').first().json.r.cal.end || '' }}"),"location":expr("{{ $('Executar botao').first().json.r.cal.location || '' }}"),"attendees":expr("{{ $('Executar botao').first().json.r.cal.attendees || '' }}"),"event_id":expr("{{ $('Executar botao').first().json.r.cal.event_id || '' }}"),"send_updates":expr("{{ $('Executar botao').first().json.r.cal.send_updates || '' }}"),"force":expr("{{ $('Executar botao').first().json.r.cal.force || '' }}"),"meet":expr("{{ $('Executar botao').first().json.r.cal.meet || '' }}"),"repeat_freq":expr("{{ $('Executar botao').first().json.r.cal.repeat_freq || '' }}"),"repeat_until":expr("{{ $('Executar botao').first().json.r.cal.repeat_until || '' }}"),"repeat_count":expr("{{ $('Executar botao').first().json.r.cal.repeat_count || '' }}"),"response":expr("{{ $('Executar botao').first().json.r.cal.response || '' }}")}}},"position":[1300,3560],"onError":"continueRegularOutput"}});
const n83 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Agenda: sem calendario (acao)","parameters":{...K6,"jsCode":`const u = $('Normalizar update').first().json;
return [{ json: { chat_id: u.chat_id, text: 'Nao encontrei o calendario dessa acao. Peca de novo.', kb: 'none', rid: 0, state: '' } }];`},"position":[1300,3720]}});
const n84 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Agenda: concluir acao","parameters":{"operation":"executeQuery","query":"SELECT agente.f_agenda_done($1::bigint, $2::bigint, $3::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Buscar usuario').first().json.id, $('Executar botao').first().json.r.cal.pid, JSON.stringify($input.first().json) ] }}")}},"credentials":CP,"position":[1500,3480]}});
const n85 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Agenda: resposta da acao","parameters":{...K6,"jsCode":`const u = $('Normalizar update').first().json;
const r = $input.first().json.r || {};
return [{ json: { chat_id: u.chat_id, text: r.text || 'Nao consegui concluir agora. Confira sua agenda.', kb: r.kb || 'none', rid: r.rid || 0, state: r.state || '' } }];`},"position":[1700,3480]}});
const n86 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com ag confirm","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Confirmar","additionalFields":{"callback_data":expr("agok:{{ $('Preparar envio').first().json.rid }}")}},{"text":"Cancelar","additionalFields":{"callback_data":expr("agno:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,3984]}});
const n87 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com ag pick2","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"1","additionalFields":{"callback_data":expr("agpk:{{ $('Preparar envio').first().json.rid }}:1")}},{"text":"2","additionalFields":{"callback_data":expr("agpk:{{ $('Preparar envio').first().json.rid }}:2")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,4176]}});
const n88 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com ag pick3","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"1","additionalFields":{"callback_data":expr("agpk:{{ $('Preparar envio').first().json.rid }}:1")}},{"text":"2","additionalFields":{"callback_data":expr("agpk:{{ $('Preparar envio').first().json.rid }}:2")}},{"text":"3","additionalFields":{"callback_data":expr("agpk:{{ $('Preparar envio').first().json.rid }}:3")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,4368]}});
const n89 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com ag scope","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Só este","additionalFields":{"callback_data":expr("agsc:{{ $('Preparar envio').first().json.rid }}:1")}},{"text":"A série","additionalFields":{"callback_data":expr("agsc:{{ $('Preparar envio').first().json.rid }}:a")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,4560]}});
const n90 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com ag conflict","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Marcar mesmo assim","additionalFields":{"callback_data":expr("agfy:{{ $('Preparar envio').first().json.rid }}")}},{"text":"Outro horário","additionalFields":{"callback_data":expr("agfo:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,4752]}});
const n91 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com ag invite","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Aceitar","additionalFields":{"callback_data":expr("agrs:{{ $('Preparar envio').first().json.rid }}")}},{"text":"Recusar","additionalFields":{"callback_data":expr("agrn:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,4944]}});
const n92 = switchCase({type:"n8n-nodes-base.switch",version:3.4,config:{"name":"Extras: Qual consulta?","parameters":{"mode":"rules","rules":{"values":[{"outputKey":"tasks_closed","renameOutput":true,"conditions":{"options":O1,"conditions":[{"leftValue":expr("{{ $json.query_kind }}"),"operator":OE,"rightValue":"tasks_closed"}],"combinator":"and"}}]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"outras consultas"}},"position":[4256,3744]}});
const n93 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Extras: Tarefas fechadas","parameters":{"source":"database","mode":"once","workflowId":{"__rl":true,"mode":"id","value":"dnVm8cfVhpqXGWmr"},"workflowInputs":{"mappingMode":"defineBelow","value":{"calendar_key":expr("{{ $('Interpretar resposta').first().json.calendar_key }}"),"action":"closed","title":"","due":expr("{{ $('Interpretar resposta').first().json.closed_min }}")}}},"position":[4480,3600],"alwaysOutputData":true}});
const n94 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Extras: Resposta das tarefas","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json || {};
const NL = String.fromCharCode(10);
let text = '';
if (r.not_connected) {
text = 'Suas tarefas do Google ainda nao estao conectadas ao agente.';
} else if (!Array.isArray(r.closed)) {
text = 'Nao consegui consultar as tarefas concluidas agora. Tente de novo mais tarde.';
} else if (r.closed.length === 0) {
text = 'Nenhuma tarefa concluida desde segunda-feira.';
} else {
text = 'Voce concluiu ' + r.closed.length + ' tarefa' + (r.closed.length > 1 ? 's' : '') + ' desde segunda-feira:' + NL + r.closed.slice(0, 15).map(function (t) { return '- ' + t.title; }).join(NL);
}
return [{ json: { chat_id: a.chat_id, text: text, kb: 'none', rid: 0, state: '' } }];`},"position":[4704,3600]}});
const n95 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Extras: Consulta","parameters":{"operation":"executeQuery","query":"SELECT agente.f_misc($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.misc_json ] }}")}},"credentials":CP,"position":[4480,3792],"onError":"continueRegularOutput"}});
const n96 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Extras: Cancelar lembrete","parameters":{"operation":"executeQuery","query":"SELECT agente.f_reminder_cancel($1::bigint, $2::text) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.title ] }}")}},"credentials":CP,"position":[4480,3984],"onError":"continueRegularOutput"}});
const n97 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Extras: Resposta","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
return [{ json: { chat_id: a.chat_id, text: r.text || 'Nao consegui agora. Tente de novo.', kb: r.kb || 'none', rid: r.rid || 0, state: '' } }];`},"position":[4704,3888]}});
const n98 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com ex card del","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Sim, apagar","additionalFields":{"callback_data":expr("exdel:{{ $('Preparar envio').first().json.rid }}")}},{"text":"Nao","additionalFields":{"callback_data":expr("exkeep:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,5136]}});
const n99 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Contatos: executar","parameters":{"operation":"executeQuery","query":"SELECT agente.f_contacts($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.contact_json ] }}")}},"credentials":CP,"position":[4480,3600]}});
const n100 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Convites: preparar","parameters":{"operation":"executeQuery","query":"SELECT agente.f_invite_prepare($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.invite_json ] }}")}},"credentials":CP,"position":[4480,3792]}});
const n101 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Contatos: resposta","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
return [{ json: { chat_id: a.chat_id, text: r.text || 'Nao consegui agora. Tente de novo.', kb: r.kb || 'none', rid: r.rid || 0, state: '' } }];`},"position":[4704,3696]}});
const n102 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com ct confirm","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Confirmar","additionalFields":{"callback_data":expr("ctok:{{ $('Preparar envio').first().json.rid }}")}},{"text":"Cancelar","additionalFields":{"callback_data":expr("ctno:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,5328]}});
const n103 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Docs: registrar recebido","parameters":{"operation":"executeQuery","query":"SELECT agente.f_docs_inbox_note($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Buscar usuario').first().json.id || 0, JSON.stringify({ file_id: $('Normalizar update').first().json.file_id, tg_type: $('Normalizar update').first().json.tg_type, mime: $('Normalizar update').first().json.mime, file_name: $('Normalizar update').first().json.file_name, file_size: $('Normalizar update').first().json.file_size, caption: $('Normalizar update').first().json.text }) ] }}")}},"credentials":CP,"position":[1100,3300],...K5,"alwaysOutputData":true}});
const n104 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Docs: arquivo direto","parameters":{"operation":"executeQuery","query":"SELECT agente.f_docs_file($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Buscar usuario').first().json.id || 0, JSON.stringify({ file_id: $('Normalizar update').first().json.file_id, tg_type: $('Normalizar update').first().json.tg_type, mime: $('Normalizar update').first().json.mime, file_name: $('Normalizar update').first().json.file_name, file_size: $('Normalizar update').first().json.file_size, caption: $('Normalizar update').first().json.text }) ] }}")}},"credentials":CP,"position":[1100,3500],...K5,"alwaysOutputData":true}});
const n105 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Docs: executar","parameters":{"operation":"executeQuery","query":"SELECT agente.f_docs($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.docs_json ] }}")}},"credentials":CP,"position":[4480,4200],...K5,"alwaysOutputData":true}});
const n106 = ifElse({type:"n8n-nodes-base.if",version:2.2,config:{"name":"Docs: tem arquivos?","parameters":{"conditions":{"options":O2,"conditions":[{"leftValue":expr("{{ !!($json.r && Array.isArray($json.r.files) && $json.r.files.length > 0) }}"),"operator":{"type":"boolean","operation":"true","singleValue":true},"rightValue":""}],"combinator":"and"}},"position":[4704,4200]}});
const n107 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Docs: resposta","parameters":{...K6,"jsCode":`const u = $('Normalizar update').first().json;
const r = $input.first().json.r || {};
return [{ json: { chat_id: u.chat_id, text: r.text || 'Nao consegui agora. Tente de novo.', kb: r.kb || 'none', rid: r.rid || 0, state: '' } }];`},"position":[4928,4360]}});
const n108 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Docs: expandir","parameters":{...K6,"jsCode":`const u = $('Normalizar update').first().json;
const r = $input.first().json.r || {};
const files = Array.isArray(r.files) ? r.files : [];
return files.slice(0, 10).map(function (f, i) {
const t = f.tg_type === 'photo' ? 'photo' : (f.tg_type === 'video' ? 'video' : 'document');
return { json: { chat_id: u.chat_id, file_id: String(f.file_id || ''), tg_type: t, caption: String(f.caption || '').replace(/[<>&]/g, '').slice(0, 200), idx: i } };
});`},"position":[4928,4040]}});
const n109 = switchCase({type:"n8n-nodes-base.switch",version:3.4,config:{"name":"Docs: tipo de arquivo","parameters":{"mode":"rules","rules":{"values":[{"outputKey":"foto","renameOutput":true,"conditions":{"options":O1,"conditions":[{"leftValue":expr("{{ $json.tg_type }}"),"operator":OE,"rightValue":"photo"}],"combinator":"and"}},{"outputKey":"video","renameOutput":true,"conditions":{"options":O1,"conditions":[{"leftValue":expr("{{ $json.tg_type }}"),"operator":OE,"rightValue":"video"}],"combinator":"and"}}]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"documento"}},"position":[5152,4040]}});
const n110 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Docs: enviar foto","parameters":{"resource":"message","operation":"sendPhoto","chatId":expr("{{ $json.chat_id }}"),"binaryData":false,"file":expr("{{ $json.file_id }}"),"additionalFields":{"caption":expr("{{ $json.caption }}"),"parse_mode":"HTML"}},"credentials":CT,"position":[5376,3920],"onError":"continueRegularOutput"}});
const n111 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Docs: enviar video","parameters":{"resource":"message","operation":"sendVideo","chatId":expr("{{ $json.chat_id }}"),"binaryData":false,"file":expr("{{ $json.file_id }}"),"additionalFields":{"caption":expr("{{ $json.caption }}"),"parse_mode":"HTML"}},"credentials":CT,"position":[5376,4040],"onError":"continueRegularOutput"}});
const n112 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Docs: enviar documento","parameters":{"resource":"message","operation":"sendDocument","chatId":expr("{{ $json.chat_id }}"),"binaryData":false,"file":expr("{{ $json.file_id }}"),"additionalFields":{"caption":expr("{{ $json.caption }}"),"parse_mode":"HTML"}},"credentials":CT,"position":[5376,4160],"onError":"continueRegularOutput"}});
const n113 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Docs: resposta final","parameters":{...K6,"jsCode":`const u = $('Normalizar update').first().json;
const r = $('Docs: executar').first().json.r || {};
let total = 0;
try { total = $('Docs: expandir').all().length; } catch (e) { total = 0; }
let feitos = 0;
let falhas = 0;
let a = [];
try { a = $('Docs: enviar foto').all(); } catch (e) { a = []; }
a.forEach(function (it) { if (it.json && it.json.error) { falhas += 1; } else { feitos += 1; } });
a = [];
try { a = $('Docs: enviar video').all(); } catch (e) { a = []; }
a.forEach(function (it) { if (it.json && it.json.error) { falhas += 1; } else { feitos += 1; } });
a = [];
try { a = $('Docs: enviar documento').all(); } catch (e) { a = []; }
a.forEach(function (it) { if (it.json && it.json.error) { falhas += 1; } else { feitos += 1; } });
if (feitos + falhas < total) { return []; }
let text = String(r.text || 'Pronto.');
if (falhas > 0) { text += ' (' + falhas + (falhas === 1 ? ' arquivo nao pode ser enviado' : ' arquivos nao puderam ser enviados') + ': o Telegram recusou.)'; }
return [{ json: { chat_id: u.chat_id, text: text, kb: 'none', rid: 0, state: '' } }];`},"position":[5600,4040]}});
const n114 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com dc del","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Sim, apagar","additionalFields":{"callback_data":expr("dcdel:{{ $('Preparar envio').first().json.rid }}")}},{"text":"Nao","additionalFields":{"callback_data":expr("dckeep:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,5520]}});
const n115 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com dc fdel","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Sim, apagar a pasta","additionalFields":{"callback_data":expr("dcfdel:{{ $('Preparar envio').first().json.rid }}")}},{"text":"Nao","additionalFields":{"callback_data":expr("dckeep:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,5712]}});
const n116 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Listas: executar","parameters":{"operation":"executeQuery","query":"SELECT agente.f_lists($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.list_json ] }}")}},"credentials":CP,"position":[4480,4400],"onError":"continueRegularOutput"}});
const n117 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Notas: executar","parameters":{"operation":"executeQuery","query":"SELECT agente.f_notes($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.note_json ] }}")}},"credentials":CP,"position":[4480,4592],"onError":"continueRegularOutput"}});
const n118 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Listas: resposta","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
return [{ json: { chat_id: a.chat_id, text: r.text || 'Nao consegui agora. Tente de novo.', kb: r.kb || 'none', rid: r.rid || 0, state: '' } }];`},"position":[4704,4496]}});
const n119 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com ls confirm","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Confirmar","additionalFields":{"callback_data":expr("lsok:{{ $('Preparar envio').first().json.rid }}")}},{"text":"Cancelar","additionalFields":{"callback_data":expr("lsno:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,5904]}});
const n120 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Projetos: Executar","parameters":{"operation":"executeQuery","query":"SELECT agente.f_projects($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.proj_json ] }}")}},"credentials":CP,"position":[4480,4176],"onError":"continueRegularOutput"}});
const n121 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Projetos: Resposta","parameters":{...K6,"jsCode":`let r = {};
try { r = $('Projetos: Executar').first().json.r || {}; } catch (e1) { r = {}; }
if (!r.text) { try { r = $('Executar botao').first().json.r || {}; } catch (e2) { r = {}; } }
const a = $('Normalizar update').first().json;
return [{ json: { chat_id: a.chat_id, text: r.text || 'Nao consegui mexer nos projetos agora. Tente de novo.', kb: r.kb || 'none', rid: r.rid || 0, state: r.state || '' } }];`},"position":[4704,4176]}});
const n122 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com pj tasks","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Gravar tarefas","additionalFields":{"callback_data":expr("pjok:{{ $('Preparar envio').first().json.rid }}")}},{"text":"Cancelar","additionalFields":{"callback_data":expr("pjno:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,6096]}});
const n123 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com pj del","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Sim, apagar","additionalFields":{"callback_data":expr("pjdel:{{ $('Preparar envio').first().json.rid }}")}},{"text":"Nao","additionalFields":{"callback_data":expr("pjkeep:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,6288]}});
const n124 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Projetos: plano de leitura","parameters":{"operation":"executeQuery","query":"SELECT agente.f_proj_gt_plan($1::bigint, $2::jsonb) AS gt","options":{"queryReplacement":expr("{{ [ $('Buscar usuario').first().json.id, (['list', 'show', 'overdue'].indexOf((JSON.parse($('Interpretar resposta').first().json.proj_json || '{}')).action) >= 0) ? '{\"list\":true,\"push\":false}' : '{\"list\":false,\"push\":false}' ] }}")}},"credentials":CP,"position":[4032,4288],"onError":"continueRegularOutput"}});
const n125 = ifElse({type:"n8n-nodes-base.if",version:2.2,config:{"name":"Projetos: ler do Google?","parameters":{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"loose"},"conditions":[{"leftValue":expr("{{ ($json.gt && $json.gt.ops) ? $json.gt.ops.length : 0 }}"),"operator":{"type":"number","operation":"gt"},"rightValue":0}],"combinator":"and"}},"position":[4256,4288]}});
const n126 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Projetos: Google (leitura)","parameters":{"source":"database","mode":"once","workflowId":{"__rl":true,"mode":"id","value":"G5N2OpaT2v6Pczcl"},"workflowInputs":{"mappingMode":"defineBelow","value":{"owner":expr("{{ $json.gt.owner }}"),"ops":expr("{{ JSON.stringify($json.gt.ops) }}")}}},"position":[4480,4400],"onError":"continueRegularOutput"}});
const n127 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Projetos: aplicar leitura","parameters":{"operation":"executeQuery","query":"SELECT agente.f_proj_google_apply($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Buscar usuario').first().json.id, JSON.stringify($input.first().json) ] }}")}},"credentials":CP,"position":[4704,4400],"onError":"continueRegularOutput"}});
const n128 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Projetos: plano de envio","parameters":{"operation":"executeQuery","query":"SELECT agente.f_proj_gt_plan($1::bigint, $2::jsonb) AS gt","options":{"queryReplacement":expr("{{ [ $('Buscar usuario').first().json.id, '{\"push\":true,\"limit\":40}' ] }}")}},"credentials":CP,"position":[4704,4288],"onError":"continueRegularOutput"}});
const n129 = ifElse({type:"n8n-nodes-base.if",version:2.2,config:{"name":"Projetos: enviar ao Google?","parameters":{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"loose"},"conditions":[{"leftValue":expr("{{ ($json.gt && $json.gt.ops) ? $json.gt.ops.length : 0 }}"),"operator":{"type":"number","operation":"gt"},"rightValue":0}],"combinator":"and"}},"position":[4928,4288]}});
const n130 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Projetos: Google (envio)","parameters":{"source":"database","mode":"once","workflowId":{"__rl":true,"mode":"id","value":"G5N2OpaT2v6Pczcl"},"workflowInputs":{"mappingMode":"defineBelow","value":{"owner":expr("{{ $json.gt.owner }}"),"ops":expr("{{ JSON.stringify($json.gt.ops) }}")}}},"position":[5152,4400],"onError":"continueRegularOutput"}});
const n131 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Projetos: aplicar envio","parameters":{"operation":"executeQuery","query":"SELECT agente.f_proj_google_apply($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Buscar usuario').first().json.id, JSON.stringify($input.first().json) ] }}")}},"credentials":CP,"position":[5376,4400],"onError":"continueRegularOutput"}});
const n132 = ifElse({type:"n8n-nodes-base.if",version:2.2,config:{"name":"Projetos: botao de projeto?","parameters":{"conditions":{"options":{"caseSensitive":true,"leftValue":"","typeValidation":"loose"},"conditions":[{"leftValue":expr("{{ String($('Normalizar update').first().json.cb_data || '') }}"),"operator":{"type":"string","operation":"startsWith"},"rightValue":"pj"}],"combinator":"and"}},"position":[1124,3600]}});
const n133 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Comando: dados","parameters":{"operation":"executeQuery","query":"SELECT agente.f_command_data($1::bigint) AS r, CASE $2::text WHEN '/contatos' THEN agente.f_list_pessoas($1::bigint) WHEN '/locais' THEN agente.f_list_lugares($1::bigint) WHEN '/memoria' THEN agente.f_mem_list($1::bigint, $3::text) WHEN '/config' THEN agente.f_mem_switches($1::bigint) END AS x","options":{"queryReplacement":expr("{{ [ $('Buscar usuario').first().json.id, String($('Normalizar update').first().json.text || '').split(' ')[0].split('@')[0].toLowerCase(), String($('Normalizar update').first().json.text || '').split(' ').slice(1).join(' ').trim() ] }}")}},"credentials":CP,"position":[4480,192],...K5,"alwaysOutputData":true}});
const n134 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com menu","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Lembretes e agenda","additionalFields":{"callback_data":expr("mn:lemb")}},{"text":"Tarefas e listas","additionalFields":{"callback_data":expr("mn:tar")}}]}},{"row":{"buttons":[{"text":"Dinheiro","additionalFields":{"callback_data":expr("mn:din")}},{"text":"Remédios","additionalFields":{"callback_data":expr("mn:rem")}}]}},{"row":{"buttons":[{"text":"Projetos","additionalFields":{"callback_data":expr("mn:proj")}},{"text":"Documentos","additionalFields":{"callback_data":expr("mn:doc")}}]}},{"row":{"buttons":[{"text":"Pessoas e memória","additionalFields":{"callback_data":expr("mn:pess")}},{"text":"Fotos e pesquisa","additionalFields":{"callback_data":expr("mn:foto")}}]}},{"row":{"buttons":[{"text":"Ajustes","additionalFields":{"callback_data":expr("mn:aj")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,6480]}});
const n135 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com place ask","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Marcar sem endereco","additionalFields":{"callback_data":expr("plskip:{{ $('Preparar envio').first().json.rid }}")}},{"text":"Nao perguntar mais","additionalFields":{"callback_data":expr("plnever:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,6672]}});
const n136 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com sup del","parameters":{"resource":"message","operation":"sendMessage",...K1,"text":expr("{{ $('Preparar envio').first().json.text }}"),...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Sim, apagar","additionalFields":{"callback_data":expr("spdel:{{ $('Preparar envio').first().json.rid }}")}},{"text":"Nao","additionalFields":{"callback_data":expr("spkeep:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false}},"credentials":CT,"position":[6272,6864]}});
const n137 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com fin recibo","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Desfazer","additionalFields":{"callback_data":expr("fundo:{{ $('Preparar envio').first().json.rid }}")}},{"text":"Editar","additionalFields":{"callback_data":expr("fedit:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,7056]}});
const n138 = ifElse({type:"n8n-nodes-base.if",version:2.2,config:{"name":"Tem relatorio?","parameters":{"conditions":{"options":O2,"conditions":[{"leftValue":expr("{{ ($json.r && $json.r.report) ? 'sim' : 'nao' }}"),"operator":OE,"rightValue":"sim"}],"combinator":"and"}},"position":[4592,3200]}});
const n139 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Chamar relatorio","parameters":{"source":"database","mode":"once","workflowId":{"__rl":true,"mode":"id","value":"QrxbGEgdoP56QszP"},"workflowInputs":{"mappingMode":"defineBelow","value":{"user_id":expr("{{ String($('Interpretar resposta').first().json.user_id) }}"),"chat_id":expr("{{ String($('Interpretar resposta').first().json.chat_id) }}"),"period":expr("{{ String($json.r.report.period || 'current') }}"),"month":expr("{{ String($json.r.report.month || '') }}"),"format":expr("{{ String($json.r.report.format || 'xlsx') }}"),"keywords":expr("{{ String($json.r.report.keywords || '') }}")}}},"position":[4704,3088]}});
const n140 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Registrar uso de IA","parameters":{"operation":"executeQuery","query":"SELECT agente.f_ai_log($1::bigint, $2::text, $3::text, NULLIF($4::text, '')::int, NULLIF($5::text, '')::int, $6::boolean) AS r","options":{"queryReplacement":expr("{{ [ $json.user_id, $json.ai_kind || 'texto', $json.ai_model || '', $json.ai_tin === null || $json.ai_tin === undefined ? '' : $json.ai_tin, $json.ai_tout === null || $json.ai_tout === undefined ? '' : $json.ai_tout, $json.ai_est === true ] }}")}},"credentials":CP,"position":[3808,2128],...K5,"alwaysOutputData":true}});
const n141 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Restaurar interpretacao","parameters":{...K6,"jsCode":`return [{ json: $('Interpretar resposta').first().json }];`},"position":[4032,2032]}});
const n142 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Consultar custo de IA","parameters":{"operation":"executeQuery","query":"SELECT agente.f_ai_cost_text($1::bigint) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id ] }}")}},"credentials":CP,"position":[4480,4000],...K5,"alwaysOutputData":true}});
const n143 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Resposta do custo de IA","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json || {};
return [{ json: { chat_id: a.chat_id, text: r.r || 'Nao consegui calcular o custo agora. Tente de novo.', kb: 'none', rid: 0, state: '' } }];`},"position":[4704,4000]}});
const n144 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Pesquisa: executar","parameters":{"source":"database","mode":"once","workflowId":{"__rl":true,"mode":"id","value":"HHhnrZ4dMoKxs5YI"},"workflowInputs":{"mappingMode":"defineBelow","value":{"user_id":expr("{{ String($('Interpretar resposta').first().json.user_id) }}"),"chat_id":expr("{{ String($('Interpretar resposta').first().json.chat_id) }}"),"pergunta":expr("{{ $('Interpretar resposta').first().json.research_query }}")}}},"position":[4480,4800],"onError":"continueRegularOutput"}});
const n145 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Pesquisa: resposta","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json || {};
const text = r.text ? String(r.text) : 'Não consegui pesquisar agora. Tente de novo daqui a pouco.';
return [{ json: { chat_id: a.chat_id, text: text, kb: 'none', rid: 0, state: '' } }];`},"position":[4704,4800]}});
const n146 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Importar agenda: montar pedido","parameters":{...K6,"jsCode":`const m = $('Montar pedido a IA').first().json;
const a = $('Interpretar resposta').first().json;
const NL = String.fromCharCode(10);
const tz = a.tz || 'America/Sao_Paulo';
let hoje = '';
try { hoje = DateTime.now().setZone(tz).toFormat('yyyy-MM-dd'); } catch (e) { hoje = new Date().toISOString().slice(0, 10); }
const regras = [
'Voce le a FOTO de uma agenda ou planner de papel e devolve os compromissos e as tarefas da pagina em JSON, sem inventar nada.',
'A foto pode estar girada 90 graus ou torta: gire mentalmente para ler. Pode haver duas paginas lado a lado (a semana inteira em duas paginas).',
'Hoje e ' + hoje + ' (fuso ' + tz + '). Leia o cabecalho de cada dia (nome, numero do dia e o mes impresso) e monte as datas completas YYYY-MM-DD. Se o ano nao estiver escrito, use o ano de hoje. week_start = a segunda-feira (ou o primeiro dia) da semana mostrada.',
'LEGENDA: se a pagina tem legenda de cores (quadrados coloridos com nomes como Academia, Faculdade, Estagio, Igreja, Tarefas), a cor de cada bloco indica a categoria. Copie os nomes exatamente como estao escritos e liste a legenda em legend.',
'GRADE DE HORARIOS: as linhas marcadas com horas (7h, 8h... 22h) formam a grade de cada dia. Um bloco colorido que cobre linhas de uma hora a outra e UM compromisso: start = hora da primeira linha coberta, end = hora logo apos a ultima linha coberta (HH:MM). Junte linhas seguidas da mesma cor no mesmo dia em um unico compromisso. Se o horario nao estiver claro, estime e marque uncertain=true.',
'BLOCOS COLORIDOS SAO OBRIGATORIOS: percorra dia por dia, da primeira ate a ultima hora da grade, e liste TODOS os blocos coloridos de cada dia como kind=evento, mesmo sem texto escrito (nesse caso title vazio e category = nome da cor na legenda). Nunca devolva so tarefas se a grade tem blocos coloridos. Cada dia da semana costuma ter varios blocos (por exemplo estagio todas as tardes de segunda a sexta).',
'TITULO: se o bloco tem texto escrito a mao, use o texto em title e a categoria da cor em category. Sem texto: title vazio e category = nome da categoria da cor.',
'TAREFAS: anotacoes sem horario (lista de tarefas ao pe do dia, caixas de marcar, destaques ou foco da semana) sao kind=tarefa, com day = o dia em que estao; destaque ou foco da semana sem dia: day = ultimo dia da semana. urgent=true so se estiver escrito entrega, prova, prazo, urgente ou com exclamacao.',
'NAO inclua: blocos riscados ou rabiscados, linhas vazias, texto impresso da agenda (frases, calendario pequeno do mes). Se a letra for duvidosa, inclua o item com uncertain=true; se for ilegivel, nao inclua e descreva em notes (ex.: a quinta a tarde esta ilegivel).',
'Responda somente o JSON do schema.'
];
const S = function (t) { return { type: t }; };
const N = function (t) { return { type: [t, 'null'] }; };
const itemProps = { day: S('string'), kind: { type: 'string', enum: ['evento', 'tarefa'] }, start: N('string'), end: N('string'), title: S('string'), category: N('string'), urgent: S('boolean'), uncertain: S('boolean') };
const legProps = { color: S('string'), category: S('string') };
const props = {
week_start: N('string'),
legend: { type: 'array', items: { type: 'object', properties: legProps, required: Object.keys(legProps), additionalProperties: false } },
items: { type: 'array', items: { type: 'object', properties: itemProps, required: Object.keys(itemProps), additionalProperties: false } },
notes: { type: 'array', items: S('string') }
};
const schema = { type: 'object', properties: props, required: Object.keys(props), additionalProperties: false };
let legenda = String(m.texto_atual || '').trim();
if (legenda.indexOf('Imagem enviada pelo usuario') === 0) { legenda = ''; }
const prompt = 'Leia a agenda de papel desta foto.' + (legenda ? NL + 'Mensagem da pessoa: ' + legenda : '');
return [{ json: { modelo: 'gpt-6.1-sol', instrucoes: regras.join(NL), prompt: prompt, schema_json: JSON.stringify(schema), image_url: m.image_url } }];`},"position":[4480,6000]}});
const n147 = node({type:"@n8n/n8n-nodes-langchain.openAi",version:2.3,config:{"name":"Importar agenda: ler foto","parameters":{"resource":"text","operation":"response","modelId":{"__rl":true,"mode":"id","value":expr("{{ $('Importar agenda: montar pedido').first().json.modelo }}")},"responses":{"values":[{"type":"text","role":"user","content":expr("{{ $('Importar agenda: montar pedido').first().json.prompt }}")},{"type":"image","role":"user","imageType":"url","imageUrl":expr("{{ $('Importar agenda: montar pedido').first().json.image_url }}"),"imageDetail":"high"}]},"simplify":false,"options":{"instructions":expr("{{ $('Importar agenda: montar pedido').first().json.instrucoes }}"),"maxTokens":6000,"store":false,"textFormat":{"textOptions":{"type":"json_schema","name":"agenda","schema":expr("{{ $('Importar agenda: montar pedido').first().json.schema_json }}"),"strict":true}}}},"credentials":CO,"position":[4704,6000],...K5,"retryOnFail":true}});
const n148 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Importar agenda: avisar","parameters":{"resource":"message","operation":"sendMessage","chatId":expr("{{ $('Normalizar update').first().json.chat_id }}"),"text":"Estou lendo sua agenda, isso leva cerca de 1 minuto.","additionalFields":{"appendAttribution":false}},"credentials":CT,"position":[4592,6000],"onError":"continueRegularOutput"}});
const n149 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Importar agenda: normalizar","parameters":{...K6,"jsCode":`const r = $input.first().json;
const a = $('Interpretar resposta').first().json;
let g = null;
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
const dre = /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/;
const hre = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;
const lista = (g && Array.isArray(g.items)) ? g.items : [];
const itens2 = [];
lista.slice(0, 80).forEach(function (it) {
if (!it || !dre.test(String(it.day || ''))) { return; }
const cat = String(it.category || '').trim();
const t = String(it.title || '').trim();
let label = t;
if (cat && t && it.kind !== 'tarefa') { label = (t.toLowerCase().indexOf(cat.toLowerCase()) === 0) ? t : cat + ' · ' + t; }
else if (cat && it.kind !== 'tarefa') { label = cat; }
let kind = it.kind === 'tarefa' ? 'task' : 'event';
let st = hre.test(String(it.start || '')) ? String(it.start) : '';
let en = hre.test(String(it.end || '')) ? String(it.end) : '';
let duvida = it.uncertain === true;
if (kind === 'event' && !st) { kind = 'task'; duvida = true; }
if (kind === 'event' && (!en || en <= st)) {
const h = parseInt(st.slice(0, 2), 10) + 1;
en = h > 23 ? '23:59' : (h < 10 ? '0' : '') + h + st.slice(2);
duvida = true;
}
if (kind === 'task' && !t) { return; }
itens2.push({ day: String(it.day), kind: kind, start: st, end: en, title: label || 'Compromisso', urgent: it.urgent === true, uncertain: duvida });
});
const notas = (g && Array.isArray(g.notes)) ? g.notes.map(function (n) { return String(n).slice(0, 160); }).slice(0, 6) : [];
const x = { week_start: (g && dre.test(String(g.week_start || ''))) ? g.week_start : null, items: itens2, notes: notas };
return [{ json: { user_id: a.user_id, x: JSON.stringify(x) } }];`},"position":[4928,6000]}});
const n150 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Importar agenda: rascunho","parameters":{"operation":"executeQuery","query":"SELECT agente.f_agimp_create($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $json.user_id, $json.x ] }}")}},"credentials":CP,"position":[5152,6000]}});
const n151 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Importar agenda: editar","parameters":{"operation":"executeQuery","query":"SELECT agente.f_agimp_edit($1::bigint, $2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.imp_json ] }}")}},"credentials":CP,"position":[4480,6200]}});
const n152 = ifElse({type:"n8n-nodes-base.if",version:2.2,config:{"name":"Importar agenda: criar em massa?","parameters":{"conditions":{"options":O2,"conditions":[{"leftValue":expr("{{ !!($json.r && $json.r.imp) }}"),"operator":{"type":"boolean","operation":"true","singleValue":true},"rightValue":""}],"combinator":"and"}},"position":[4704,6200]}});
const n153 = ifElse({type:"n8n-nodes-base.if",version:2.2,config:{"name":"Importar agenda: botao em massa?","parameters":{"conditions":{"options":O2,"conditions":[{"leftValue":expr("{{ !!($json.r && $json.r.imp) }}"),"operator":{"type":"boolean","operation":"true","singleValue":true},"rightValue":""}],"combinator":"and"}},"position":[4480,6400]}});
const n154 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Importar agenda: executar","parameters":{"source":"database","mode":"once","workflowId":{"__rl":true,"mode":"id","value":"30nv9jzvF504UQUu"},"workflowInputs":{"mappingMode":"defineBelow","value":{"draft_id":expr("{{ String($json.r.imp.draft_id) }}"),"calendar_key":expr("{{ $json.r.imp.calendar_key }}"),"eventos":expr("{{ JSON.stringify($json.r.imp.events) }}"),"tarefas":expr("{{ JSON.stringify($json.r.imp.tasks) }}")}}},"position":[4928,6300],"onError":"continueRegularOutput"}});
const n155 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Importar agenda: preparar conclusao","parameters":{...K6,"jsCode":`const r = $input.first().json || {};
let id = r.draft_id;
if (!id) { try { id = $('Executar botao').first().json.r.imp.draft_id; } catch (e) { id = null; } }
if (!id) { try { id = $('Importar agenda: editar').first().json.r.imp.draft_id; } catch (e) { id = null; } }
let res = { events_ok: 0, events_fail: 0, tasks_ok: 0, tasks_fail: 0, errors: ['falha ao falar com o Google'] };
if (typeof r.events_ok === 'number') {
res = { events_ok: r.events_ok, events_fail: r.events_fail || 0, tasks_ok: r.tasks_ok || 0, tasks_fail: r.tasks_fail || 0, errors: Array.isArray(r.errors) ? r.errors : [] };
}
return [{ json: { draft_id: id ? Number(id) : 0, res: JSON.stringify(res) } }];`},"position":[5152,6300]}});
const n156 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Importar agenda: concluir","parameters":{"operation":"executeQuery","query":"SELECT agente.f_agimp_done($1::bigint, $2::bigint, $3::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Buscar usuario').first().json.id, $json.draft_id, $json.res ] }}")}},"credentials":CP,"position":[5376,6300]}});
const n157 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Importar agenda: resposta","parameters":{...K6,"jsCode":`const r = $input.first().json.r || {};
const u = $('Normalizar update').first().json;
return [{ json: { chat_id: u.chat_id, text: r.text || 'Ok.', kb: r.kb || 'none', rid: r.rid || 0, state: '' } }];`},"position":[5600,6150]}});
const n158 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com agimp","parameters":{"resource":"message","operation":"sendMessage",...K1,"text":expr("{{ $('Preparar envio').first().json.text }}"),...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Criar tudo","additionalFields":{"callback_data":expr("aiok:{{ $('Preparar envio').first().json.rid }}")}},{"text":"Cancelar","additionalFields":{"callback_data":expr("aino:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false}},"credentials":CT,"position":[6272,7248]}});
const n159 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Correcao: executar","parameters":{"operation":"executeQuery","query":"SELECT agente.f_recent_correct($1::bigint,$2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.corr_json || '{}' ] }}")}},"credentials":CP,"position":[3000,4900]}});
const n160 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Correcao: resposta","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
const r = $input.first().json.r || {};
return [{ json: { chat_id: a.chat_id, text: r.text || 'Nao consegui corrigir agora. Tente de novo.', kb: r.kb || 'none', rid: r.rid || 0, state: '' } }];`},"position":[3250,4900]}});
const n161 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Lote: abrir","parameters":{"operation":"executeQuery","query":"SELECT agente.f_batch_open($1::bigint) AS batch","options":{"queryReplacement":expr("{{ [ $json.user_id ] }}")}},"credentials":CP,"position":[2200,5200],"onError":"continueRegularOutput"}});
const n162 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Multi: preparar","parameters":{...K6,"jsCode":`const a = $('Interpretar resposta').first().json;
let batch = 0;
try { batch = Number($input.first().json.batch) || 0; } catch (e) { batch = 0; }
const tz = a.tz || 'America/Sao_Paulo';
const now = DateTime.now().setZone(tz);
const okDate = /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/;
const okTime = /^[0-9]{1,2}:[0-9]{2}$/;
const lista = Array.isArray(a.more_actions) ? a.more_actions.slice(0, 6) : [];
const db = []; const ev = []; const tk = []; const ask = [];
const q = function (s) { return '"' + s + '"'; };
lista.forEach(function (m) {
if (!m || typeof m !== 'object') { return; }
const kind = String(m.kind || '');
const title = String(m.title || '').trim();
if (kind === 'lista') {
let its = Array.isArray(m.items) ? m.items.map(function (x) { return String(x || '').trim(); }).filter(function (x) { return x !== ''; }) : [];
if (!its.length && title) { its = [title]; }
if (!its.length) { return; }
db.push({ kind: 'list', title: its.join(', '), list_name: m.list_name ? String(m.list_name) : '', items: its });
return;
}
if (!title) { return; }
if (kind === 'nota') { db.push({ kind: 'note', title: title }); return; }
if (kind === 'tomei') { db.push({ kind: 'supply', title: title }); return; }
if (kind === 'gasto') {
const amt = Number(m.amount);
if (!(amt > 0)) { ask.push('o valor de ' + q(title)); return; }
db.push({ kind: 'expense', title: title, amount: amt });
return;
}
if (kind === 'tarefa') {
tk.push({ title: title, due: (m.date && okDate.test(String(m.date))) ? String(m.date) : '', calendar_key: a.calendar_key || '' });
return;
}
if (kind === 'lembrete' || kind === 'compromisso') {
const tm0 = (m.time && okTime.test(String(m.time))) ? String(m.time) : '';
if (!tm0) { ask.push('a hora de ' + q(title)); return; }
const hhmm = tm0.length === 4 ? '0' + tm0 : tm0;
let d = (m.date && okDate.test(String(m.date))) ? String(m.date) : '';
if (!d) {
const t0 = DateTime.fromISO(now.toFormat('yyyy-MM-dd') + 'T' + hhmm, { zone: tz });
d = (t0 > now ? t0 : t0.plus({ days: 1 })).toFormat('yyyy-MM-dd');
}
const due = DateTime.fromISO(d + 'T' + hhmm, { zone: tz });
if (!due.isValid || due <= now) { ask.push('a data de ' + q(title)); return; }
const lead = (typeof m.lead_minutes === 'number' && m.lead_minutes >= 0) ? String(m.lead_minutes) : '';
if (kind === 'lembrete') {
db.push({ kind: 'reminder', title: title, due_iso: due.toISO(), lead: lead });
} else {
const dur = (typeof m.duration_minutes === 'number' && m.duration_minutes > 0) ? m.duration_minutes : 60;
ev.push({ title: title, due_iso: due.toISO(), end_iso: due.plus({ minutes: dur }).toISO(), location: m.location ? String(m.location) : '', lead_str: lead, calendar_key: a.calendar_key || '' });
}
}
});
return [{ json: Object.assign({}, a, { batch_id: batch, multi_db: db, multi_ev: ev, multi_tk: tk, multi_ask: ask, multi_n: db.length + ev.length + tk.length + ask.length }) }];`},"position":[2450,5200]}});
const n163 = ifElse({type:"n8n-nodes-base.if",version:2.3,config:{"name":"Multi: tem extras?","parameters":{"conditions":{"options":O2,"conditions":[{"leftValue":expr("{{ $json.multi_n > 0 }}"),"operator":{"type":"boolean","operation":"true","singleValue":true},"rightValue":""}],"combinator":"and"}},"position":[2700,5200]}});
const n164 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Multi: banco","parameters":{"operation":"executeQuery","query":"SELECT agente.f_multi_db($1::bigint,$2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $('Multi: preparar').first().json.user_id, JSON.stringify($('Multi: preparar').first().json.multi_db || []) ] }}")}},"credentials":CP,"position":[2950,5100],"onError":"continueRegularOutput"}});
const n165 = ifElse({type:"n8n-nodes-base.if",version:2.3,config:{"name":"Multi: tem compromissos?","parameters":{"conditions":{"options":O2,"conditions":[{"leftValue":expr("{{ ($('Multi: preparar').first().json.multi_ev || []).length > 0 }}"),"operator":{"type":"boolean","operation":"true","singleValue":true},"rightValue":""}],"combinator":"and"}},"position":[3200,5100]}});
const n166 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Multi: expandir compromissos","parameters":{...K6,"jsCode":`return ($('Multi: preparar').first().json.multi_ev || []).map(function (x) { return { json: x }; });`},"position":[3450,5000]}});
const n167 = switchCase({type:"n8n-nodes-base.switch",version:3.4,config:{"name":"Multi: qual calendario","parameters":{"mode":"rules","rules":{"values":[{"outputKey":"adrian","renameOutput":true,"conditions":{"options":O1,"conditions":[{"leftValue":expr("{{ $json.calendar_key }}"),"operator":OE,"rightValue":"adrian"}],"combinator":"and"}},{"outputKey":"maria","renameOutput":true,"conditions":{"options":O1,"conditions":[{"leftValue":expr("{{ $json.calendar_key }}"),"operator":OE,"rightValue":"maria"}],"combinator":"and"}}]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"sem calendario"}},"position":[3700,5000]}});
const n168 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Multi: Agenda Adrian","parameters":{"source":"database","mode":"each","workflowId":{"__rl":true,"mode":"id","value":"bBJo78YVQ1cOMX09"},"workflowInputs":{"mappingMode":"defineBelow","value":{"action":"create","summary":expr("{{ $json.title }}"),"start":expr("{{ $json.due_iso }}"),"end":expr("{{ $json.end_iso }}"),"location":expr("{{ $json.location || '' }}"),"attendees":"","send_updates":"all","force":"false","meet":"false","repeat_freq":"","repeat_until":"","repeat_count":""}}},"position":[3950,4900],"onError":"continueRegularOutput"}});
const n169 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Multi: Agenda Maria Clara","parameters":{"source":"database","mode":"each","workflowId":{"__rl":true,"mode":"id","value":"6bXuicjujajBuXbd"},"workflowInputs":{"mappingMode":"defineBelow","value":{"action":"create","summary":expr("{{ $json.title }}"),"start":expr("{{ $json.due_iso }}"),"end":expr("{{ $json.end_iso }}"),"location":expr("{{ $json.location || '' }}"),"attendees":"","send_updates":"all","force":"false","meet":"false","repeat_freq":"","repeat_until":"","repeat_count":""}}},"position":[3950,5060],"onError":"continueRegularOutput"}});
const n170 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Multi: sem calendario","parameters":{...K6,"jsCode":`return $input.all().map(function () { return { json: { ok: false, error: 'agenda nao conectada' } }; });`},"position":[3950,5220]}});
const n171 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Multi: concluir compromissos","parameters":{...K6,"jsCode":`const base = $('Multi: expandir compromissos').all();
const outs = $input.all();
const p = $('Multi: preparar').first().json;
const items = base.map(function (b, i) {
const x = b.json;
const o = (outs[i] && outs[i].json) ? outs[i].json : { error: 'sem resposta' };
let res = o;
if (o.ok !== true && o.ok !== false) { res = { ok: false, error: String((o.error && o.error.message) ? o.error.message : (o.error || 'sem resposta')).slice(0, 120) }; }
return { req: { title: x.title, due_iso: x.due_iso, end_iso: x.end_iso, location: x.location || '', lead_str: x.lead_str || '', source: 'text', calendar_key: x.calendar_key || '',
repeat_freq: '', repeat_until: '', repeat_count: '', attendees: '', meet: 'false' }, result: res };
});
return [{ json: { user_id: p.user_id, items_json: JSON.stringify(items) } }];`},"position":[4200,5000]}});
const n172 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Multi: compromissos no banco","parameters":{"operation":"executeQuery","query":"SELECT agente.f_multi_events($1::bigint,$2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $json.user_id, $json.items_json ] }}")}},"credentials":CP,"position":[4450,5000],"onError":"continueRegularOutput"}});
const n173 = ifElse({type:"n8n-nodes-base.if",version:2.3,config:{"name":"Multi: tem tarefas?","parameters":{"conditions":{"options":O2,"conditions":[{"leftValue":expr("{{ ($('Multi: preparar').first().json.multi_tk || []).length > 0 }}"),"operator":{"type":"boolean","operation":"true","singleValue":true},"rightValue":""}],"combinator":"and"}},"position":[4700,5100]}});
const n174 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Multi: expandir tarefas","parameters":{...K6,"jsCode":`return ($('Multi: preparar').first().json.multi_tk || []).map(function (x) { return { json: x }; });`},"position":[4950,5200]}});
const n175 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Multi: Google Tarefas","parameters":{"source":"database","mode":"each","workflowId":{"__rl":true,"mode":"id","value":"dnVm8cfVhpqXGWmr"},"workflowInputs":{"mappingMode":"defineBelow","value":{"calendar_key":expr("{{ $json.calendar_key }}"),"action":"add","title":expr("{{ $json.title }}"),"due":expr("{{ $json.due }}")}}},"position":[5200,5200],"onError":"continueRegularOutput"}});
const n176 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Multi: concluir tarefas","parameters":{...K6,"jsCode":`const base = $('Multi: expandir tarefas').all();
const outs = $input.all();
const p = $('Multi: preparar').first().json;
const items = base.map(function (b, i) {
const x = b.json;
const o = (outs[i] && outs[i].json) ? outs[i].json : {};
return { title: x.title, due: x.due || '', calendar_key: x.calendar_key || '', result: o };
});
return [{ json: { user_id: p.user_id, items_json: JSON.stringify(items) } }];`},"position":[5450,5200]}});
const n177 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Multi: tarefas no banco","parameters":{"operation":"executeQuery","query":"SELECT agente.f_multi_tasks($1::bigint,$2::jsonb) AS r","options":{"queryReplacement":expr("{{ [ $json.user_id, $json.items_json ] }}")}},"credentials":CP,"position":[5700,5200],"onError":"continueRegularOutput"}});
const n178 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Multi: consolidar","parameters":{...K6,"jsCode":`const p = $('Multi: preparar').first().json;
const lines = []; const fails = [];
['Multi: banco', 'Multi: compromissos no banco', 'Multi: tarefas no banco'].forEach(function (nm) {
try {
const r = $(nm).first().json.r;
if (r) {
(Array.isArray(r.lines) ? r.lines : []).forEach(function (x) { lines.push(String(x)); });
(Array.isArray(r.fails) ? r.fails : []).forEach(function (x) { fails.push(String(x)); });
}
} catch (e) {}
});
return [{ json: Object.assign({}, p, { multi_lines: lines, multi_fails: fails }) }];`},"position":[5950,5200]}});
const n179 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com multi undo","parameters":{"resource":"message","operation":"sendMessage",...K1,...K2,...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Desfazer tudo","additionalFields":{"callback_data":expr("mu:{{ $('Preparar envio').first().json.rid }}")}}]}}]},"additionalFields":{"appendAttribution":false,"parse_mode":"HTML"}},"credentials":CT,"position":[6272,7440]}});
const n180 = ifElse({type:"n8n-nodes-base.if",version:2.3,config:{"name":"Lote: desfazer Google?","parameters":{"conditions":{"options":O2,"conditions":[{"leftValue":expr("{{ !!($json.r && Array.isArray($json.r.cals) && $json.r.cals.length > 0) }}"),"operator":{"type":"boolean","operation":"true","singleValue":true},"rightValue":""}],"combinator":"and"}},"position":[1000,5400]}});
const n181 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Lote: expandir exclusoes","parameters":{...K6,"jsCode":`return (($('Executar botao').first().json.r || {}).cals || []).map(function (c) { return { json: c }; });`},"position":[1250,5300]}});
const n182 = switchCase({type:"n8n-nodes-base.switch",version:3.4,config:{"name":"Lote: qual calendario","parameters":{"mode":"rules","rules":{"values":[{"outputKey":"adrian","renameOutput":true,"conditions":{"options":O1,"conditions":[{"leftValue":expr("{{ $json.calendar_key }}"),"operator":OE,"rightValue":"adrian"}],"combinator":"and"}},{"outputKey":"maria","renameOutput":true,"conditions":{"options":O1,"conditions":[{"leftValue":expr("{{ $json.calendar_key }}"),"operator":OE,"rightValue":"maria"}],"combinator":"and"}}]},"options":{"fallbackOutput":"extra","renameFallbackOutput":"sem calendario"}},"position":[1500,5300]}});
const n183 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Lote: Agenda Adrian","parameters":{"source":"database","mode":"each","workflowId":{"__rl":true,"mode":"id","value":"bBJo78YVQ1cOMX09"},"workflowInputs":{"mappingMode":"defineBelow","value":{"action":"delete","summary":"","start":"","end":"","location":"","attendees":"","event_id":expr("{{ $json.event_id }}"),"send_updates":"none","force":"","meet":"","repeat_freq":"","repeat_until":"","repeat_count":"","response":""}}},"position":[1750,5200],"onError":"continueRegularOutput"}});
const n184 = node({type:"n8n-nodes-base.executeWorkflow",version:1.3,config:{"name":"Lote: Agenda Maria Clara","parameters":{"source":"database","mode":"each","workflowId":{"__rl":true,"mode":"id","value":"6bXuicjujajBuXbd"},"workflowInputs":{"mappingMode":"defineBelow","value":{"action":"delete","summary":"","start":"","end":"","location":"","attendees":"","event_id":expr("{{ $json.event_id }}"),"send_updates":"none","force":"","meet":"","repeat_freq":"","repeat_until":"","repeat_count":"","response":""}}},"position":[1750,5360],"onError":"continueRegularOutput"}});
const n185 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Lote: sem calendario","parameters":{...K6,"jsCode":`return $input.all().map(function () { return { json: { ok: false, error: 'agenda nao conectada' } }; });`},"position":[1750,5520]}});
const n186 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Lote: concluir desfazer","parameters":{...K6,"jsCode":`const u = $('Normalizar update').first().json;
const r = $('Executar botao').first().json.r || {};
const cals = Array.isArray(r.cals) ? r.cals : [];
const outs = $input.all();
const NL = String.fromCharCode(10);
const falhas = [];
cals.forEach(function (c, i) {
const o = (outs[i] && outs[i].json) ? outs[i].json : {};
if (o.ok !== true) { falhas.push('- ' + String(c.title || 'compromisso').slice(0, 60)); }
});
let text = String(r.text || 'Desfeito.');
if (falhas.length) { text += NL + NL + 'Não consegui apagar estes compromissos do Google (apague na agenda se quiser):' + NL + falhas.join(NL); }
return [{ json: { chat_id: u.chat_id, text: text, kb: 'none', rid: 0, state: '' } }];`},"position":[2000,5300]}});
const n187 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Memoria: gravar","parameters":{"operation":"executeQuery","query":"SELECT $1::bigint AS batch, (SELECT jsonb_agg(agente.f_mem_add($2::bigint, x->>'texto', coalesce(x->>'tipo', 'fato'), 'ia')) FROM jsonb_array_elements($3::jsonb) x) AS mem","options":{"queryReplacement":expr("{{ [ $json.batch, $('Interpretar resposta').first().json.user_id, $('Interpretar resposta').first().json.mem_json || '[]' ] }}")}},"credentials":CP,"position":[2325,5400],"onError":"continueRegularOutput"}});
const n188 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Memoria: preparar","parameters":{...K6,"jsCode":`const u = $('Normalizar update').first().json;
const user = $('Buscar usuario').first().json;
let st = null;
try { const raw = $('Ler estado da conversa').first().json.state; st = raw ? JSON.parse(raw) : null; } catch (e) { st = null; }
const fresh = !!(st && st.kind === 'offer' && Number(st.ts) > 0 && (Date.now() - Number(st.ts)) < 900000);
const btn = u.kind === 'callback';
let action = ''; let ref = ''; let email = ''; let address = '';
if (btn) { action = u.cb_data === 'of:y' ? 'offer_yes' : 'offer_no'; }
else {
let mm = {};
try { mm = JSON.parse($('Interpretar resposta').first().json.mm_json || '{}'); } catch (e) { mm = {}; }
action = mm.action || ''; ref = mm.ref || ''; email = mm.email || ''; address = mm.address || '';
}
const isOffer = action === 'offer_yes' || action === 'offer_no';
let expired = false;
if (isOffer && !fresh) { expired = true; action = 'none'; }
if (action === 'offer_no' && st && st.accepted === true) { action = 'none'; }
return [{ json: { user_id: user.id, chat_id: u.chat_id, btn: btn, action: action, expired: expired, ref: ref,
pessoa: (st && st.pessoa) ? String(st.pessoa) : '', lugar: (st && st.lugar) ? String(st.lugar) : '', rel: (st && st.rel) ? String(st.rel) : '',
email: email, address: address } }];`},"position":[3000,6200]}});
const n189 = node({type:"n8n-nodes-base.postgres",version:2.6,config:{"name":"Memoria: executar","parameters":{"operation":"executeQuery","query":"SELECT CASE $2::text WHEN 'forget' THEN agente.f_mem_forget($1::bigint, $3::text) WHEN 'list' THEN agente.f_mem_list($1::bigint, $3::text) WHEN 'switch_on' THEN agente.f_mem_set_switch($1::bigint, $3::text, true) WHEN 'switch_off' THEN agente.f_mem_set_switch($1::bigint, $3::text, false) WHEN 'offer_yes' THEN agente.f_offer_accept($1::bigint, $4::text, $5::text, $6::text, $7::text, $8::text) WHEN 'offer_no' THEN agente.f_offer_decline($1::bigint, $4::text, $6::text) END AS r","options":{"queryReplacement":expr("{{ [ $('Memoria: preparar').first().json.user_id, $('Memoria: preparar').first().json.action, $('Memoria: preparar').first().json.ref, $('Memoria: preparar').first().json.pessoa, $('Memoria: preparar').first().json.email, $('Memoria: preparar').first().json.lugar, $('Memoria: preparar').first().json.address, $('Memoria: preparar').first().json.rel ] }}")}},"credentials":CP,"position":[3250,6200],"onError":"continueRegularOutput"}});
const n190 = node({type:"n8n-nodes-base.code",version:2,config:{"name":"Memoria: resposta","parameters":{...K6,"jsCode":`const p = $('Memoria: preparar').first().json;
const r = $input.first().json.r || null;
let text = ''; let state = '';
if (p.expired) { text = 'Essa pergunta já passou. Se quiser salvar, me diz de novo.'; }
else if (p.action === 'none') { text = 'Ok, deixo assim.'; }
else if (!r) { text = 'Não consegui agora. Tente de novo.'; }
else { text = String(r.text || 'Ok.'); }
if (p.action === 'offer_yes' && r && r.ok === true) {
const falta = [];
if (r.person && !r.person.email) { falta.push('o e-mail'); }
if (r.place && !r.place.address) { falta.push('o endereço'); }
if (falta.length) {
text += ' Se quiser, me manda ' + falta.join(' e ') + ' que eu completo.';
state = JSON.stringify({ kind: 'offer', pessoa: p.pessoa, lugar: p.lugar, rel: p.rel, accepted: true, ts: Date.now() });
}
}
if (!state && p.btn) { state = JSON.stringify({ kind: 'none' }); }
return [{ json: { chat_id: p.chat_id, text: text, kb: 'none', rid: 0, state: state } }];`},"position":[3500,6200]}});
const n191 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com menu area","parameters":{"resource":"message","operation":"sendMessage",...K1,"text":expr("{{ $('Preparar envio').first().json.text }}"),...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Ver mais","additionalFields":{"callback_data":expr("mn:mais{{ $('Preparar envio').first().json.rid }}")}},{"text":"Voltar ao menu","additionalFields":{"callback_data":expr("mn:inicio")}}]}}]},"additionalFields":{"appendAttribution":false}},"credentials":CT,"position":[6272,7632]}});
const n192 = node({type:"n8n-nodes-base.telegram",version:1.2,config:{"name":"Enviar com menu mais","parameters":{"resource":"message","operation":"sendMessage",...K1,"text":expr("{{ $('Preparar envio').first().json.text }}"),...K3,"inlineKeyboard":{"rows":[{"row":{"buttons":[{"text":"Voltar à área","additionalFields":{"callback_data":expr("mn:a{{ $('Preparar envio').first().json.rid }}")}},{"text":"Menu","additionalFields":{"callback_data":expr("mn:inicio")}}]}}]},"additionalFields":{"appendAttribution":false}},"credentials":CT,"position":[6272,7824]}});
const n193 = node({type:"n8n-nodes-base.redis",version:1,config:{"name":"Ler regras","parameters":{"operation":"get","key":"agente:cfg:rules","propertyName":"regras","keyType":"string"},"credentials":CR,"position":[1900,256]}});

export default workflow('Y0Xjkwwljvku36ia', 'Agente | Telegram').add(n0).to(n1.to(n2.to(n3.to(n4.onTrue(n5.to(n6.to(n7.to(n8.to(n193.to(n9.onCase(0,n10.to(n11.to(n180.onTrue(n181.to(n182.onCase(0,n183.to(n186.to(n13.to(n50.to(n51.to(n52.onTrue(n53.to(n54.onCase(0,n55).onCase(1,n56).onCase(2,n57).onCase(3,n66).onCase(4,n67).onCase(5,n68).onCase(6,n86).onCase(7,n87).onCase(8,n88).onCase(9,n89).onCase(10,n90).onCase(11,n91).onCase(12,n98).onCase(13,n102).onCase(14,n114).onCase(15,n115).onCase(16,n119).onCase(17,n122).onCase(18,n123).onCase(19,n134).onCase(20,n135).onCase(21,n136).onCase(22,n137).onCase(23,n158).onCase(24,n179).onCase(25,n191).onCase(26,n192).onCase(27,n58))).onFalse(n54))))))).onCase(1,n184.to(n186)).onCase(2,n185.to(n186)))).onFalse(n153.onTrue(n154.to(n155.to(n156.to(n157.to(n13))))).onFalse(n79.onTrue(n80.onCase(0,n81.to(n84.to(n85.to(n13)))).onCase(1,n82.to(n84)).onCase(2,n83.to(n13))).onFalse(n132.onTrue(n128.to(n129.onTrue(n130.to(n131.to(n121.to(n13)))).onFalse(n121))).onFalse(n12.to(n13)))))))).onCase(1,n133.to(n14.to(n13))).onCase(2,n15.to(n59.onTrue(n60.to(n17.to(n18.to(n19.to(n61.onTrue(n63.to(n20.to(n140.to(n141.to(n161.to(n187.to(n162.to(n163.onTrue(n164.to(n165.onTrue(n166.to(n167.onCase(0,n168.to(n171.to(n172.to(n173.onTrue(n174.to(n175.to(n176.to(n177.to(n178.to(n21.onCase(0,n22.to(n23.to(n13))).onCase(1,n24.onCase(0,n25.to(n72.to(n73.to(n13)))).onCase(1,n26.to(n72)).onCase(2,n27.to(n13))).onCase(2,n28.onCase(0,n29.to(n74.onTrue(n75.to(n76.to(n13))).onFalse(n30.to(n49.to(n13))))).onCase(1,n31.to(n74)).onCase(2,n74)).onCase(3,n32.to(n33.to(n13))).onCase(4,n34.to(n35.to(n13))).onCase(5,n36.to(n37.to(n13))).onCase(6,n38.to(n39.to(n13))).onCase(7,n40.to(n41.to(n13))).onCase(8,n42.to(n43.to(n13))).onCase(9,n44.to(n45.to(n13))).onCase(10,n46.to(n47.to(n13))).onCase(11,n64.to(n138.onTrue(n139.to(n65.to(n13))).onFalse(n65))).onCase(12,n28).onCase(13,n77.to(n78.to(n13))).onCase(14,n92.onCase(0,n93.to(n94.to(n13))).onCase(1,n95.to(n97.to(n13)))).onCase(15,n96.to(n97)).onCase(16,n99.to(n101.to(n13))).onCase(17,n100.to(n101)).onCase(18,n105.to(n106.onTrue(n108.to(n109.onCase(0,n110.to(n113.to(n13))).onCase(1,n111.to(n113)).onCase(2,n112.to(n113)))).onFalse(n107.to(n13)))).onCase(19,n116.to(n118.to(n13))).onCase(20,n117.to(n118)).onCase(21,n124.to(n125.onTrue(n126.to(n127.to(n120.to(n128)))).onFalse(n120))).onCase(22,n142.to(n143.to(n13))).onCase(23,n144.to(n145.to(n13))).onCase(24,n146.to(n148.to(n147.to(n149.to(n150.to(n157)))))).onCase(25,n151.to(n152.onTrue(n154).onFalse(n157))).onCase(26,n159.to(n160.to(n13))).onCase(27,n188.to(n189.to(n190.to(n13)))).onCase(28,n48.to(n13)))))))).onFalse(n178))))).onCase(1,n169.to(n171)).onCase(2,n170.to(n171)))).onFalse(n173))).onFalse(n21))))))))).onFalse(n69.onTrue(n70.to(n71.to(n20))).onFalse(n62.to(n20)))))))).onFalse(n16.to(n17)))).onCase(3,n17).onCase(4,n103.to(n15)).onCase(5,n103).onCase(6,n14).onCase(7,n104.to(n107))))))))))));