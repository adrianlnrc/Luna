# Extensao de create_event (Locais): pergunta de endereco quando o local nao e conhecido (teclado place_ask) e regra de resposta com endereco.
# Depende de db/023_locais_pergunta.sql (place_pending, f_place_is_name, f_place_cb). Os textos de /locais ficam em patch_f5_locais.py.
from .core import Intent, Edit

RAW_RULES = """  'ENDERECO DE LOCAL: se a ultima mensagem do assistente no historico perguntou o endereco de um local (\"Nao tenho o endereco de X. Qual e?\") e o usuario responde com um endereco (\"Rua das Flores, 120\" ou \"a igreja fica na Rua X\"), use intent=contact_manage com contact_action=place_save, contact_name = so o nome do local (X) e location = o endereco. Preencha reply com texto vazio.',
"""


def build():
    add_kb('place_ask', [('Marcar sem endereco', 'plskip:{rid}'), ('Nao perguntar mais', 'plnever:{rid}')])


INTENT = Intent(
    name='create_event.locais',
    extends='create_event',
    raw_rules=RAW_RULES,
    edits=[Edit('Interpretar resposta', 'jsCode', "if (out.intent === 'create_event' && out.due_iso) {\n  const convidados = Array.isArray(out.invitees) ? out.invitees.filter(function (x) { return String(x || '').trim() !== ''; }) : [];\n  if (convidados.length > 0 || out.meet === true) {",
                """const semAcento = function (s) {
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
  if (convidados.length > 0 || out.meet === true || localDesconhecido(out.location)) {""")],
    build=build,
)
