-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_find_lugar(p_user bigint, p_name text)
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 389)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:389
CREATE OR REPLACE FUNCTION agente.f_find_lugar(p_user bigint, p_name text) RETURNS bigint
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE n text := regexp_replace(f_norm(p_name), '^(a|o|na|no|da|do|de|em|as|os) ', ''); v bigint; k int;
BEGIN
  IF n = '' THEN RETURN NULL; END IF;
  SELECT p.id INTO v FROM places p
   WHERE p.user_id = p_user AND (p.norm_name = n OR EXISTS (SELECT 1 FROM unnest(p.aliases) a WHERE f_norm(a) = n))
   ORDER BY p.id LIMIT 1;
  IF v IS NOT NULL THEN RETURN v; END IF;
  SELECT count(*), min(p.id) INTO k, v FROM places p
   WHERE p.user_id = p_user AND (p.norm_name LIKE n || ' %' OR n LIKE p.norm_name || ' %');
  IF k = 1 THEN RETURN v; END IF;
  RETURN NULL;
END $$;
