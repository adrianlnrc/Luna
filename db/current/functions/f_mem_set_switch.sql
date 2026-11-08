-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_mem_set_switch(p_user bigint, p_name text, p_value boolean)
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 112)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:112
CREATE OR REPLACE FUNCTION agente.f_mem_set_switch(p_user bigint, p_name text, p_value boolean) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE n text := f_mem_switch_name(p_name); lbl text;
BEGIN
  IF n IS NULL OR p_value IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'nome_invalido', 'text', 'Não entendi qual recurso ligar ou desligar (memória, sugestões ou perguntar se salvo).');
  END IF;
  INSERT INTO user_switches(user_id) VALUES (p_user) ON CONFLICT (user_id) DO NOTHING;
  EXECUTE format('UPDATE user_switches SET %I = $1, updated_at = now() WHERE user_id = $2', n) USING p_value, p_user;
  lbl := CASE n WHEN 'mem_enabled' THEN 'a memória' WHEN 'offer_save_enabled' THEN 'a pergunta de salvar contatos e lugares' ELSE 'as sugestões' END;
  RETURN jsonb_build_object('ok', true, 'name', n, 'value', p_value,
           'text', CASE WHEN p_value THEN 'Pronto, liguei ' ELSE 'Pronto, desliguei ' END || lbl || '.');
END $$;
