-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_command_data_base(p_user bigint)
-- Origem da definicao atual: 021_locais_comandos.sql (linha 95)
-- Definicoes (migracao:linha), da mais antiga a atual: 021_locais_comandos.sql:95
-- Renomeada de f_command_data para f_command_data_base em 023_locais_pergunta.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_command_data_base).
CREATE OR REPLACE FUNCTION f_command_data(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE
  u users%ROWTYPE; r record; t text := ''; c text; g text; l text;
  nc integer; ng integer; np integer;
  lead text; ev text; cfg text;
BEGIN
  SELECT * INTO u FROM users WHERE id = p_user;
  IF NOT FOUND THEN RETURN jsonb_build_object('contatos', 'Não achei o seu cadastro.', 'config', 'Não achei o seu cadastro.'); END IF;
  SELECT count(*) INTO nc FROM contacts WHERE user_id = p_user;
  SELECT count(*) INTO ng FROM contact_groups WHERE user_id = p_user;
  SELECT count(*) INTO np FROM places WHERE user_id = p_user;

  -- /contatos
  c := 'Contatos (' || nc || '):';
  IF nc = 0 THEN c := c || E'\n- nenhum ainda. Ex.: "salva o e-mail da Claudia: claudia@x.com"'; END IF;
  FOR r IN SELECT name, email, favorite FROM contacts WHERE user_id = p_user ORDER BY favorite DESC, name LOOP
    c := c || E'\n- ' || f_ct_disp(r.name) || CASE WHEN r.favorite THEN ' (favorito)' ELSE '' END || ' - ' || r.email;
  END LOOP;
  g := 'Grupos (' || ng || '):';
  IF ng = 0 THEN g := g || E'\n- nenhum ainda. Ex.: "cria o grupo família com Ana e Bia"'; END IF;
  FOR r IN SELECT cg.name, (SELECT string_agg(f_ct_disp(ct.name), ', ' ORDER BY ct.name)
                              FROM contact_group_members m JOIN contacts ct ON ct.id = m.contact_id WHERE m.group_id = cg.id) AS membros
             FROM contact_groups cg WHERE cg.user_id = p_user ORDER BY cg.name LOOP
    g := g || E'\n- ' || f_ct_disp(r.name) || ': ' || coalesce(r.membros, 'sem ninguém');
  END LOOP;
  l := 'Locais salvos (' || np || '):';
  IF np = 0 THEN l := l || E'\n- nenhum ainda. Ex.: "o local igreja é Rua das Flores, 120"'; END IF;
  FOR r IN SELECT name, address FROM places WHERE user_id = p_user ORDER BY name LOOP
    l := l || E'\n- ' || f_ct_disp(r.name) || ': ' || r.address;
  END LOOP;
  t := c || E'\n\n' || g || E'\n\n' || l
    || E'\n\nPara marcar com eles: "festa da igreja na sexta com a família" (uso o local e o grupo salvos, pergunto só a hora e confirmo antes de enviar o convite).'
    || E'\nPara mexer: "tira a Claudia dos contatos", "apaga o grupo família", "tira o local igreja".';

  -- /config
  lead := CASE WHEN u.default_lead_minutes IS NULL THEN 'pergunto a cada vez'
               WHEN u.default_lead_minutes = 0 THEN 'nunca avisar antes'
               ELSE u.default_lead_minutes || ' min antes' END;
  ev := CASE WHEN u.evening_enabled THEN to_char(u.evening_time, 'HH24:MI') ELSE 'desligado' END;
  cfg := 'Suas preferências:'
    || E'\n- Como te chamo: ' || coalesce(nullif(u.nickname, ''), u.name)
    || E'\n- Resumo da manhã: ' || coalesce(to_char(u.summary_time, 'HH24:MI'), 'desligado')
    || E'\n- Resumo do fim do dia: ' || ev
    || E'\n- Aviso antes dos compromissos: ' || lead
    || E'\n- Aviso de estoque: ' || u.supply_alert_days || ' dias antes de acabar (remédio: 7 dias)'
    || E'\n- Fechamento do mês financeiro: dia ' || u.fin_closing_day
    || E'\n- Fuso horário: ' || u.timezone
    || E'\n- Emojis: ' || CASE WHEN u.no_emoji THEN 'desligados' ELSE 'ligados' END
    || E'\n- Google Agenda e Tarefas: ' || CASE WHEN coalesce(u.calendar_key, '') <> '' THEN 'conectados' ELSE 'não conectados' END
    || E'\n\nGuardado por mim: ' || nc || ' contatos, ' || ng || ' grupos, ' || np || ' locais, '
    || (SELECT count(*) FROM lists WHERE user_id = p_user) || ' listas, '
    || (SELECT count(*) FROM notes WHERE user_id = p_user) || ' notas, '
    || (SELECT count(*) FROM projects WHERE user_id = p_user) || ' projetos e '
    || (SELECT count(*) FROM documents WHERE user_id = p_user) || ' documentos.'
    || E'\n\nPara mudar, é só me dizer: "resumo às 8h", "desliga o resumo do fim do dia", "sempre me avise 30 min antes", "avise o estoque com 7 dias", "fecha dia 10", "me chama de Dri", "sem emojis". Para ver contatos, grupos e locais: /contatos.';
  RETURN jsonb_build_object('contatos', t, 'config', cfg);
END $$;
