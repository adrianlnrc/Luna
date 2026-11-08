-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_offer_accept(p_user bigint, p_pessoa text, p_email text, p_lugar text, p_endereco text, p_parentesco text)
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 459)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:459
CREATE OR REPLACE FUNCTION agente.f_offer_accept(p_user bigint, p_pessoa text DEFAULT '', p_email text DEFAULT '', p_lugar text DEFAULT '',
                                                 p_endereco text DEFAULT '', p_parentesco text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  pn text := lower(left(btrim(coalesce(p_pessoa, '')), 80)); em text := lower(btrim(coalesce(p_email, '')));
  ln text := btrim(regexp_replace(btrim(coalesce(p_lugar, '')), '^(a|o|na|no|da|do|de|em) ', '', 'i')); ad text := left(btrim(coalesce(p_endereco, '')), 200);
  rel text := left(btrim(coalesce(p_parentesco, '')), 40);
  pid bigint; lid bigint; pres jsonb := NULL; lres jsonb := NULL; mail_bad boolean := false; parts text[] := '{}'; c contacts%ROWTYPE; pl places%ROWTYPE;
BEGIN
  IF em <> '' AND em !~ '^[^@ ]+@[^@ ]+\.[^@ ]+$' THEN mail_bad := true; em := ''; END IF;

  IF pn <> '' THEN
    pid := f_find_pessoa(p_user, pn);
    IF pid IS NULL THEN
      INSERT INTO contacts(user_id, name, email, relation) VALUES (p_user, pn, em, rel)
      ON CONFLICT (user_id, name) DO UPDATE SET email = CASE WHEN EXCLUDED.email <> '' THEN EXCLUDED.email ELSE contacts.email END,
                                                relation = CASE WHEN EXCLUDED.relation <> '' THEN EXCLUDED.relation ELSE contacts.relation END
      RETURNING * INTO c;
      pres := jsonb_build_object('status', 'created', 'id', c.id, 'name', c.name, 'email', nullif(c.email, ''), 'parentesco', nullif(c.relation, ''));
      parts := parts || ('Salvei ' || f_ct_disp(c.name) || ' nos contatos' || CASE WHEN c.email = '' THEN ' (sem e-mail)' ELSE ' (' || c.email || ')' END);
    ELSE
      UPDATE contacts SET email = CASE WHEN em <> '' THEN em ELSE email END, relation = CASE WHEN rel <> '' THEN rel ELSE relation END
       WHERE id = pid AND user_id = p_user RETURNING * INTO c;
      pres := jsonb_build_object('status', 'updated', 'id', c.id, 'name', c.name, 'email', nullif(c.email, ''), 'parentesco', nullif(c.relation, ''));
      parts := parts || ('Atualizei ' || f_ct_disp(c.name) || CASE WHEN c.email <> '' THEN ' (' || c.email || ')' ELSE '' END);
    END IF;
    DELETE FROM save_offers_silenced WHERE user_id = p_user AND tipo = 'pessoa' AND norm_name = regexp_replace(f_norm(pn), '^(a|o|as|os) ', '');
  END IF;

  IF ln <> '' THEN
    lid := f_find_lugar(p_user, ln);
    IF lid IS NULL THEN
      INSERT INTO places(user_id, name, norm_name, address) VALUES (p_user, lower(left(ln, 60)), f_norm(left(ln, 60)), ad)
      ON CONFLICT (user_id, norm_name) DO UPDATE SET address = CASE WHEN EXCLUDED.address <> '' THEN EXCLUDED.address ELSE places.address END
      RETURNING * INTO pl;
      lres := jsonb_build_object('status', 'created', 'id', pl.id, 'name', pl.name, 'address', nullif(pl.address, ''));
      parts := parts || ('salvei o lugar ' || pl.name || CASE WHEN pl.address = '' THEN ' (sem endereço)' ELSE ': ' || pl.address END);
    ELSE
      UPDATE places SET address = CASE WHEN ad <> '' THEN ad ELSE address END WHERE id = lid AND user_id = p_user RETURNING * INTO pl;
      lres := jsonb_build_object('status', 'updated', 'id', pl.id, 'name', pl.name, 'address', nullif(pl.address, ''));
      parts := parts || ('atualizei o lugar ' || pl.name || CASE WHEN pl.address <> '' THEN ': ' || pl.address ELSE '' END);
    END IF;
    DELETE FROM save_offers_silenced WHERE user_id = p_user AND tipo = 'lugar' AND norm_name = f_norm(left(ln, 60));
  END IF;

  IF pres IS NULL AND lres IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'nada_para_salvar', 'text', 'Não entendi o que salvar. Me diga o nome da pessoa ou do lugar.');
  END IF;
  RETURN jsonb_build_object('ok', true, 'person', pres, 'place', lres, 'email_invalid', mail_bad,
           'text', upper(left(array_to_string(parts, ' e '), 1)) || substr(array_to_string(parts, ' e '), 2) || '.'
                   || CASE WHEN mail_bad THEN ' Esse e-mail não parece válido; me manda de novo se quiser guardar.' ELSE '' END);
END $$;
