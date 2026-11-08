# ---------- M2 (onda 2): recibo com Desfazer + Editar por 24h e alertas de variacao ----------
# Depende de db/026_recibo_alertas.sql (f_fin com kb fin_recibo e alertas, f_callback com fedit e validade de 24h,
# f_fin_correct com data, f_card_status_text e f_summary_data com alerta de fatura, f_menu).
# Depende de patch_f6_correcoes.py (HTML em Preparar envio). Roda antes de patch_zz_compact.py.
# Ancoras alteradas:
#   - nos: novo teclado 'Enviar com fin recibo' (add_kb) e nova regra em 'Qual teclado?' (chave fin_recibo)
#   - Montar pedido a IA: trecho "correct (corrigir o ULTIMO lancamento: valor, categoria ou descricao)" (regra FINANCAS)
#   - Montar pedido a IA: nova regra estatica inserida antes de "  'FINANCAS categorias: "
# Sem mudanca no schema da IA (date ja existe; fin_action=correct ja existe). Sem nos novos de logica.

from intents import REGISTRY
REGISTRY.apply('finance.recibo', globals())
