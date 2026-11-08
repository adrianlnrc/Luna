-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_mem_tokens(p text)
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 127)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:127
CREATE OR REPLACE FUNCTION agente.f_mem_tokens(p text) RETURNS text[]
LANGUAGE sql IMMUTABLE SET search_path TO 'agente', 'public' AS $$
  SELECT coalesce(array_agg(DISTINCT s.stem), '{}')
    FROM (SELECT CASE WHEN length(w) > 4 AND w ~ 's$' THEN left(w, -1) ELSE w END AS stem
            FROM unnest(string_to_array(f_norm(p), ' ')) w
           WHERE length(w) >= 4
             AND w <> ALL (ARRAY['para','como','mais','quero','tenho','pode','poderia','esse','essa','isso','esta','este','sobre','quando',
                                 'muito','fazer','favor','preciso','amanha','hoje','marca','marcar','agenda','lembra','lembrar','lembrete',
                                 'que','com','uma','uns','umas','dos','das','nos','nas','pelo','pela','meu','minha','seu','sua','vai','ser'])) s
$$;
