-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ra_trg_notes()
-- Origem da definicao atual: 033_acoes_recentes.sql (linha 89)
-- Definicoes (migracao:linha), da mais antiga a atual: 033_acoes_recentes.sql:89
CREATE OR REPLACE FUNCTION agente.f_ra_trg_notes() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
BEGIN
  PERFORM f_ra_log(NEW.user_id, 'note', NEW.id, NULL, NULL, left(NEW.body, 70));
  RETURN NEW;
EXCEPTION WHEN others THEN
  RETURN NEW;
END $$;
