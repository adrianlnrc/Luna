-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_contact_save(p_user bigint, p_name text, p_email text, p_favorite boolean)
-- Origem da definicao atual: 007_contatos.sql (linha 28)
-- Definicoes (migracao:linha), da mais antiga a atual: 007_contatos.sql:28
CREATE OR REPLACE FUNCTION f_contact_save(p_user bigint, p_name text, p_email text, p_favorite boolean DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE c contacts%ROWTYPE;
BEGIN
  IF p_email !~ '^[^@ ]+@[^@ ]+\.[^@ ]+$' THEN RETURN jsonb_build_object('ok', false, 'error', 'email'); END IF;
  INSERT INTO contacts(user_id, name, email, favorite)
  VALUES (p_user, lower(trim(p_name)), lower(trim(p_email)), COALESCE(p_favorite, false))
  ON CONFLICT (user_id, name) DO UPDATE SET email = EXCLUDED.email, favorite = COALESCE(p_favorite, contacts.favorite)
  RETURNING * INTO c;
  RETURN jsonb_build_object('ok', true, 'name', c.name, 'email', c.email, 'favorite', c.favorite);
END $$;
