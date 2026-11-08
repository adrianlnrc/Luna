-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_edit_cb(p_user bigint, p_id bigint)
-- Origem da definicao atual: 026_recibo_alertas.sql (linha 148)
-- Definicoes (migracao:linha), da mais antiga a atual: 026_recibo_alertas.sql:148
CREATE OR REPLACE FUNCTION agente.f_fin_edit_cb(p_user bigint, p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE e fin_entries%ROWTYPE; cat text;
BEGIN
  SELECT * INTO e FROM fin_entries WHERE id = p_id AND user_id = p_user;
  IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Esse lançamento já foi desfeito ou apagado.', 'kb', 'none'); END IF;
  IF f_fin_expired(p_id) THEN
    RETURN jsonb_build_object('text', 'Esse lançamento já passou de 24h; diga o que corrigir, por exemplo: corrige o gasto do mercado de ontem para 50', 'kb', 'none');
  END IF;
  SELECT name INTO cat FROM fin_categories WHERE id = e.category_id;
  RETURN jsonb_build_object('text',
    'Editar ' || e.description || ' ' || f_brl(e.amount) || ' (' || coalesce(cat, 'Outros') || ', ' || to_char(e.occurred_on, 'DD/MM') || E').\nDiga: "corrige para 50", "isso é Lazer" ou "foi dia 12".',
    'kb', 'none',
    'state', jsonb_build_object('kind', 'clarify', 'original',
      'Quero corrigir o lançamento "' || e.description || '" de ' || f_brl(e.amount) || ' do dia ' || to_char(e.occurred_on, 'DD/MM') || '.')::text);
END $function$;
