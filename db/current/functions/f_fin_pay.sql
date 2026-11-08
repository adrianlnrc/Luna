-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_pay(p_user bigint, p jsonb)
-- Origem da definicao atual: 008_financas.sql (linha 332)
-- Definicoes (migracao:linha), da mais antiga a atual: 008_financas.sql:332
CREATE OR REPLACE FUNCTION f_fin_pay(p_user bigint, p jsonb) RETURNS jsonb LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE today date := f_fin_today(p_user); q text := f_norm(p->>'title'); e fin_entries%ROWTYPE;
BEGIN
  SELECT * INTO e FROM fin_entries
  WHERE user_id = p_user AND status = 'pending'
    AND (q = '' OR norm_desc LIKE '%' || q || '%' OR f_norm(person) LIKE '%' || q || '%')
  ORDER BY (due_on < today) DESC, due_on, id LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('text', CASE WHEN q = '' THEN 'Não tenho nenhuma conta ou cobrança pendente anotada.'
      ELSE 'Não achei "' || btrim(p->>'title') || '" entre as pendentes. Diga "o que tenho a pagar" para ver a lista.' END, 'kb', 'none');
  END IF;
  UPDATE fin_entries SET status = 'paid', paid_on = today, occurred_on = today WHERE id = e.id;
  IF e.reminder_id IS NOT NULL THEN
    UPDATE reminders SET status = 'done' WHERE id = e.reminder_id;
    UPDATE notifications SET state = 'cancelled' WHERE reminder_id = e.reminder_id AND state = 'pending';
  END IF;
  RETURN jsonb_build_object('text', CASE WHEN e.kind = 'income' THEN 'Recebido: ' ELSE 'Pago: ' END || e.description || ' ' || f_brl(e.amount) ||
    CASE WHEN e.due_on < today THEN ' (vencia em ' || to_char(e.due_on, 'DD/MM') || ')' ELSE '' END || '.', 'kb', 'none');
END $$;
