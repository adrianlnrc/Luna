-- 033: Etapa 1 da secretaria natural (spec-secretaria-natural.md).
--   (a) varias acoes numa mensagem: lote por mensagem, execucao das acoes extras no banco, "Desfazer tudo"
--   (c) acoes recentes por usuario (ultimas 10 ou 24h, com os ids do que foi criado) para o prompt e para corrigir por texto
-- NAO foi aplicado em producao. Idempotente (CREATE ... IF NOT EXISTS / CREATE OR REPLACE / DROP TRIGGER IF EXISTS).
-- Ordem: aplicar ANTES de enviar o workflow principal (a query do "Buscar usuario" chama f_recent_actions_txt).
-- Depende de: f_reminder_create_ex, f_fin, f_notes, f_lists, f_supply_taken, f_agenda_after_create, f_callback (cadeia ate o db/031), f_brl, f_norm.
SET search_path TO agente, public;

-- ---------------------------------------------------------------- tabelas
-- Lote = uma mensagem do usuario. Fica "aberto" por 90 s: so nesse intervalo os triggers registram acoes
-- (assim lembretes/gastos gerados pelo Disparador, recorrencias e rotinas nao entram na lista).
CREATE TABLE IF NOT EXISTS agente.recent_batches (
  id         bigserial PRIMARY KEY,
  user_id    bigint NOT NULL REFERENCES agente.users(id) ON DELETE CASCADE,
  opened_at  timestamptz NOT NULL DEFAULT now(),
  open_until timestamptz NOT NULL DEFAULT now() + interval '90 seconds'
);
CREATE INDEX IF NOT EXISTS recent_batches_user ON agente.recent_batches (user_id, id DESC);

CREATE TABLE IF NOT EXISTS agente.recent_actions (
  id           bigserial PRIMARY KEY,
  user_id      bigint NOT NULL REFERENCES agente.users(id) ON DELETE CASCADE,
  batch_id     bigint REFERENCES agente.recent_batches(id) ON DELETE SET NULL,
  kind         text NOT NULL CHECK (kind IN ('reminder', 'event', 'expense', 'note', 'list_item', 'task')),
  ref_id       bigint,          -- id da linha no banco (reminders.id, fin_entries.id, notes.id, list_items.id)
  ref_text     text,            -- id externo: evento do Google (kind=event) ou tarefa do Google (kind=task)
  calendar_key text,
  label        text NOT NULL,   -- linha curta que vai para o prompt
  undone       boolean NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS recent_actions_user ON agente.recent_actions (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS recent_actions_batch ON agente.recent_actions (batch_id);

-- ---------------------------------------------------------------- lote e registro
CREATE OR REPLACE FUNCTION agente.f_batch_open(p_user bigint) RETURNS bigint
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE v bigint;
BEGIN
  DELETE FROM recent_actions WHERE created_at < now() - interval '3 days';
  DELETE FROM recent_batches WHERE opened_at < now() - interval '3 days';
  INSERT INTO recent_batches(user_id) VALUES (p_user) RETURNING id INTO v;
  RETURN v;
END $$;

-- Registra uma acao no lote aberto do usuario (sem lote aberto = nao e acao do usuario: ignora). Nunca lanca erro.
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

-- ---------------------------------------------------------------- triggers (cobrem todos os fluxos que criam algo)
CREATE OR REPLACE FUNCTION agente.f_ra_trg_reminders() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE tz text; ck text;
BEGIN
  IF NEW.repeat_of IS NOT NULL OR NEW.card_id IS NOT NULL OR NEW.status NOT IN ('pending', 'awaiting_time') THEN RETURN NEW; END IF;
  IF NEW.kind = 'event' AND coalesce(NEW.calendar_event_id, '') = '' THEN RETURN NEW; END IF;
  SELECT coalesce(nullif(timezone, ''), 'America/Sao_Paulo'), calendar_key INTO tz, ck FROM users WHERE id = NEW.user_id;
  PERFORM f_ra_log(NEW.user_id, NEW.kind, NEW.id, NEW.calendar_event_id, ck,
    NEW.title || CASE WHEN NEW.due_at IS NOT NULL THEN ', ' || to_char(NEW.due_at AT TIME ZONE tz, 'DD/MM HH24:MI') ELSE '' END);
  RETURN NEW;
EXCEPTION WHEN others THEN
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS ra_reminders ON agente.reminders;
CREATE TRIGGER ra_reminders AFTER INSERT ON agente.reminders FOR EACH ROW EXECUTE FUNCTION agente.f_ra_trg_reminders();

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
DROP TRIGGER IF EXISTS ra_fin ON agente.fin_entries;
CREATE TRIGGER ra_fin AFTER INSERT ON agente.fin_entries FOR EACH ROW EXECUTE FUNCTION agente.f_ra_trg_fin();

CREATE OR REPLACE FUNCTION agente.f_ra_trg_notes() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
BEGIN
  PERFORM f_ra_log(NEW.user_id, 'note', NEW.id, NULL, NULL, left(NEW.body, 70));
  RETURN NEW;
EXCEPTION WHEN others THEN
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS ra_notes ON agente.notes;
CREATE TRIGGER ra_notes AFTER INSERT ON agente.notes FOR EACH ROW EXECUTE FUNCTION agente.f_ra_trg_notes();

CREATE OR REPLACE FUNCTION agente.f_ra_trg_list_items() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
BEGIN
  PERFORM f_ra_log(NEW.user_id, 'list_item', NEW.id, NULL, NULL, NEW.name);
  RETURN NEW;
EXCEPTION WHEN others THEN
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS ra_list_items ON agente.list_items;
CREATE TRIGGER ra_list_items AFTER INSERT ON agente.list_items FOR EACH ROW EXECUTE FUNCTION agente.f_ra_trg_list_items();

-- ---------------------------------------------------------------- texto para o prompt
-- Ate 10 acoes das ultimas 24h, mais recentes primeiro, em linhas curtas. Lista de compras fica de fora (so entra no "Desfazer tudo").
CREATE OR REPLACE FUNCTION agente.f_recent_actions_txt(p_user bigint) RETURNS text
LANGUAGE sql STABLE SET search_path TO 'agente', 'public' AS $$
  SELECT string_agg(
           '[' || s.id || '] ' ||
           CASE s.kind WHEN 'reminder' THEN 'lembrete' WHEN 'event' THEN 'compromisso' WHEN 'expense' THEN 'gasto'
                       WHEN 'note' THEN 'nota' WHEN 'task' THEN 'tarefa' ELSE s.kind END ||
           ': ' || s.label || ' (ha ' ||
           CASE WHEN now() - s.created_at < interval '60 minutes' THEN greatest(1, floor(extract(epoch FROM now() - s.created_at) / 60)::int) || ' min'
                ELSE floor(extract(epoch FROM now() - s.created_at) / 3600)::int || ' h' END || ')',
           E'\n' ORDER BY s.id DESC)
    FROM (SELECT id, kind, label, created_at FROM agente.recent_actions
           WHERE user_id = p_user AND NOT undone AND kind <> 'list_item' AND created_at > now() - interval '24 hours'
           ORDER BY id DESC LIMIT 10) s
$$;

-- ---------------------------------------------------------------- acoes extras (varias acoes na mesma mensagem), so banco
-- p_acts = [{kind: reminder|expense|note|list|supply, title, due_iso, lead, amount, list_name, items}]
-- devolve {lines: [...texto do que foi feito...], fails: [...texto do que falhou...]}
CREATE OR REPLACE FUNCTION agente.f_multi_db(p_user bigint, p_acts jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  a jsonb; k text; tz text; v_lines jsonb := '[]'::jsonb; v_fails jsonb := '[]'::jsonb; res jsonb; t text; due timestamptz; v_title text; v_lead int; lab text;
BEGIN
  SELECT coalesce(nullif(timezone, ''), 'America/Sao_Paulo') INTO tz FROM users WHERE id = p_user;
  FOR a IN SELECT * FROM jsonb_array_elements(coalesce(p_acts, '[]'::jsonb)) LOOP
    k := a->>'kind'; v_title := btrim(coalesce(a->>'title', '')); t := NULL;
    BEGIN
      IF k = 'reminder' THEN
        due := (a->>'due_iso')::timestamptz;
        v_lead := nullif(a->>'lead', '')::int;
        res := f_reminder_create_ex(p_user, v_title, due, false, v_lead, 'text', '{"freq":"","until":"","count":""}'::jsonb);
        lab := CASE WHEN coalesce(v_lead, 0) >= 1440 AND v_lead % 1440 = 0 THEN ' (aviso ' || (v_lead / 1440) || ' dia(s) antes)'
                    WHEN coalesce(v_lead, 0) >= 60 AND v_lead % 60 = 0 THEN ' (aviso ' || (v_lead / 60) || 'h antes)'
                    WHEN coalesce(v_lead, 0) > 0 THEN ' (aviso ' || v_lead || ' min antes)' ELSE '' END;
        t := CASE WHEN coalesce((res->>'duplicate')::boolean, false) THEN 'Lembrete que já existia: ' ELSE 'Lembrete: ' END
             || v_title || ', ' || to_char(due AT TIME ZONE tz, 'DD/MM "às" HH24:MI') || lab;
      ELSIF k = 'expense' THEN
        res := f_fin(p_user, jsonb_build_object('action', 'add', 'kind', 'expense', 'amount', (a->>'amount')::numeric, 'title', v_title,
                 'category', '', 'category_stated', false, 'method', '', 'installments', 1, 'paid', true, 'date', '', 'recurring_day', NULL,
                 'person', '', 'period', 'current', 'keywords', '', 'budget_amount', NULL, 'closing_day', NULL, 'card', '',
                 'card_closing_day', NULL, 'card_due_day', NULL, 'card_limit', NULL, 'month', '', 'alert_days', NULL, 'report_format', '',
                 'items', '[]'::jsonb, 'source', 'text', 'reply', ''));
        t := nullif(btrim(split_part(coalesce(res->>'text', ''), E'\n', 1)), '');
        IF t IS NULL THEN RAISE EXCEPTION 'sem texto'; END IF;
      ELSIF k = 'note' THEN
        res := f_notes(p_user, jsonb_build_object('note_action', 'save', 'note_text', v_title, 'note_query', '', 'text', v_title));
        t := nullif(btrim(split_part(coalesce(res->>'text', ''), E'\n', 1)), '');
        IF t IS NULL THEN RAISE EXCEPTION 'sem texto'; END IF;
      ELSIF k = 'list' THEN
        res := f_lists(p_user, jsonb_build_object('list_action', 'add', 'list_name', coalesce(a->>'list_name', ''),
                 'list_items', coalesce(a->'items', '[]'::jsonb), 'text', v_title));
        t := nullif(btrim(split_part(coalesce(res->>'text', ''), E'\n', 1)), '');
        IF t IS NULL THEN RAISE EXCEPTION 'sem texto'; END IF;
      ELSIF k = 'supply' THEN
        res := f_supply_taken(p_user, v_title);
        IF coalesce((res->>'found')::boolean, false) THEN
          t := 'Anotado: tomou ' || coalesce(res->>'item', v_title);
        ELSE
          v_fails := v_fails || to_jsonb('Não achei o item "' || v_title || '" para marcar como tomado.');
          CONTINUE;
        END IF;
      ELSE
        CONTINUE;
      END IF;
      v_lines := v_lines || to_jsonb(t);
    EXCEPTION WHEN others THEN
      v_fails := v_fails || to_jsonb('Não consegui registrar "' || left(v_title, 60) || '".');
    END;
  END LOOP;
  RETURN jsonb_build_object('lines', v_lines, 'fails', v_fails);
END $$;

-- Compromissos extras: o Google ja foi chamado pelo workflow. p_items = [{req: {...como f_agenda_after_create...}, result: {...resposta do sub-workflow...}}]
CREATE OR REPLACE FUNCTION agente.f_multi_events(p_user bigint, p_items jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  it jsonb; rq jsonb; rs jsonb; tz text; v_lines jsonb := '[]'::jsonb; v_fails jsonb := '[]'::jsonb; v_title text; v_due timestamptz; conf text; out_r jsonb;
BEGIN
  SELECT coalesce(nullif(timezone, ''), 'America/Sao_Paulo') INTO tz FROM users WHERE id = p_user;
  FOR it IN SELECT * FROM jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) LOOP
    rq := it->'req'; rs := coalesce(it->'result', '{}'::jsonb); v_title := coalesce(rq->>'title', ''); v_due := (rq->>'due_iso')::timestamptz;
    BEGIN
      IF coalesce(rs->>'ok', '') <> 'true' THEN
        v_fails := v_fails || to_jsonb('Não consegui marcar "' || left(v_title, 60) || '" no Google Agenda'
                     || CASE WHEN jsonb_typeof(rs->'error') = 'string' THEN ' (' || left(rs->>'error', 100) || ')' ELSE '' END || '.');
      ELSIF coalesce(rs->>'conflict', '') = 'true' THEN
        SELECT string_agg(c->>'title', ', ') INTO conf FROM jsonb_array_elements(coalesce(rs->'conflicts', '[]'::jsonb)) c;
        v_fails := v_fails || to_jsonb('Não marquei "' || left(v_title, 60) || '" (' || to_char(v_due AT TIME ZONE tz, 'DD/MM "às" HH24:MI')
                     || '): conflita com ' || coalesce(conf, 'outro compromisso') || '. Me peça ele sozinho que eu pergunto se marco mesmo assim.');
      ELSE
        out_r := f_agenda_after_create(p_user, rq, rs);
        v_lines := v_lines || to_jsonb('Compromisso: ' || v_title || ', ' || to_char(v_due AT TIME ZONE tz, 'DD/MM "às" HH24:MI')
                     || CASE WHEN coalesce(rq->>'location', '') <> '' THEN ' em ' || (rq->>'location') ELSE '' END);
        IF out_r ? 'err' THEN
          v_fails := v_fails || to_jsonb('"' || left(v_title, 60) || '" foi para o Google, mas deu problema nos avisos daqui.');
        END IF;
      END IF;
    EXCEPTION WHEN others THEN
      v_fails := v_fails || to_jsonb('Não consegui registrar "' || left(v_title, 60) || '".');
    END;
  END LOOP;
  RETURN jsonb_build_object('lines', v_lines, 'fails', v_fails);
END $$;

-- Tarefas extras (Google Tarefas): o workflow ja criou. p_items = [{title, due, calendar_key, result: {id, ...} | {not_connected: true}}]
CREATE OR REPLACE FUNCTION agente.f_multi_tasks(p_user bigint, p_items jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE it jsonb; v_lines jsonb := '[]'::jsonb; v_fails jsonb := '[]'::jsonb; v_title text; v_id text;
BEGIN
  FOR it IN SELECT * FROM jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) LOOP
    v_title := coalesce(it->>'title', ''); v_id := coalesce(it->'result'->>'id', '');
    IF v_id <> '' THEN
      PERFORM f_ra_log(p_user, 'task', NULL, v_id, it->>'calendar_key', v_title || CASE WHEN coalesce(it->>'due', '') <> '' THEN ', para ' || to_char((it->>'due')::date, 'DD/MM') ELSE '' END);
      v_lines := v_lines || to_jsonb('Tarefa: ' || v_title || CASE WHEN coalesce(it->>'due', '') <> '' THEN ', para ' || to_char((it->>'due')::date, 'DD/MM') ELSE '' END);
    ELSE
      v_fails := v_fails || to_jsonb('Não consegui criar a tarefa "' || left(v_title, 60) || '"'
                   || CASE WHEN coalesce(it->'result'->>'not_connected', '') = 'true' THEN ' (sua conta do Google Tarefas não está conectada)' ELSE '' END || '.');
    END IF;
  END LOOP;
  RETURN jsonb_build_object('lines', v_lines, 'fails', v_fails);
END $$;

-- ---------------------------------------------------------------- Desfazer tudo (botao mu:<lote>)
-- Desfaz no banco o que o lote criou e devolve cals = compromissos a apagar no Google (o workflow chama o sub-workflow de agenda).
CREATE OR REPLACE FUNCTION agente.f_batch_undo(p_user bigint, p_batch bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  ra recent_actions%ROWTYPE; v_done text := ''; v_manual text := ''; v_cals jsonb := '[]'::jsonb; n int := 0; nl text := E'\n'; v_text text;
BEGIN
  IF p_batch IS NULL THEN RETURN jsonb_build_object('text', 'Não achei o que desfazer.', 'kb', 'none', 'rid', 0); END IF;
  FOR ra IN SELECT * FROM recent_actions WHERE user_id = p_user AND batch_id = p_batch AND NOT undone ORDER BY id DESC LOOP
    BEGIN
      IF ra.kind = 'reminder' THEN
        UPDATE reminders SET status = 'cancelled' WHERE id = ra.ref_id AND user_id = p_user;
        UPDATE notifications SET state = 'cancelled' WHERE reminder_id = ra.ref_id AND state = 'pending';
      ELSIF ra.kind = 'event' THEN
        UPDATE reminders SET status = 'cancelled' WHERE user_id = p_user AND calendar_event_id = ra.ref_text AND status IN ('pending', 'awaiting_time');
        UPDATE notifications SET state = 'cancelled' WHERE state = 'pending' AND reminder_id IN (SELECT id FROM reminders WHERE user_id = p_user AND calendar_event_id = ra.ref_text);
        UPDATE agenda_series SET active = false WHERE user_id = p_user AND calendar_event_id = ra.ref_text;
        v_cals := v_cals || jsonb_build_array(jsonb_build_object('op', 'delete', 'calendar_key', coalesce(ra.calendar_key, ''), 'event_id', ra.ref_text, 'title', ra.label));
      ELSIF ra.kind = 'expense' THEN
        PERFORM f_callback(p_user, 'fundo:' || ra.ref_id);
      ELSIF ra.kind = 'note' THEN
        DELETE FROM notes WHERE id = ra.ref_id AND user_id = p_user;
      ELSIF ra.kind = 'list_item' THEN
        DELETE FROM list_items WHERE id = ra.ref_id AND user_id = p_user;
      ELSIF ra.kind = 'task' THEN
        v_manual := v_manual || nl || '- tarefa: ' || ra.label;
        CONTINUE;
      END IF;
      UPDATE recent_actions SET undone = true WHERE id = ra.id;
      IF ra.kind <> 'list_item' THEN
        v_done := v_done || nl || '- ' || CASE ra.kind WHEN 'reminder' THEN 'lembrete' WHEN 'event' THEN 'compromisso' WHEN 'expense' THEN 'gasto' WHEN 'note' THEN 'nota' ELSE ra.kind END || ': ' || ra.label;
      ELSE
        n := n + 1;
      END IF;
    EXCEPTION WHEN others THEN
      v_manual := v_manual || nl || '- ' || ra.label || ' (deu erro; confira)';
    END;
  END LOOP;
  IF v_done = '' AND n = 0 AND v_manual = '' THEN
    RETURN jsonb_build_object('text', 'Isso já foi desfeito (ou não tem mais nada desse pedido para desfazer).', 'kb', 'none', 'rid', 0);
  END IF;
  v_text := 'Desfeito:' || v_done || CASE WHEN n > 0 THEN nl || '- ' || n || ' item(ns) de lista' ELSE '' END;
  IF v_done = '' AND n = 0 THEN v_text := 'Não consegui desfazer tudo.'; END IF;
  IF v_manual <> '' THEN
    v_text := v_text || nl || nl || 'Estes eu não consigo desfazer daqui (apague no app do Google se quiser):' || v_manual;
  END IF;
  RETURN jsonb_build_object('text', v_text, 'kb', 'none', 'rid', 0) || CASE WHEN jsonb_array_length(v_cals) > 0 THEN jsonb_build_object('cals', v_cals) ELSE '{}'::jsonb END;
END $$;

-- ---------------------------------------------------------------- correcao por texto (lembrete e nota; compromisso e gasto usam manage_event e finance)
-- p = {recent_id, title, date (YYYY-MM-DD ou ''), time (HH:MM ou ''), note_text}
CREATE OR REPLACE FUNCTION agente.f_recent_correct(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  ra recent_actions%ROWTYPE; r reminders%ROWTYPE; tz text; v_title text; v_date date; v_time time; v_due timestamptz; offs int[]; o int; v_note text;
BEGIN
  SELECT coalesce(nullif(timezone, ''), 'America/Sao_Paulo') INTO tz FROM users WHERE id = p_user;
  SELECT * INTO ra FROM recent_actions
   WHERE id = CASE WHEN coalesce(p->>'recent_id', '') ~ '^[0-9]+$' THEN (p->>'recent_id')::bigint END AND user_id = p_user AND NOT undone;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('text', 'Não achei essa ação entre as últimas. Me diz o nome do que você quer corrigir.', 'kb', 'none', 'rid', 0);
  END IF;

  IF ra.kind = 'reminder' THEN
    SELECT * INTO r FROM reminders WHERE id = ra.ref_id AND user_id = p_user;
    IF NOT FOUND OR r.status NOT IN ('pending', 'awaiting_time') THEN
      RETURN jsonb_build_object('text', 'Esse lembrete já foi concluído ou cancelado. Quer que eu crie outro?', 'kb', 'none', 'rid', 0);
    END IF;
    v_title := coalesce(nullif(btrim(p->>'title'), ''), r.title);
    v_due := r.due_at;
    IF coalesce(p->>'date', '') <> '' OR coalesce(p->>'time', '') <> '' THEN
      v_date := coalesce(nullif(p->>'date', '')::date, (r.due_at AT TIME ZONE tz)::date);
      v_time := coalesce(nullif(p->>'time', '')::time, (r.due_at AT TIME ZONE tz)::time);
      IF v_date IS NULL OR v_time IS NULL THEN
        RETURN jsonb_build_object('text', 'Me diga a data e a hora certas do lembrete.', 'kb', 'none', 'rid', 0);
      END IF;
      v_due := (v_date + v_time) AT TIME ZONE tz;
      IF v_due <= now() THEN
        RETURN jsonb_build_object('text', 'Esse horário já passou. Para quando eu mudo?', 'kb', 'none', 'rid', 0);
      END IF;
    END IF;
    UPDATE reminders SET title = v_title, due_at = v_due, status = 'pending' WHERE id = r.id;
    IF v_due IS DISTINCT FROM r.due_at THEN
      SELECT array_agg(DISTINCT offset_minutes) INTO offs FROM notifications WHERE reminder_id = r.id AND type = 'pre_alert' AND offset_minutes IS NOT NULL;
      UPDATE notifications SET state = 'cancelled' WHERE reminder_id = r.id AND state = 'pending';
      INSERT INTO notifications(user_id, reminder_id, type, fire_at) VALUES (p_user, r.id, 'reminder', v_due);
      FOREACH o IN ARRAY coalesce(offs, ARRAY[]::int[]) LOOP
        IF o > 0 AND v_due - make_interval(mins => o) > now() THEN
          INSERT INTO notifications(user_id, reminder_id, type, fire_at, offset_minutes) VALUES (p_user, r.id, 'pre_alert', v_due - make_interval(mins => o), o);
        END IF;
      END LOOP;
    END IF;
    UPDATE recent_actions SET label = left(v_title || ', ' || to_char(v_due AT TIME ZONE tz, 'DD/MM HH24:MI'), 120) WHERE id = ra.id;
    RETURN jsonb_build_object('text', 'Corrigido: ' || v_title || ', ' || to_char(v_due AT TIME ZONE tz, 'DD/MM "às" HH24:MI') || '.', 'kb', 'none', 'rid', 0);

  ELSIF ra.kind = 'note' THEN
    v_note := btrim(coalesce(p->>'note_text', ''));
    IF f_norm(v_note) = '' THEN
      RETURN jsonb_build_object('text', 'Como a nota deve ficar?', 'kb', 'none', 'rid', 0);
    END IF;
    v_note := left(v_note, 4000);
    UPDATE notes SET body = v_note, body_norm = f_norm(v_note) WHERE id = ra.ref_id AND user_id = p_user;
    UPDATE recent_actions SET label = left(v_note, 70) WHERE id = ra.id;
    RETURN jsonb_build_object('text', 'Nota corrigida: "' || left(v_note, 100) || '".', 'kb', 'none', 'rid', 0);

  ELSIF ra.kind = 'event' THEN
    RETURN jsonb_build_object('text', 'Para mudar um compromisso eu confirmo com você antes. Diga, por exemplo: "muda ' || left(ra.label, 40) || ' para as 10h".', 'kb', 'none', 'rid', 0);
  ELSIF ra.kind = 'expense' THEN
    RETURN jsonb_build_object('text', 'Para corrigir um gasto diga, por exemplo: "corrige o gasto do mercado para 50".', 'kb', 'none', 'rid', 0);
  END IF;
  RETURN jsonb_build_object('text', 'Tarefa do Google eu ainda não altero. Quer que eu crie outra com o texto certo? A antiga você apaga no app.', 'kb', 'none', 'rid', 0);
END $$;

-- ---------------------------------------------------------------- despachante: prefixo mu* (Desfazer tudo)
DO $do$
BEGIN
  IF to_regproc('agente.f_callback_pre_f10') IS NULL THEN
    ALTER FUNCTION agente.f_callback(bigint, text) RENAME TO f_callback_pre_f10;
  END IF;
END $do$;

CREATE OR REPLACE FUNCTION agente.f_callback(p_user bigint, p_data text) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
BEGIN
  IF split_part(p_data, ':', 1) = 'mu' AND split_part(p_data, ':', 2) ~ '^[0-9]+$' THEN
    RETURN f_batch_undo(p_user, split_part(p_data, ':', 2)::bigint);
  END IF;
  RETURN f_callback_pre_f10(p_user, p_data);
END $$;
