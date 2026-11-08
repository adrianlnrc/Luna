-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_gen(p_rec bigint)
-- Origem da definicao atual: 008_financas.sql (linha 221)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:221
CREATE OR REPLACE FUNCTION f_fin_gen(p_rec bigint) RETURNS bigint LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE r fin_recurring%ROWTYPE; v_due date; v_id bigint;
BEGIN
  SELECT * INTO r FROM fin_recurring WHERE id = p_rec AND active;
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_due := f_fin_next_due(r.day_of_month, coalesce(r.last_generated_on + 1, f_fin_today(r.user_id)));
  INSERT INTO fin_entries (user_id, kind, amount, description, norm_desc, category_id, method, status, occurred_on, due_on, person, recurring_id, source)
  VALUES (r.user_id, r.kind, r.amount, r.description, f_norm(r.description), r.category_id, r.method, 'pending', v_due, v_due, r.person, r.id, 'recurring')
  RETURNING id INTO v_id;
  UPDATE fin_recurring SET last_generated_on = v_due WHERE id = p_rec;
  PERFORM f_fin_remind(v_id);
  RETURN v_id;
END $$;
