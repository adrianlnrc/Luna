-- M4 (onda 2): custo de IA (/custo) e lembretes anuais.
-- Idempotente. Wrappers criados so na primeira aplicacao (renomeia a funcao viva para *_pre_m4 / *_base e embrulha),
-- para nao sobrescrever wrappers de outros modulos se este arquivo for reaplicado.
-- Fonte dos precos: https://developers.openai.com/api/docs/pricing (padrao, contexto curto), consultada em 01/11/2026.
-- Cambio: AwesomeAPI USD-BRL (bid 5,4397 em 30/10/2026). Se o M5 ja criou ai_pricing (cambio 5,342 PTAX), os valores dele ficam (DO NOTHING).
-- Tudo configuravel: UPDATE ai_pricing.
SET search_path TO agente, public;

-- ---------- 1) tabelas ----------
CREATE TABLE IF NOT EXISTS ai_usage (
  id         bigserial PRIMARY KEY,
  user_id    bigint NOT NULL REFERENCES users(id),
  day        date NOT NULL,
  kind       text NOT NULL,                 -- texto | foto | voz | pdf | pesquisa
  model      text NOT NULL,
  tokens_in  integer NOT NULL DEFAULT 0,
  tokens_out integer NOT NULL DEFAULT 0,
  estimated  boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE ai_usage ADD COLUMN IF NOT EXISTS estimated boolean NOT NULL DEFAULT false;
-- extra_usd: custo extra da chamada em dolar (ex.: taxa da busca na web do M5), somado ao custo dos tokens
ALTER TABLE ai_usage ADD COLUMN IF NOT EXISTS extra_usd numeric NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS ai_usage_user_day_idx ON ai_usage (user_id, day);

CREATE TABLE IF NOT EXISTS ai_pricing (
  model          text PRIMARY KEY,
  usd_per_1m_in  numeric(12,4) NOT NULL,
  usd_per_1m_out numeric(12,4) NOT NULL,
  usd_brl        numeric(8,4)  NOT NULL,
  source         text,
  updated_at     timestamptz NOT NULL DEFAULT now()
);

INSERT INTO ai_pricing (model, usd_per_1m_in, usd_per_1m_out, usd_brl, source) VALUES
  ('gpt-6-luna',   0.10,  0.50, 5.4397, 'OpenAI developers.openai.com/api/docs/pricing (standard, 01/11/2026); dolar AwesomeAPI 30/10/2026'),
  ('gpt-6.1-sol',  2.00, 10.00, 5.4397, 'OpenAI developers.openai.com/api/docs/pricing (standard, 01/11/2026); dolar AwesomeAPI 30/10/2026')
ON CONFLICT (model) DO NOTHING;

-- ---------- 2) registro de uso ----------
CREATE OR REPLACE FUNCTION f_ai_log(p_user bigint, p_kind text, p_model text, p_in integer, p_out integer, p_est boolean DEFAULT false)
RETURNS bigint LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE tz text; v_id bigint;
BEGIN
  IF p_user IS NULL OR (p_in IS NULL AND p_out IS NULL) THEN RETURN NULL; END IF;
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  IF NOT FOUND THEN RETURN NULL; END IF;
  INSERT INTO ai_usage (user_id, day, kind, model, tokens_in, tokens_out, estimated)
  VALUES (p_user, (now() AT TIME ZONE coalesce(tz, 'America/Sao_Paulo'))::date, coalesce(nullif(btrim(p_kind), ''), 'texto'),
          coalesce(nullif(btrim(p_model), ''), 'desconhecido'), greatest(coalesce(p_in, 0), 0), greatest(coalesce(p_out, 0), 0), coalesce(p_est, false))
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- ---------- 3) formatacao e texto do /custo ----------
CREATE OR REPLACE FUNCTION f_ai_brl(p numeric) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT 'R$ ' || replace(CASE WHEN abs(coalesce(p, 0)) >= 1 THEN to_char(coalesce(p, 0), 'FM999999990.00') ELSE to_char(coalesce(p, 0), 'FM990.0000') END, '.', ',')
$$;

CREATE OR REPLACE FUNCTION f_ai_num(p numeric) RETURNS text
LANGUAGE sql IMMUTABLE AS $$ SELECT replace(to_char(coalesce(p, 0), 'FM999,999,999,990'), ',', '.') $$;

CREATE OR REPLACE FUNCTION f_ai_cost_text(p_user bigint) RETURNS text
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE
  tz text; hoje date; ini date; fim date; dias_mes integer; decorridos integer;
  NL text := chr(10); t text; r record;
  c_hoje numeric; n_hoje integer; c_mes numeric; n_mes integer; ti_mes bigint; to_mes bigint; sem_preco integer; est integer;
  proj numeric; modelo text; pr ai_pricing%ROWTYPE;
  meses text[] := ARRAY['janeiro','fevereiro','março','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro'];
  rot text; v_rate numeric;
BEGIN
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  IF NOT FOUND THEN RETURN 'Não achei o seu cadastro.'; END IF;
  SELECT usd_brl INTO v_rate FROM ai_pricing ORDER BY updated_at DESC LIMIT 1;
  v_rate := coalesce(v_rate, 5.5);
  hoje := (now() AT TIME ZONE coalesce(tz, 'America/Sao_Paulo'))::date;
  ini := date_trunc('month', hoje)::date;
  fim := (ini + interval '1 month')::date;
  dias_mes := fim - ini;
  decorridos := hoje - ini + 1;

  SELECT count(*), coalesce(sum((coalesce(u.tokens_in * p.usd_per_1m_in + u.tokens_out * p.usd_per_1m_out, 0) / 1000000.0 + coalesce(u.extra_usd, 0)) * coalesce(p.usd_brl, v_rate)), 0)
    INTO n_hoje, c_hoje
    FROM ai_usage u LEFT JOIN ai_pricing p ON p.model = u.model WHERE u.user_id = p_user AND u.day = hoje;
  SELECT count(*), coalesce(sum((coalesce(u.tokens_in * p.usd_per_1m_in + u.tokens_out * p.usd_per_1m_out, 0) / 1000000.0 + coalesce(u.extra_usd, 0)) * coalesce(p.usd_brl, v_rate)), 0),
         coalesce(sum(u.tokens_in), 0), coalesce(sum(u.tokens_out), 0),
         count(*) FILTER (WHERE p.model IS NULL AND u.tokens_in + u.tokens_out > 0), count(*) FILTER (WHERE u.estimated)
    INTO n_mes, c_mes, ti_mes, to_mes, sem_preco, est
    FROM ai_usage u LEFT JOIN ai_pricing p ON p.model = u.model WHERE u.user_id = p_user AND u.day >= ini AND u.day < fim;

  IF n_mes = 0 THEN
    RETURN 'Custo de IA (estimativa)' || NL || 'Ainda não registrei nenhuma chamada de IA para você neste mês. O registro começa quando você me manda mensagens (texto, áudio, foto ou PDF).';
  END IF;

  t := 'Custo de IA (estimativa)' || NL
    || 'Hoje: ' || f_ai_brl(c_hoje) || ' (' || n_hoje || CASE WHEN n_hoje = 1 THEN ' chamada)' ELSE ' chamadas)' END || NL
    || 'Em ' || meses[extract(month FROM hoje)::int] || ': ' || f_ai_brl(c_mes) || ' (' || n_mes || CASE WHEN n_mes = 1 THEN ' chamada; ' ELSE ' chamadas; ' END || f_ai_num(ti_mes) || ' tokens de entrada e ' || f_ai_num(to_mes) || ' de saída)' || NL
    || NL || 'Por tipo, no mês:';
  FOR r IN
    SELECT u.kind, count(*) AS n, sum(u.tokens_in) AS ti, sum(u.tokens_out) AS tout,
           coalesce(sum((coalesce(u.tokens_in * p.usd_per_1m_in + u.tokens_out * p.usd_per_1m_out, 0) / 1000000.0 + coalesce(u.extra_usd, 0)) * coalesce(p.usd_brl, v_rate)), 0) AS custo
      FROM ai_usage u LEFT JOIN ai_pricing p ON p.model = u.model
     WHERE u.user_id = p_user AND u.day >= ini AND u.day < fim
     GROUP BY u.kind ORDER BY custo DESC, n DESC
  LOOP
    rot := CASE r.kind WHEN 'texto' THEN 'texto' WHEN 'foto' THEN 'foto' WHEN 'voz' THEN 'voz' WHEN 'pdf' THEN 'PDF' WHEN 'pesquisa' THEN 'pesquisa' ELSE r.kind END;
    t := t || NL || '- ' || rot || ': ' || r.n || CASE WHEN r.n = 1 THEN ' chamada, ' ELSE ' chamadas, ' END || f_ai_num(r.ti + r.tout) || ' tokens, ' || f_ai_brl(r.custo);
  END LOOP;

  IF decorridos >= 1 THEN
    proj := c_mes / decorridos * dias_mes;
    t := t || NL || NL || 'Projeção para o mês todo (pela média até agora): ' || f_ai_brl(proj);
  END IF;

  SELECT u.model INTO modelo FROM ai_usage u WHERE u.user_id = p_user AND u.day >= ini AND u.day < fim
   GROUP BY u.model ORDER BY count(*) DESC LIMIT 1;
  SELECT * INTO pr FROM ai_pricing WHERE model = modelo;
  t := t || NL || NL;
  IF FOUND THEN
    t := t || 'Conta feita com o preço público da OpenAI para ' || modelo || ': US$ ' || replace(to_char(pr.usd_per_1m_in, 'FM990.00'), '.', ',')
      || ' por 1 milhão de tokens de entrada e US$ ' || replace(to_char(pr.usd_per_1m_out, 'FM990.00'), '.', ',') || ' de saída, dólar a R$ '
      || replace(to_char(pr.usd_brl, 'FM990.00'), '.', ',') || ' (atualizado em ' || to_char(pr.updated_at AT TIME ZONE coalesce(tz, 'America/Sao_Paulo'), 'DD/MM/YYYY') || ').';
  ELSE
    t := t || 'O modelo ' || coalesce(modelo, '?') || ' não tem preço cadastrado, então mostro só os tokens.';
  END IF;
  t := t || NL || 'É uma estimativa: não inclui a transcrição de áudio'
    || CASE WHEN sem_preco > 0 THEN ' e ' || sem_preco || CASE WHEN sem_preco = 1 THEN ' chamada' ELSE ' chamadas' END || ' sem preço cadastrado ficou fora do valor em reais' ELSE '' END
    || CASE WHEN est > 0 THEN '; ' || est || CASE WHEN est = 1 THEN ' chamada teve' ELSE ' chamadas tiveram' END || ' os tokens estimados pelo tamanho do texto' ELSE '' END || '.';
  RETURN t;
END $$;

-- ---------- 4) /custo no f_command_data (wrapper unico) ----------
DO $do$
BEGIN
  IF to_regproc('agente.f_command_data_pre_m4') IS NULL THEN
    ALTER FUNCTION agente.f_command_data(bigint) RENAME TO f_command_data_pre_m4;
    EXECUTE $f$
      CREATE FUNCTION agente.f_command_data(p_user bigint) RETURNS jsonb
      LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $b$
      BEGIN
        RETURN agente.f_command_data_pre_m4(p_user) || jsonb_build_object('custo', agente.f_ai_cost_text(p_user));
      END $b$ $f$;
  END IF;
END $do$;

-- ---------- 5) lembretes anuais ----------
ALTER TABLE reminders DROP CONSTRAINT IF EXISTS reminders_repeat_rule_chk;
ALTER TABLE reminders ADD CONSTRAINT reminders_repeat_rule_chk
  CHECK (repeat_rule IS NULL OR repeat_rule = ANY (ARRAY['daily','weekly','monthly','yearly']));

-- 5a) criacao: wrapper de f_reminder_create_ex_base (aviso padrao de 15 dias = 21600 min nos anuais)
DO $do$
BEGIN
  IF to_regproc('agente.f_reminder_create_ex_base_pre_m4') IS NULL THEN
    ALTER FUNCTION agente.f_reminder_create_ex_base(bigint, text, timestamptz, boolean, integer, text, jsonb) RENAME TO f_reminder_create_ex_base_pre_m4;
    EXECUTE $f$
      CREATE FUNCTION agente.f_reminder_create_ex_base(p_user bigint, p_title text, p_due timestamptz, p_shared boolean DEFAULT false,
                                                       p_lead integer DEFAULT NULL, p_source text DEFAULT 'text', p_repeat jsonb DEFAULT NULL)
      RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'agente','public' AS $b$
      DECLARE res jsonb; v_until date; v_cnt integer; v_rid bigint; v_grp uuid; tz text; loc timestamp; v_lead integer;
      BEGIN
        IF lower(nullif(p_repeat->>'freq', '')) IS DISTINCT FROM 'yearly' THEN
          RETURN agente.f_reminder_create_ex_base_pre_m4(p_user, p_title, p_due, p_shared, p_lead, p_source, p_repeat);
        END IF;
        v_until := agente.f_safe_date(p_repeat->>'until');
        BEGIN v_cnt := nullif(p_repeat->>'count', '')::int; EXCEPTION WHEN others THEN v_cnt := NULL; END;
        v_lead := coalesce(p_lead, 21600);
        res := agente.f_reminder_create_ex_base_pre_m4(p_user, p_title, p_due, p_shared, v_lead, p_source, NULL);
        v_rid := (res->>'reminder_id')::bigint;
        SELECT shared_group INTO v_grp FROM agente.reminders WHERE id = v_rid;
        UPDATE agente.reminders SET repeat_rule = 'yearly', repeat_until = v_until,
               repeat_left = CASE WHEN v_cnt IS NOT NULL AND v_cnt >= 1 THEN v_cnt - 1 END
         WHERE id = v_rid OR (v_grp IS NOT NULL AND shared_group = v_grp);
        SELECT timezone INTO tz FROM agente.users WHERE id = p_user;
        loc := p_due AT TIME ZONE tz;
        RETURN res || jsonb_build_object('repeat_rule', 'yearly', 'repeat_text',
          'todo ano em ' || to_char(loc, 'DD/MM') || ' às ' || to_char(loc, 'HH24:MI')
          || CASE WHEN v_lead >= 1440 THEN ' (aviso ' || (v_lead / 1440) || ' dias antes)' ELSE '' END
          || CASE WHEN v_until IS NOT NULL THEN ' (até ' || to_char(v_until, 'DD/MM/YYYY') || ')'
                  WHEN v_cnt IS NOT NULL AND v_cnt > 1 THEN ' (' || v_cnt || ' vezes)' ELSE '' END);
      END $b$ $f$;
  END IF;
END $do$;

-- 5b) proxima ocorrencia: f_reminder_advance_yearly (espelha a mensal) + wrapper de f_reminder_advance
CREATE OR REPLACE FUNCTION f_reminder_advance_yearly(p_rid bigint) RETURNS bigint
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $$
DECLARE r reminders%ROWTYPE; root reminders%ROWTYPE; tz text; v_chain bigint; v_loc timestamp; v_nxt timestamptz;
        v_left integer; v_lead integer; v_new bigint; a_mon integer; a_day integer; y integer; d integer; n integer := 0;
BEGIN
  SELECT * INTO r FROM reminders WHERE id = p_rid;
  IF NOT FOUND OR r.repeat_rule IS DISTINCT FROM 'yearly' OR r.status <> 'pending' THEN RETURN NULL; END IF;
  v_chain := coalesce(r.repeat_of, r.id);
  UPDATE notifications SET state = 'cancelled'
   WHERE state = 'pending' AND reminder_id IN (SELECT id FROM reminders WHERE coalesce(repeat_of, id) = v_chain AND id < r.id AND user_id = r.user_id);
  UPDATE reminders SET status = 'done' WHERE coalesce(repeat_of, id) = v_chain AND id < r.id AND user_id = r.user_id AND status = 'pending';
  IF EXISTS (SELECT 1 FROM reminders WHERE coalesce(repeat_of, id) = v_chain AND id > r.id AND user_id = r.user_id AND status = 'pending') THEN RETURN NULL; END IF;
  SELECT timezone INTO tz FROM users WHERE id = r.user_id;
  SELECT * INTO root FROM reminders WHERE id = v_chain;
  a_mon := extract(month FROM (coalesce(root.due_at, r.due_at) AT TIME ZONE tz))::int;
  a_day := extract(day FROM (coalesce(root.due_at, r.due_at) AT TIME ZONE tz))::int;
  v_loc := r.due_at AT TIME ZONE tz;
  v_left := r.repeat_left;
  LOOP
    n := n + 1;
    IF n > 100 THEN RETURN NULL; END IF;
    IF v_left IS NOT NULL AND v_left <= 0 THEN RETURN NULL; END IF;
    y := extract(year FROM v_loc)::int + 1;
    d := least(a_day, extract(day FROM (make_date(y, a_mon, 1) + interval '1 month - 1 day'))::int);
    v_loc := make_date(y, a_mon, d) + v_loc::time;
    v_nxt := v_loc AT TIME ZONE tz;
    IF v_left IS NOT NULL THEN v_left := v_left - 1; END IF;
    EXIT WHEN v_nxt > now();
  END LOOP;
  IF r.repeat_until IS NOT NULL AND v_loc::date > r.repeat_until THEN RETURN NULL; END IF;
  INSERT INTO reminders (user_id, kind, title, due_at, status, shared_group, source, repeat_rule, repeat_until, repeat_left, repeat_of)
  VALUES (r.user_id, 'reminder', r.title, v_nxt, 'pending', r.shared_group, r.source, 'yearly', r.repeat_until, v_left, v_chain)
  RETURNING id INTO v_new;
  INSERT INTO notifications (user_id, reminder_id, type, fire_at) VALUES (r.user_id, v_new, 'reminder', v_nxt);
  SELECT offset_minutes INTO v_lead FROM notifications WHERE reminder_id = r.id AND type = 'pre_alert' ORDER BY id LIMIT 1;
  v_lead := coalesce(v_lead, 21600);
  IF v_lead > 0 AND v_nxt - make_interval(mins => v_lead) > now() THEN
    INSERT INTO notifications (user_id, reminder_id, type, fire_at, offset_minutes)
    VALUES (r.user_id, v_new, 'pre_alert', v_nxt - make_interval(mins => v_lead), v_lead);
  END IF;
  RETURN v_new;
END $$;

DO $do$
BEGIN
  IF to_regproc('agente.f_reminder_advance_base') IS NULL THEN
    ALTER FUNCTION agente.f_reminder_advance(bigint) RENAME TO f_reminder_advance_base;
    EXECUTE $f$
      CREATE FUNCTION agente.f_reminder_advance(p_rid bigint) RETURNS bigint
      LANGUAGE plpgsql SET search_path TO 'agente','public' AS $b$
      BEGIN
        IF EXISTS (SELECT 1 FROM agente.reminders WHERE id = p_rid AND repeat_rule = 'yearly') THEN
          RETURN agente.f_reminder_advance_yearly(p_rid);
        END IF;
        RETURN agente.f_reminder_advance_base(p_rid);
      END $b$ $f$;
  END IF;
END $do$;

-- ---------- 6) menu: /custo em Ajustes e exemplo anual em Lembretes (wrapper unico) ----------
DO $do$
BEGIN
  IF to_regproc('agente.f_menu_pre_m4') IS NULL THEN
    ALTER FUNCTION agente.f_menu(bigint, text) RENAME TO f_menu_pre_m4;
    EXECUTE $f$
      CREATE FUNCTION agente.f_menu(p_user bigint, p_key text) RETURNS jsonb
      LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $b$
      DECLARE r jsonb := agente.f_menu_pre_m4(p_user, p_key); k text := lower(coalesce(btrim(p_key), 'inicio')); t text := r->>'text'; add_ text := ''; pos integer;
      BEGIN
        IF k = 'lembretes' THEN
          add_ := E'\n\nTodo ano:\n- "me lembra todo ano do IPVA em 15/01" (aviso 15 dias antes, sem pedir)\n- "seguro do carro renova dia 10/06, me avisa 15 dias antes"';
        ELSIF k = 'ajustes' THEN
          add_ := E'\n\nCusto da IA:\n- /custo mostra quanto gastei de IA hoje e no mês, por tipo, com a projeção do mês (é uma estimativa)\n- "quanto estou gastando de IA?" também funciona';
        END IF;
        IF add_ <> '' THEN
          pos := position(E'\n\nDica:' IN t);
          IF pos > 0 THEN t := substr(t, 1, pos - 1) || add_ || substr(t, pos); ELSE t := t || add_; END IF;
          r := jsonb_set(r, '{text}', to_jsonb(t));
        END IF;
        RETURN r;
      END $b$ $f$;
  END IF;
END $do$;
