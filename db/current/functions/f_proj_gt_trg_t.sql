-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_proj_gt_trg_t()
-- Origem da definicao atual: 030_projetos_google.sql (linha 71)
-- Definicoes (migracao:linha), da mais antiga a atual: 030_projetos_google.sql:71
CREATE OR REPLACE FUNCTION f_proj_gt_trg_t() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
BEGIN
  IF coalesce(current_setting('agente.gsync', true), '') = 'on' THEN RETURN NEW; END IF;
  IF f_proj_gt_owner(NEW.user_id) IS NULL THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.google_pending := true; NEW.google_ver := 1;
  ELSIF NEW.title IS DISTINCT FROM OLD.title OR NEW.due_date IS DISTINCT FROM OLD.due_date
     OR NEW.urgent IS DISTINCT FROM OLD.urgent OR NEW.done IS DISTINCT FROM OLD.done THEN
    NEW.google_pending := true; NEW.google_ver := OLD.google_ver + 1;
  END IF;
  RETURN NEW;
END $$;
