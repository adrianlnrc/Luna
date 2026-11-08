-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_proj_gt_trg_del()
-- Origem da definicao atual: 030_projetos_google.sql (linha 96)
-- Definicoes (migracao:linha), da mais antiga a atual: 030_projetos_google.sql:96
CREATE OR REPLACE FUNCTION f_proj_gt_trg_del() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
BEGIN
  IF OLD.google_task_id IS NOT NULL THEN
    INSERT INTO project_google_trash (user_id, google_task_id, google_list) VALUES (OLD.user_id, OLD.google_task_id, OLD.google_list);
  END IF;
  RETURN NULL;
END $$;
