# Extensao da intent finance (M2, onda 2): recibo com Desfazer + Editar por 24h e alertas de variacao.
# Depende de db/026_recibo_alertas.sql (f_fin com kb fin_recibo e alertas, f_callback com fedit, f_fin_correct com data).
from .core import Intent, Edit

RAW_RULES = """  'CORRIGIR LANCAMENTO: depois de registrar um gasto, pedidos como corrige para 50, na verdade foi 50, o valor e 50 = intent=finance, fin_action=correct e amount; isso e Lazer, a categoria e Transporte, muda para Saude = fin_action=correct e category; foi dia 12, foi ontem, era do dia 3, a data e 10/10 = fin_action=correct e date em AAAA-MM-DD (dia sem mes e o mes atual, ou o anterior se o dia ainda nao chegou). Se citar o gasto (corrige o gasto do mercado de ontem para 50), preencha title com o nome citado (mercado). Pode combinar valor, categoria e data na mesma mensagem. Se a conversa recente mostrar que o usuario tocou em Editar (Quero corrigir o lancamento X), title = X. Nunca crie um gasto novo para uma correcao.',
"""


def build():
    global byname
    # teclado do recibo: Desfazer (fundo) + Editar (fedit), mesmo formato do teclado 'Enviar com desfazer'
    add_kb('fin_recibo', [('Desfazer', 'fundo:{rid}'), ('Editar', 'fedit:{rid}')])
    byname = _refresh()
    _ref = byname['Enviar com desfazer']['parameters']
    _new = byname['Enviar com fin recibo']['parameters']
    _new['text'] = _ref['text']
    _new['additionalFields'] = dict(_ref['additionalFields'])


INTENT = Intent(
    name='finance.recibo',
    extends='finance',
    raw_rules=RAW_RULES,
    edits=[
        Edit('Montar pedido a IA', 'jsCode', "correct (corrigir o ULTIMO lancamento: valor, categoria ou descricao)",
        "correct (corrigir o ULTIMO lancamento, ou o citado pelo nome em title: valor, categoria, descricao ou data)")],
    build=build,
)
