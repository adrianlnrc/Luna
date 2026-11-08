-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_proj_gt_trg_t_parent()
-- Origem da definicao atual: 030_projetos_google.sql (linha 86)
-- Definicoes (migracao:linha), da mais antiga a atual: 030_projetos_google.sql:86
CREATE OR REPLACE FUNCTION f_proj_gt_trg_t_parent() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
BEGIN
  IF coalesce(current_setting('agente.gsync', true), '') = 'on' THEN RETURN NULL; END IF;
  IF TG_OP = 'UPDATE' AND NEW.done IS NOT DISTINCT FROM OLD.done THEN RETURN NULL; END IF;
  UPDATE projects SET google_pending = true, google_ver = google_ver + 1
   WHERE id = NEW.project_id AND user_id = NEW.user_id AND google_task_id IS NOT NULL AND f_proj_gt_owner(user_id) IS NOT NULL;
  RETURN NULL;
END $$;
