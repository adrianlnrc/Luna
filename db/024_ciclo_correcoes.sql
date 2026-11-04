-- 024: ciclo de correcoes (testes com personas Carla e Julia)
-- Idempotente. Todas as mudancas sao por wrapper: a funcao viva e renomeada para *_base
-- (so se o *_base ainda nao existe) e a funcao com o nome antigo passa a chamar a base.
--   f_fin               -> f_fin_base               (P2-d: varios gastos numa mensagem: items)
--   f_create_supply     -> f_create_supply_base     (P2-e: ask_total, pergunta da cartela so quando faz sentido)
--   f_reminder_create_ex-> f_reminder_create_ex_base(P2-f: lembrete identico nao duplica)
--   f_menu              -> f_menu_base              (P1-c / P2-d / P2-e: dicas no menu)
--   f_callback          -> f_callback_pre_f6        (P2-e: botoes spdel / spkeep)
-- Novas: f_supply_manage (renomear/apagar remedio), f_supply_cb (confirmacao de apagar).

SET search_path TO agente, public;

-- ---------- renomeios guardados ----------
DO $$ BEGIN
  IF to_regproc('agente.f_fin_base') IS NULL THEN
    ALTER FUNCTION agente.f_fin(bigint, jsonb) RENAME TO f_fin_base;
  END IF;
  IF to_regproc('agente.f_create_supply_base') IS NULL THEN
    ALTER FUNCTION agente.f_create_supply(bigint, text, integer, numeric, date, integer, text, time, integer) RENAME TO f_create_supply_base;
  END IF;
  IF to_regproc('agente.f_reminder_create_ex_base') IS NULL THEN
    ALTER FUNCTION agente.f_reminder_create_ex(bigint, text, timestamptz, boolean, integer, text, jsonb) RENAME TO f_reminder_create_ex_base;
  END IF;
  IF to_regproc('agente.f_menu_base') IS NULL THEN
    ALTER FUNCTION agente.f_menu(bigint, text) RENAME TO f_menu_base;
  END IF;
  IF to_regproc('agente.f_callback_pre_f6') IS NULL THEN
    ALTER FUNCTION agente.f_callback(bigint, text) RENAME TO f_callback_pre_f6;
  END IF;
END $$;

-- ---------- P2-d: f_fin aceita items (um lancamento por item) ----------
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

-- ---------- P2-e: pergunta da cartela so quando faz sentido ----------
CREATE OR REPLACE FUNCTION agente.f_create_supply(p_user bigint, p_item text, p_total integer DEFAULT NULL::integer, p_per_day numeric DEFAULT 1, p_started date DEFAULT NULL::date, p_alert_days integer DEFAULT NULL::integer, p_kind text DEFAULT NULL::text, p_take_time time without time zone DEFAULT NULL::time without time zone, p_left integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE r jsonb; ask boolean;
BEGIN
  r := f_create_supply_base(p_user, p_item, p_total, p_per_day, p_started, p_alert_days, p_kind, p_take_time, p_left);
  -- pergunta a cartela so se o item e novo, sem quantidade, e a pessoa nunca informou quantidade de nenhum item
  ask := coalesce((r->>'created')::boolean, false) AND coalesce((r->>'needs_total')::boolean, false)
         AND NOT EXISTS (SELECT 1 FROM supplies WHERE user_id = p_user AND id <> (r->>'id')::bigint AND units_total IS NOT NULL);
  RETURN r || jsonb_build_object('ask_total', ask);
END $function$;

-- ---------- P2-e: renomear / apagar remedio ----------
CREATE OR REPLACE FUNCTION agente.f_supply_manage(p_user bigint, p_item text, p_units_left integer, p_pause_days integer, p_action text, p_new_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE v_id bigint; s supplies%ROWTYPE; nn text := nullif(btrim(coalesce(p_new_name, '')), '');
        it text := lower(btrim(coalesce(p_item, '')));
        generic text[] := ARRAY['', 'remedio', 'remédio', 'medicamento', 'comprimido', 'pilula', 'pílula', 'capsula', 'cápsula', 'generico', 'genérico'];
BEGIN
  IF coalesce(p_action, '') = 'rename' THEN
    IF nn IS NULL THEN RETURN jsonb_build_object('action', 'rename', 'found', false, 'need_name', true); END IF;
    IF it = ANY (generic) THEN
      SELECT id INTO v_id FROM supplies WHERE user_id = p_user AND status = 'active' AND lower(btrim(item)) = ANY (generic) ORDER BY created_at DESC LIMIT 1;
    ELSE
      v_id := f_find_supply(p_user, p_item);
    END IF;
    IF v_id IS NULL THEN RETURN jsonb_build_object('action', 'rename', 'found', false); END IF;
    SELECT * INTO s FROM supplies WHERE id = v_id;
    IF EXISTS (SELECT 1 FROM supplies WHERE user_id = p_user AND status = 'active' AND id <> v_id AND lower(btrim(item)) = lower(nn)) THEN
      RETURN jsonb_build_object('action', 'rename', 'found', true, 'conflict', true, 'item', nn, 'old_item', s.item);
    END IF;
    UPDATE supplies SET item = nn WHERE id = v_id;
    RETURN jsonb_build_object('action', 'rename', 'found', true, 'old_item', s.item, 'item', nn, 'take_time', to_char(s.take_time, 'HH24:MI'));
  ELSIF coalesce(p_action, '') = 'delete' THEN
    v_id := f_find_supply(p_user, p_item);
    IF v_id IS NULL THEN RETURN jsonb_build_object('action', 'delete', 'found', false); END IF;
    SELECT * INTO s FROM supplies WHERE id = v_id;
    RETURN jsonb_build_object('action', 'delete', 'found', true, 'confirm', true, 'sid', v_id, 'item', s.item, 'take_time', to_char(s.take_time, 'HH24:MI'));
  END IF;
  RETURN f_supply_adjust(p_user, p_item, p_units_left, p_pause_days);
END $function$;

CREATE OR REPLACE FUNCTION agente.f_supply_cb(p_user bigint, p_data text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE a text := split_part(p_data, ':', 1); v_id bigint := nullif(split_part(p_data, ':', 2), '')::bigint; s supplies%ROWTYPE;
BEGIN
  IF a = 'spkeep' THEN RETURN jsonb_build_object('text', 'Ok, mantive.', 'kb', 'none'); END IF;
  SELECT * INTO s FROM supplies WHERE id = v_id AND user_id = p_user;
  IF NOT FOUND THEN RETURN jsonb_build_object('text', 'Esse item já foi apagado.', 'kb', 'none'); END IF;
  DELETE FROM notifications WHERE user_id = p_user AND (supply_id = v_id OR dose_id IN (SELECT id FROM supply_doses WHERE supply_id = v_id));
  DELETE FROM supply_doses WHERE supply_id = v_id;
  DELETE FROM supplies WHERE id = v_id;
  RETURN jsonb_build_object('text', 'Apaguei ' || s.item || CASE WHEN s.take_time IS NOT NULL THEN ' e o lembrete de tomar às ' || to_char(s.take_time, 'HH24:MI') ELSE '' END || '.', 'kb', 'none');
END $function$;

CREATE OR REPLACE FUNCTION agente.f_callback(p_user bigint, p_data text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
BEGIN
  IF split_part(p_data, ':', 1) IN ('spdel', 'spkeep') THEN
    RETURN f_supply_cb(p_user, p_data);
  END IF;
  RETURN f_callback_pre_f6(p_user, p_data);
END $function$;

-- ---------- P2-f: lembrete identico (mesmo titulo e horario, ainda pendente) nao duplica ----------
CREATE OR REPLACE FUNCTION agente.f_reminder_create_ex(p_user bigint, p_title text, p_due timestamp with time zone, p_shared boolean DEFAULT false, p_lead integer DEFAULT NULL::integer, p_source text DEFAULT 'text'::text, p_repeat jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE v_id bigint;
BEGIN
  SELECT id INTO v_id FROM reminders
   WHERE user_id = p_user AND kind = 'reminder' AND status = 'pending' AND due_at = p_due
     AND lower(btrim(title)) = lower(btrim(p_title))
   ORDER BY id LIMIT 1;
  IF v_id IS NOT NULL THEN
    RETURN jsonb_build_object('reminder_id', v_id, 'ask_lead', false, 'title', p_title, 'due_at', p_due, 'duplicate', true);
  END IF;
  RETURN f_reminder_create_ex_base(p_user, p_title, p_due, p_shared, p_lead, p_source, p_repeat);
END $function$;

-- ---------- Menu: dicas novas ----------
CREATE OR REPLACE FUNCTION agente.f_menu(p_user bigint, p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE r jsonb := f_menu_base(p_user, p_key); k text := lower(coalesce(btrim(p_key), 'inicio')); t text := r->>'text';
BEGIN
  IF k = 'remedios' THEN
    t := t || E'\n\nCorrigir e apagar:\n- "o nome é sertralina" (corrijo o nome de um item genérico)\n- "apaga o remédio sertralina" (peço confirmação por botão)\nSe faltar o nome ao cadastrar, eu pergunto.';
  ELSIF k = 'dinheiro' THEN
    t := t || E'\n\nDois gastos de uma vez: "gastei 120 na farmácia e 80 no mercado" vira dois lançamentos.';
  END IF;
  IF k <> 'inicio' AND k NOT IN ('', 'menu') THEN
    t := t || E'\n\nDica: uma coisa por mensagem funciona melhor. Se vierem vários pedidos juntos, eu faço o principal e aviso o que ficou de fora.';
  END IF;
  RETURN jsonb_set(r, '{text}', to_jsonb(t));
END $function$;
