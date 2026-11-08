# Extensao de contact_manage (Fase 4b): locais salvos (place_save/place_list/place_remove) e grupos no prompt.
# Depende de db/021_locais_comandos.sql (f_ai_places, f_ai_groups, f_places).
from .core import Intent, Edit

# (a primeira linha tem trecho dinamico: locais e grupos do usuario)
RAW_RULES = """  'LOCAIS E GRUPOS SALVOS deste usuario. Locais (nome = endereco): ' + (user.places_txt || 'nenhum') + '. Grupos: ' + (user.groups_txt || 'nenhum') + '.',
  'LOCAIS SALVOS: contact_manage com contact_action place_save guarda um local (\"o local igreja e Rua das Flores, 120\", \"salva o endereco da igreja: Rua das Flores, 120\"): contact_name = so o nome do local (igreja) e location = o endereco. place_list = \"meus locais\" ou \"onde fica a igreja\". place_remove = \"tira o local igreja\" (contact_name). Em contact_manage de local preencha reply com texto vazio.',
  'COMPROMISSO COM LOCAL E GRUPO SALVOS: quando o usuario citar um local que esta em LOCAIS SALVOS (ex.: igreja) preencha location com o endereco salvo e nao ponha o local no title; quando citar um grupo ou contato salvo (ex.: familia, time) coloque o nome em invitees. A pessoa quer marcar o compromisso com aquele grupo naquele local. Exemplo: festa da igreja na sexta com a familia = create_event, title Festa da igreja, date da sexta, location com o endereco salvo da igreja, invitees [familia], time vazio. Se faltar so a hora, use create_event com time vazio e reply = pergunta curta citando titulo, dia, local e quem, por exemplo: Anotei a festa da igreja na sexta (05/11), na Rua das Flores, com a familia. Que horas? Quando a hora chegar na mensagem seguinte, complete o mesmo compromisso (o sistema pede a confirmacao antes de enviar o convite). Local citado que NAO esta salvo: use o nome dito como location. Grupo que NAO existe: ponha o nome em invitees mesmo assim (o sistema avisa e orienta).',
"""

INTENT = Intent(
    name='contact_manage.locais',
    extends='contact_manage',
    user_cols=['agente.f_ai_places(u.id) AS places_txt', 'agente.f_ai_groups(u.id) AS groups_txt'],
    raw_rules=RAW_RULES,
    edits=[
        Edit('Montar pedido a IA', 'jsCode', "'group_list', 'group_remove', null] },",
        "'group_list', 'group_remove', 'place_save', 'place_list', 'place_remove', null] },"),
        Edit('Interpretar resposta', 'jsCode', "contact_email: out.contact_email || '',",
        "contact_email: out.contact_email || '', place_address: out.location || '',")],
)
