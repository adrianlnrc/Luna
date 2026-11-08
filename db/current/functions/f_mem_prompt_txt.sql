-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_mem_prompt_txt(p_user bigint, p_msg text)
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 220)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:220
CREATE OR REPLACE FUNCTION agente.f_mem_prompt_txt(p_user bigint, p_msg text) RETURNS text
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE t text;
BEGIN
  IF NOT f_mem_sw(p_user, 'mem_enabled') THEN RETURN ''; END IF;
  t := f_mem_relevant_txt(p_user, p_msg, 8);
  IF t = '' THEN RETURN ''; END IF;
  RETURN 'MEMORIA (fatos duradouros sobre o usuario; use so se ajudarem neste pedido):' || E'\n' || t;
EXCEPTION WHEN others THEN
  RETURN '';
END $$;
