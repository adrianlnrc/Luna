-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_pre_m2(p_user bigint, p jsonb)
-- Origem da definicao atual: 024_ciclo_correcoes.sql (linha 33)
-- Definicoes (migracao:linha), da mais antiga a atual: 024_ciclo_correcoes.sql:33
-- Renomeada de f_fin para f_fin_pre_m2 em 026_recibo_alertas.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_fin_pre_m2).
CREATE OR REPLACE FUNCTION agente.f_fin(p_user bigint, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE
  items jsonb := CASE WHEN jsonb_typeof(p->'items') = 'array' THEN p->'items' ELSE NULL END;
  valid jsonb := '[]'::jsonb; it jsonb; q jsonb; res jsonb; rid bigint; last_id bigint;
  lines text[] := '{}'; notes text := ''; nt text; n integer; txt text; lbl text; e record; i integer;
BEGIN
  IF coalesce(p->>'action', '') = 'add' AND items IS NOT NULL AND coalesce(p->>'source', 'text') <> 'photo' THEN
    FOR it IN SELECT * FROM jsonb_array_elements(items) LOOP
      IF jsonb_typeof(it) = 'object' AND coalesce(nullif(it->>'amount', '')::numeric, 0) > 0 THEN
        valid := valid || jsonb_build_array(it);
      END IF;
    END LOOP;
    IF jsonb_array_length(valid) >= 2 THEN
      FOR it IN SELECT * FROM jsonb_array_elements(valid) LOOP
        q := (p - 'items') || jsonb_build_object(
               'title', coalesce(nullif(btrim(it->>'title'), ''), 'Gasto'),
               'amount', (it->>'amount')::numeric,
               'category', coalesce(it->>'category', ''),
               'category_stated', nullif(btrim(coalesce(it->>'category', '')), '') IS NOT NULL,
               'installments', 1, 'recurring_day', NULL);
        res := f_fin_base(p_user, q);
        rid := nullif(res->>'rid', '')::bigint;
        IF rid IS NULL THEN CONTINUE; END IF;
        last_id := rid;
        SELECT fe.description, fe.amount, c.name AS cat INTO e
          FROM fin_entries fe LEFT JOIN fin_categories c ON c.id = fe.category_id WHERE fe.id = rid;
        lines := lines || (e.description || ' ' || f_brl(e.amount) || ' (' || coalesce(e.cat, 'Outros') || ')');
        nt := substring(res->>'text' from '\.\s+(\S.*)$');
        IF nt IS NOT NULL AND position(nt in notes) = 0 THEN notes := notes || E'\n' || nt; END IF;
      END LOOP;
      n := coalesce(array_length(lines, 1), 0);
      IF n >= 1 THEN
        lbl := CASE WHEN p->>'kind' = 'income' THEN 'lançamentos' ELSE 'gastos' END;
        txt := '';
        FOR i IN 1..n LOOP
          txt := txt || CASE WHEN i = 1 THEN '' WHEN i = n THEN ' e ' ELSE ', ' END || lines[i];
        END LOOP;
        RETURN jsonb_build_object('text',
          'Registrei ' || n || ' ' || lbl || ': ' || txt || '.' || notes ||
          E'\n\nO botão Desfazer apaga só o último. Para outro, diga "desfaz o da farmácia".',
          'kb', 'fin_undo', 'rid', last_id);
      END IF;
    END IF;
  END IF;
  RETURN f_fin_base(p_user, p - 'items');
END $function$;
