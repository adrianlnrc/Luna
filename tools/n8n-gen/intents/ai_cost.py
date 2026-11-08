# Intencao ai_cost (M4 / onda 2): "quanto gasto de IA?" -> custo de IA por conversa.
# Depende de agente-telegram/db/028_custo_ia_anuais.sql (f_ai_cost_text). O registro de uso (Registrar uso de IA), o /custo e o
# lembrete anual (yearly) continuam em patch_f7_m4_custo.py: nao sao a Intencao.
from .core import Intent

# (a segunda regra e do lembrete anual, repeat_freq=yearly; mora aqui porque entra junto, no mesmo ponto)
RULES = [
 "CUSTO DE IA: se o usuario perguntar quanto o assistente gasta de IA, de OpenAI ou de tokens (quanto estou gastando de IA, quanto custa esse assistente, custo da IA, quanto gastei de tokens), use intent=ai_cost e reply vazio. Nao confunda com gastos de dinheiro do proprio usuario (isso e finance).",
 "LEMBRETE ANUAL: em create_reminder use repeat_freq=yearly quando o pedido se repete todo ano (me lembra todo ano do IPVA em 15/01, seguro do carro renova dia 10/06, aniversario de contrato todo ano em marco). date = a PROXIMA ocorrencia dessa data (neste ano se ainda nao passou, senao no ano seguinte); time = HH:MM citado ou 09:00 se nao houver hora (nos anuais nao pergunte a hora). lead_minutes = dias de antecedencia x 1440 quando o usuario pedir (me avisa 15 dias antes = 21600; 30 dias = 43200); se nao pedir aviso, deixe lead_minutes null (nos anuais o aviso padrao ja e 15 dias antes). repeat_until e repeat_count so se o usuario disser. title = o assunto (IPVA, Seguro do carro)."]


def build():
    nodes.append(pg_node('Consultar custo de IA', "SELECT agente.f_ai_cost_text($1::bigint) AS r",
                         "={{ [ $('Interpretar resposta').first().json.user_id ] }}", [4480, 4000]))
    nodes.append(code_node('Resposta do custo de IA',
                           "const a = $('Interpretar resposta').first().json;\n"
                           "const r = $input.first().json || {};\n"
                           "return [{ json: { chat_id: a.chat_id, text: r.r || 'Nao consegui calcular o custo agora. Tente de novo.', kb: 'none', rid: 0, state: '' } }];",
                           [4704, 4000]))
    _refresh()
    byname['Consultar custo de IA']['onError'] = 'continueRegularOutput'
    byname['Consultar custo de IA']['alwaysOutputData'] = True
    setc('Consultar custo de IA', ['Resposta do custo de IA'])
    setc('Resposta do custo de IA', ['Preparar envio'])


INTENT = Intent(
    name='ai_cost',
    rules=RULES,
    route=('custo ia', 'Consultar custo de IA'),
    build=build,
)
