-- Assessor (PRD secao 8, "RLS"): o banco garante o isolamento entre usuarios. Idempotente. NAO aplicado em producao.
--
-- Papeis:
--   luna_app   : usado pelo servico em nome de UM usuario. Cada transacao faz SET LOCAL app.user_id = <id>.
--                So enxerga e grava linhas desse usuario.
--   luna_sched : usado so pelo agendador (resumos, notificacoes, Vigia de todos os usuarios). Enxerga tudo.
-- O dono das tabelas (a role que o n8n usa hoje) nao e afetado: RLS nao se aplica ao dono.
-- As roles nascem sem login; quem opera define a senha: ALTER ROLE luna_app LOGIN PASSWORD '...'.
SET search_path = agente, public;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'luna_app') THEN CREATE ROLE luna_app NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'luna_sched') THEN CREATE ROLE luna_sched NOLOGIN; END IF;
END $$;

CREATE OR REPLACE FUNCTION f_app_user() RETURNS bigint
LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('app.user_id', true), '')::bigint $$;

GRANT USAGE ON SCHEMA agente TO luna_app, luna_sched;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA agente TO luna_app, luna_sched;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA agente TO luna_app, luna_sched;
ALTER DEFAULT PRIVILEGES IN SCHEMA agente GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO luna_app, luna_sched;
ALTER DEFAULT PRIVILEGES IN SCHEMA agente GRANT USAGE, SELECT ON SEQUENCES TO luna_app, luna_sched;

-- tabelas globais: o servico so le; convites e visoes internas ficam fora do alcance do luna_app
REVOKE INSERT, UPDATE, DELETE ON ai_pricing, plans, ai_model_roles FROM luna_app;
REVOKE ALL ON invite_codes FROM luna_app;
REVOKE ALL ON v_assessor_margem, v_assessor_confirmacao, v_insight_regras, v_custo_modelo FROM luna_app;

-- visoes passam a respeitar o RLS de quem consulta (sem isso rodariam com os direitos do dono)
ALTER VIEW supplies_status SET (security_invoker = true);
ALTER VIEW v_pessoas SET (security_invoker = true);
ALTER VIEW v_lugares SET (security_invoker = true);
ALTER VIEW v_assessor_margem SET (security_invoker = true);
ALTER VIEW v_assessor_confirmacao SET (security_invoker = true);
ALTER VIEW v_insight_regras SET (security_invoker = true);
ALTER VIEW v_custo_modelo SET (security_invoker = true);

-- politica em toda tabela com user_id (inclusive as futuras: rode esta migracao de novo depois de criar tabela)
CREATE OR REPLACE FUNCTION f_rls_apply() RETURNS integer
LANGUAGE plpgsql SET search_path = agente, public AS $$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN SELECT tabela FROM f_user_tables() LOOP
    EXECUTE format('ALTER TABLE agente.%I ENABLE ROW LEVEL SECURITY', r.tabela);
    EXECUTE format('DROP POLICY IF EXISTS luna_app_isolamento ON agente.%I', r.tabela);
    EXECUTE format('CREATE POLICY luna_app_isolamento ON agente.%I FOR ALL TO luna_app USING (user_id = agente.f_app_user()) WITH CHECK (user_id = agente.f_app_user())', r.tabela);
    EXECUTE format('DROP POLICY IF EXISTS luna_sched_tudo ON agente.%I', r.tabela);
    EXECUTE format('CREATE POLICY luna_sched_tudo ON agente.%I FOR ALL TO luna_sched USING (true) WITH CHECK (true)', r.tabela);
    n := n + 1;
  END LOOP;
  RETURN n;
END $$;
SELECT f_rls_apply();

-- users: cada um ve so a propria linha
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS luna_app_isolamento ON users;
CREATE POLICY luna_app_isolamento ON users FOR ALL TO luna_app USING (id = f_app_user()) WITH CHECK (id = f_app_user());
DROP POLICY IF EXISTS luna_sched_tudo ON users;
CREATE POLICY luna_sched_tudo ON users FOR ALL TO luna_sched USING (true) WITH CHECK (true);

-- tabelas filhas sem user_id: isolamento pela tabela mae
ALTER TABLE contact_group_members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS luna_app_isolamento ON contact_group_members;
CREATE POLICY luna_app_isolamento ON contact_group_members FOR ALL TO luna_app
  USING (EXISTS (SELECT 1 FROM contact_groups g WHERE g.id = group_id AND g.user_id = f_app_user()))
  WITH CHECK (EXISTS (SELECT 1 FROM contact_groups g WHERE g.id = group_id AND g.user_id = f_app_user()));
DROP POLICY IF EXISTS luna_sched_tudo ON contact_group_members;
CREATE POLICY luna_sched_tudo ON contact_group_members FOR ALL TO luna_sched USING (true) WITH CHECK (true);

ALTER TABLE fin_goal_deposits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS luna_app_isolamento ON fin_goal_deposits;
CREATE POLICY luna_app_isolamento ON fin_goal_deposits FOR ALL TO luna_app
  USING (EXISTS (SELECT 1 FROM fin_goals g WHERE g.id = goal_id AND g.user_id = f_app_user()))
  WITH CHECK (EXISTS (SELECT 1 FROM fin_goals g WHERE g.id = goal_id AND g.user_id = f_app_user()));
DROP POLICY IF EXISTS luna_sched_tudo ON fin_goal_deposits;
CREATE POLICY luna_sched_tudo ON fin_goal_deposits FOR ALL TO luna_sched USING (true) WITH CHECK (true);

-- ---------- portas de entrada (SECURITY DEFINER, estreitas) ----------
-- O luna_app nao pode listar usuarios; a identidade e o cadastro passam por estas duas funcoes.
CREATE OR REPLACE FUNCTION f_channel_user(p_canal text, p_id_externo text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agente, public AS $$
  SELECT jsonb_build_object('id', u.id, 'status', u.status)
    FROM user_channels c JOIN users u ON u.id = c.user_id
   WHERE c.canal = p_canal AND c.id_externo = p_id_externo
$$;

CREATE OR REPLACE FUNCTION f_signup(p_canal text, p_id_externo text, p_nome text, p_codigo text, p_exige_convite boolean DEFAULT true) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agente, public AS $$
DECLARE v_id bigint; v_cod text := upper(btrim(coalesce(p_codigo, '')));
BEGIN
  IF EXISTS (SELECT 1 FROM user_channels WHERE canal = p_canal AND id_externo = p_id_externo) THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'ja_cadastrado');
  END IF;
  -- users.telegram_id ainda e obrigatorio (as funcoes de disparo enviam por ele): o id externo precisa ser numerico
  IF p_id_externo !~ '^[0-9]{1,18}$' THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'canal');
  END IF;
  IF p_exige_convite THEN
    PERFORM 1 FROM invite_codes WHERE codigo = v_cod AND usado_por IS NULL FOR UPDATE;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'motivo', 'convite'); END IF;
  END IF;
  INSERT INTO users (telegram_id, name, onboarding_step, papel)
  VALUES (p_id_externo::bigint, left(coalesce(nullif(btrim(p_nome), ''), 'Você'), 60), 'aceite', 'cliente') RETURNING id INTO v_id;
  INSERT INTO user_channels (user_id, canal, id_externo) VALUES (v_id, p_canal, p_id_externo);
  IF p_exige_convite THEN
    UPDATE invite_codes SET usado_por = v_id, usado_em = now() WHERE codigo = v_cod;
  END IF;
  RETURN jsonb_build_object('ok', true, 'user_id', v_id);
END $$;

-- troca de state do OAuth: uso unico, validade de 15 minutos; devolve o usuario dono do state
CREATE OR REPLACE FUNCTION f_oauth_state_use(p_state text) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agente, public AS $$
DECLARE v_user bigint;
BEGIN
  UPDATE oauth_states SET usado_em = now()
   WHERE state = p_state AND usado_em IS NULL AND criado_em > now() - interval '15 minutes' RETURNING user_id INTO v_user;
  RETURN v_user;
END $$;

REVOKE ALL ON FUNCTION f_channel_user(text, text), f_signup(text, text, text, text, boolean), f_oauth_state_use(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION f_channel_user(text, text), f_signup(text, text, text, text, boolean), f_oauth_state_use(text) TO luna_app, luna_sched;
