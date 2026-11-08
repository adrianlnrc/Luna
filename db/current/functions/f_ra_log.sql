-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ra_log(p_user bigint, p_kind text, p_ref bigint, p_ref_text text, p_cal text, p_label text)
-- Origem da definicao atual: 033_acoes_recentes.sql (linha 47)
-- Definicoes (migracao:linha), da mais antiga a atual: 033_acoes_recentes.sql:47
CREATE OR REPLACE FUNCTION agente.f_ra_log(p_user bigint, p_kind text, p_ref bigint, p_ref_text text, p_cal text, p_label text) RETURNS void
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE b bigint;
BEGIN
  SELECT id INTO b FROM recent_batches WHERE user_id = p_user AND open_until > now() ORDER BY id DESC LIMIT 1;
  IF b IS NULL THEN RETURN; END IF;
  INSERT INTO recent_actions(user_id, batch_id, kind, ref_id, ref_text, calendar_key, label)
  VALUES (p_user, b, p_kind, p_ref, nullif(p_ref_text, ''), nullif(p_cal, ''), left(coalesce(p_label, ''), 120));
EXCEPTION WHEN others THEN
  NULL;
END $$;
