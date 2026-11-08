-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ls_is_default(p text)
-- Origem da definicao atual: 025_listas_compras.sql (linha 10)
-- Definicoes (migracao:linha), da mais antiga a atual: 025_listas_compras.sql:10
CREATE OR REPLACE FUNCTION f_ls_is_default(p text) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT f_norm(f_ls_clean(p)) IN ('mercado','compras','compra','supermercado','super','feira','feiras','mercados')
$$;
