-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_remove(p_user bigint, p jsonb)
-- Origem da definicao atual: 008_financas.sql (linha 388)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:388
CREATE OR REPLACE FUNCTION f_fin_remove(p_user bigint, p jsonb) RETURNS jsonb LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE q text := f_norm(p->>'title'); e fin_entries%ROWTYPE;
BEGIN
  SELECT * INTO e FROM fin_entries WHERE user_id = p_user AND status <> 'draft' AND (q = '' OR norm_desc LIKE '%' || q || '%') ORDER BY id DESC LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Não achei esse lançamento.', 'kb', 'none'); END IF;
  RETURN jsonb_build_object('text', 'Apagar ' || e.description || ' ' || f_brl(e.amount) || ' (' || to_char(e.occurred_on, 'DD/MM') || ')' ||
    CASE WHEN e.series_id IS NOT NULL THEN ' e as outras parcelas' ELSE '' END || '?', 'kb', 'fin_delete', 'rid', e.id);
END $$;
