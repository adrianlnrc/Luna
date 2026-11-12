-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_app_user()
-- Origem da definicao atual: 041_rls.sql (linha 16)
-- Definicoes (migracao:linha), da mais antiga a atual: 041_rls.sql:16
CREATE OR REPLACE FUNCTION f_app_user() RETURNS bigint
LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('app.user_id', true), '')::bigint $$;
