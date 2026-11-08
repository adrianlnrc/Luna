-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ct_find(p_user bigint, p_name text)
-- Origem da definicao atual: 014_contatos_convites.sql (linha 20)
-- Definicoes (migracao:linha), da mais antiga a atual: 014_contatos_convites.sql:20
CREATE OR REPLACE FUNCTION f_ct_find(p_user bigint, p_name text) RETURNS bigint
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE n text := f_norm(p_name); v bigint; k int;
BEGIN
  IF n = '' THEN RETURN NULL; END IF;
  SELECT id INTO v FROM contacts WHERE user_id = p_user AND f_norm(name) = n ORDER BY id LIMIT 1;
  IF v IS NOT NULL THEN RETURN v; END IF;
  SELECT count(*), min(id) INTO k, v FROM contacts WHERE user_id = p_user AND f_norm(name) LIKE n || ' %';
  IF k = 1 THEN RETURN v; END IF;
  RETURN NULL;
END $$;
