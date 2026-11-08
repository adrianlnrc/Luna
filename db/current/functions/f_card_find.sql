-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_card_find(p_user bigint, p_hint text)
-- Origem da definicao atual: 013_extras.sql (linha 92)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:92
CREATE OR REPLACE FUNCTION f_card_find(p_user bigint, p_hint text) RETURNS bigint
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE h text; v bigint;
BEGIN
  h := f_norm(regexp_replace(btrim(coalesce(p_hint, '')), '^((o|a) )?(cart[aã]o|cr[eé]dito)?( ?(do|da|de|no|na))? ', '', 'i'));
  IF h = '' THEN h := f_norm(p_hint); END IF;
  IF h = '' THEN RETURN NULL; END IF;
  SELECT id INTO v FROM fin_cards WHERE user_id = p_user AND active AND norm_name = h;
  IF v IS NOT NULL THEN RETURN v; END IF;
  SELECT id INTO v FROM fin_cards WHERE user_id = p_user AND active AND (norm_name LIKE '%' || h || '%' OR h LIKE '%' || norm_name || '%') ORDER BY id LIMIT 1;
  RETURN v;
END $$;
