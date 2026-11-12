-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_channel_user(p_canal text, p_id_externo text)
-- Origem da definicao atual: 041_rls.sql (linha 82)
-- Definicoes (migracao:linha), da mais antiga a atual: 041_rls.sql:82
CREATE OR REPLACE FUNCTION f_channel_user(p_canal text, p_id_externo text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agente, public AS $$
  SELECT jsonb_build_object('id', u.id, 'status', u.status)
    FROM user_channels c JOIN users u ON u.id = c.user_id
   WHERE c.canal = p_canal AND c.id_externo = p_id_externo
$$;
