-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ra_trg_list_items()
-- Origem da definicao atual: 033_acoes_recentes.sql (linha 100)
-- Definicoes (migracao:linha), da mais antiga a atual: 033_acoes_recentes.sql:100
CREATE OR REPLACE FUNCTION agente.f_ra_trg_list_items() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
BEGIN
  PERFORM f_ra_log(NEW.user_id, 'list_item', NEW.id, NULL, NULL, NEW.name);
  RETURN NEW;
EXCEPTION WHEN others THEN
  RETURN NEW;
END $$;
