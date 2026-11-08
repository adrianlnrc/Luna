-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_materialize()
-- Origem da definicao atual: 008_financas.sql (linha 236)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:236
CREATE OR REPLACE FUNCTION f_fin_materialize() RETURNS void LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM fin_recurring WHERE active AND (last_generated_on IS NULL OR last_generated_on <= f_fin_today(user_id)) LOOP
    PERFORM f_fin_gen(r.id);
  END LOOP;
END $$;
