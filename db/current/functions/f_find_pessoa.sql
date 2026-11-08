-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_find_pessoa(p_user bigint, p_name text)
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 374)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:374
CREATE OR REPLACE FUNCTION agente.f_find_pessoa(p_user bigint, p_name text) RETURNS bigint
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE n text := regexp_replace(f_norm(p_name), '^(a|o|as|os) ', ''); v bigint; k int;
BEGIN
  IF n = '' THEN RETURN NULL; END IF;
  SELECT c.id INTO v FROM contacts c
   WHERE c.user_id = p_user AND (f_norm(c.name) = n OR EXISTS (SELECT 1 FROM unnest(c.aliases) a WHERE f_norm(a) = n))
   ORDER BY c.id LIMIT 1;
  IF v IS NOT NULL THEN RETURN v; END IF;
  SELECT count(*), min(c.id) INTO k, v FROM contacts c
   WHERE c.user_id = p_user AND (f_norm(c.name) LIKE n || ' %' OR n LIKE f_norm(c.name) || ' %');
  IF k = 1 THEN RETURN v; END IF;
  RETURN NULL;
END $$;
