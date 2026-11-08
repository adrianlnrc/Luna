-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ra_trg_fin()
-- Origem da definicao atual: 033_acoes_recentes.sql (linha 76)
-- Definicoes (migracao:linha), da mais antiga a atual: 033_acoes_recentes.sql:76
CREATE OR REPLACE FUNCTION agente.f_ra_trg_fin() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
BEGIN
  IF NEW.status NOT IN ('paid', 'pending') OR NEW.recurring_id IS NOT NULL OR coalesce(NEW.installment_no, 1) > 1 THEN RETURN NEW; END IF;
  PERFORM f_ra_log(NEW.user_id, 'expense', NEW.id, NULL, NULL,
    CASE WHEN NEW.kind = 'income' THEN 'receita ' ELSE '' END || NEW.description || ' ' || f_brl(NEW.amount));
  RETURN NEW;
EXCEPTION WHEN others THEN
  RETURN NEW;
END $$;
