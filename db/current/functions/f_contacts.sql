-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_contacts(p_user bigint, p jsonb)
-- Origem da definicao atual: 021_locais_comandos.sql (linha 73)
-- Definicoes (migracao:linha), da mais antiga a atual: 021_locais_comandos.sql:73
CREATE OR REPLACE FUNCTION f_contacts(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE act text := lower(coalesce(p->>'contact_action', ''));
BEGIN
  IF act IN ('place_save', 'place_list', 'place_remove') THEN
    RETURN f_places(p_user, jsonb_build_object('act', act, 'name', coalesce(p->>'contact_name', ''), 'address', coalesce(p->>'place_address', '')));
  END IF;
  RETURN f_contacts_base(p_user, p);
END $$;
