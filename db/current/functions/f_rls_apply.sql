-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_rls_apply()
-- Origem da definicao atual: 041_rls.sql (linha 40)
-- Definicoes (migracao:linha), da mais antiga a atual: 041_rls.sql:40
CREATE OR REPLACE FUNCTION f_rls_apply() RETURNS integer
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN SELECT tabela FROM f_user_tables() LOOP
    EXECUTE format('ALTER TABLE agente.%I ENABLE ROW LEVEL SECURITY', r.tabela);
    EXECUTE format('DROP POLICY IF EXISTS luna_app_isolamento ON agente.%I', r.tabela);
    EXECUTE format('CREATE POLICY luna_app_isolamento ON agente.%I FOR ALL TO luna_app USING (user_id = agente.f_app_user()) WITH CHECK (user_id = agente.f_app_user())', r.tabela);
    EXECUTE format('DROP POLICY IF EXISTS luna_sched_tudo ON agente.%I', r.tabela);
    EXECUTE format('CREATE POLICY luna_sched_tudo ON agente.%I FOR ALL TO luna_sched USING (true) WITH CHECK (true)', r.tabela);
    n := n + 1;
  END LOOP;
  RETURN n;
END $$;
