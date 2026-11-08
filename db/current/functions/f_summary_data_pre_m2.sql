-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_summary_data_pre_m2(p_user bigint)
-- Origem da definicao atual: 032_resumo_enxuto.sql (linha 260)
-- Definicoes (migracao:linha), da mais antiga a atual: 018_resumo_fase4.sql:11, 022_menu.sql:82, 032_resumo_enxuto.sql:260
CREATE OR REPLACE FUNCTION f_summary_data_pre_m2(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE
  v jsonb; c jsonb; t text := ''; x jsonb; NL text := chr(10); tip text; pj text;
BEGIN
  v := f_summary_data_base(p_user);
  c := COALESCE(v->'cards', '[]'::jsonb);
  FOR x IN SELECT * FROM jsonb_array_elements(c) LOOP
    t := t || '- Fatura ' || (x->>'name') || ' R$ ' || replace(to_char((x->>'amount')::numeric, 'FM999G990D00'), ',', '.') || ' vence ' || (x->>'due')
         || CASE WHEN (x->>'days')::int = 0 THEN ' (hoje)' WHEN (x->>'days')::int = 1 THEN ' (amanha)' ELSE '' END || NL;
  END LOOP;
  IF t <> '' THEN t := 'Cartoes:' || NL || t; END IF;
  pj := f_proj_deadline_lines(p_user);
  IF pj <> '' THEN t := t || CASE WHEN t <> '' THEN NL ELSE '' END || pj || NL; END IF;
  tip := f_tip(p_user);
  IF tip <> '' THEN t := rtrim(t, NL) || CASE WHEN rtrim(t, NL) <> '' THEN NL || NL ELSE '' END || tip; END IF;
  RETURN v || jsonb_build_object('extras_text', rtrim(t, NL));
END $$;
