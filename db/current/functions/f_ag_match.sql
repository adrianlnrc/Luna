-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ag_match(p_q text, p_t text)
-- Origem da definicao atual: 012_agenda.sql (linha 66)
-- Definicoes (migracao:linha), da mais antiga a atual: 012_agenda.sql:66
CREATE OR REPLACE FUNCTION f_ag_match(p_q text, p_t text) RETURNS int
LANGUAGE plpgsql IMMUTABLE SET search_path TO 'agente', 'public' AS $$
DECLARE qn text := f_norm(p_q); tn text := f_norm(p_t); toks text[];
BEGIN
  IF qn = '' THEN RETURN 1; END IF;
  IF position(qn IN tn) > 0 THEN RETURN 1; END IF;
  SELECT coalesce(array_agg(t), '{}') INTO toks
  FROM unnest(string_to_array(qn, ' ')) t
  WHERE length(t) >= 2 AND t NOT IN ('de','da','do','das','dos','a','o','as','os','e','com','no','na','nos','nas','em','para','pra','pro','um','uma','meu','minha','compromisso','evento','lembrete');
  IF cardinality(toks) = 0 THEN RETURN 0; END IF;
  IF NOT EXISTS (SELECT 1 FROM unnest(toks) t WHERE position(t IN tn) = 0) THEN RETURN 2; END IF;
  IF EXISTS (SELECT 1 FROM unnest(toks) t WHERE position(t IN tn) > 0) THEN RETURN 3; END IF;
  RETURN 0;
END $$;
