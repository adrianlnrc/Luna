-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_callback_pre_menu(p_user bigint, p_data text)
-- Origem da definicao atual: 011b_base_agenda.sql (linha 29)
-- Definicoes (migracao:linha), da mais antiga a atual: 011b_base_agenda.sql:29
-- Renomeada de f_callback para f_callback_pre_menu em 022_menu.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_callback_pre_menu).
CREATE OR REPLACE FUNCTION f_callback(p_user bigint, p_data text) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE a text := split_part(p_data, ':', 1);
BEGIN
  IF a LIKE 'ag%' THEN RETURN f_agenda_cb(p_user, p_data);      -- agenda (agok, agno, agpk, agsc, agfy, agfo, agrs, agrn)
  ELSIF a LIKE 'ct%' THEN RETURN f_contacts_cb(p_user, p_data);  -- contatos e convites (fase 3)
  ELSIF a LIKE 'ex%' THEN RETURN f_extras_cb(p_user, p_data);    -- extras (cartoes, lembretes recorrentes)
  END IF;
  RETURN f_callback_base(p_user, p_data);
END $$;
