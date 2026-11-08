-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ls_menu_ins(p_text text, p_block text)
-- Origem da definicao atual: 025_listas_compras.sql (linha 16)
-- Definicoes (migracao:linha), da mais antiga a atual: 025_listas_compras.sql:16
CREATE OR REPLACE FUNCTION f_ls_menu_ins(p_text text, p_block text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT CASE WHEN position(E'\n\nDica:' IN p_text) > 0
    THEN substr(p_text, 1, position(E'\n\nDica:' IN p_text) - 1) || p_block || substr(p_text, position(E'\n\nDica:' IN p_text))
    ELSE p_text || p_block END
$$;
