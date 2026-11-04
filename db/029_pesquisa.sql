-- 029_pesquisa.sql: M5 (fase 5): pesquisa com fonte citada e aviso de custo sem bloqueio.
-- Idempotente. Cadeia envolvida (wrapper, nada reescrito):
--   f_menu -> f_menu_pre_m5  (nova area "pesquisa", botao mn:pesquisa; o resto cai na funcao anterior)
-- Tabelas ai_usage e ai_pricing sao do M4 (028): aqui CREATE TABLE IF NOT EXISTS com o MESMO desenho da spec
-- (ai_usage: user_id, day, kind, model, tokens_in, tokens_out, estimated, created_at; ai_pricing: model,
-- usd_per_1m_in, usd_per_1m_out, usd_brl, source, updated_at). Acrescimos do M5, via ADD COLUMN IF NOT EXISTS
-- (o agente de integracao reconcilia com o 028):
--   ai_usage.extra_usd      = taxa por chamada de busca na web (USD) dessa linha; /custo deve somar junto
--   ai_pricing.usd_per_call = taxa por chamada de ferramenta (linha model='tool:web_search')
-- kind da pesquisa = 'pesquisa'.
-- Funcoes novas: f_research_gate (limite de 3 por minuto + reserva da linha de uso), f_research_log (grava tokens,
-- calcula o custo estimado da pesquisa, do dia e do mes).

SET search_path TO agente, public;

CREATE TABLE IF NOT EXISTS agente.ai_usage (
  id          bigserial PRIMARY KEY,
  user_id     bigint NOT NULL REFERENCES agente.users(id) ON DELETE CASCADE,
  day         date NOT NULL DEFAULT current_date,
  kind        text NOT NULL,
  model       text,
  tokens_in   integer NOT NULL DEFAULT 0,
  tokens_out  integer NOT NULL DEFAULT 0,
  estimated   boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE agente.ai_usage ADD COLUMN IF NOT EXISTS extra_usd numeric NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS ai_usage_user_day_idx ON agente.ai_usage (user_id, day);

CREATE TABLE IF NOT EXISTS agente.ai_pricing (
  model          text PRIMARY KEY,
  usd_per_1m_in  numeric NOT NULL,
  usd_per_1m_out numeric NOT NULL,
  usd_brl        numeric NOT NULL,
  source         text,
  updated_at     timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE agente.ai_pricing ADD COLUMN IF NOT EXISTS usd_per_call numeric;

-- Precos oficiais (https://developers.openai.com/api/docs/pricing, consultado em 01/11/2026, tier Standard, contexto curto).
-- Busca na web: US$ 10,00 por 1.000 chamadas (US$ 0,01 por chamada) + tokens do conteudo da busca cobrados na tarifa do modelo.
-- Cambio: PTAX venda do Banco Central de 28/10/2026 = R$ 5,3420 (ajustar em ai_pricing.usd_brl quando quiser).
INSERT INTO agente.ai_pricing (model, usd_per_1m_in, usd_per_1m_out, usd_brl, source) VALUES
  ('gpt-6-luna',    0.10,  0.50, 5.3420, 'developers.openai.com/api/docs/pricing 01/11/2026; cambio PTAX venda 28/10/2026'),
  ('gpt-6.1-sol',   2.00, 10.00, 5.3420, 'developers.openai.com/api/docs/pricing 01/11/2026; cambio PTAX venda 28/10/2026'),
  ('gpt-4.1-mini',  0.40,  1.60, 5.3420, 'developers.openai.com/api/docs/pricing 01/11/2026; cambio PTAX venda 28/10/2026')
ON CONFLICT (model) DO NOTHING;
INSERT INTO agente.ai_pricing (model, usd_per_1m_in, usd_per_1m_out, usd_brl, source, usd_per_call) VALUES
  ('tool:web_search', 0, 0, 5.3420, 'developers.openai.com/api/docs/pricing 01/11/2026: US$ 10,00 por 1k chamadas + tokens do conteudo da busca nas tarifas do modelo', 0.01)
ON CONFLICT (model) DO UPDATE SET usd_per_call = coalesce(agente.ai_pricing.usd_per_call, EXCLUDED.usd_per_call);

-- Limite: no maximo 3 pesquisas por minuto por pessoa. Reserva a linha de uso (conta mesmo se a pesquisa falhar).
CREATE OR REPLACE FUNCTION agente.f_research_gate(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE n int; oldest timestamptz; tz text; uid bigint;
BEGIN
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  IF tz IS NULL THEN RETURN jsonb_build_object('ok', false, 'wait_s', 0, 'error', 'usuario nao encontrado'); END IF;
  PERFORM pg_advisory_xact_lock(hashtext('research:' || p_user::text));
  SELECT count(*), min(created_at) INTO n, oldest FROM ai_usage
   WHERE user_id = p_user AND kind = 'pesquisa' AND created_at > now() - interval '1 minute';
  IF n >= 3 THEN
    RETURN jsonb_build_object('ok', false, 'wait_s', greatest(1, ceil(extract(epoch FROM (oldest + interval '1 minute' - now())))::int));
  END IF;
  INSERT INTO ai_usage (user_id, day, kind, tokens_in, tokens_out, estimated, extra_usd)
  VALUES (p_user, (now() AT TIME ZONE tz)::date, 'pesquisa', 0, 0, true, 0) RETURNING id INTO uid;
  RETURN jsonb_build_object('ok', true, 'usage_id', uid);
END $$;

-- Grava o uso da pesquisa e devolve custo da pesquisa, do dia e do mes (R$, estimativa; todos os tipos de uso da pessoa).
CREATE OR REPLACE FUNCTION agente.f_research_log(p_user bigint, p_usage_id bigint, p_model text, p_in int, p_out int, p_searches int, p_estimated boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE tz text; d date; fee numeric; pr record; this_usd numeric := 0; priced boolean := false; brl numeric := 5.3420;
        day_usd numeric; mon_usd numeric; unpriced int; this_brl numeric; searches int := greatest(coalesce(p_searches, 0), 0);
BEGIN
  SELECT timezone INTO tz FROM users WHERE id = p_user;
  d := (now() AT TIME ZONE coalesce(tz, 'America/Sao_Paulo'))::date;
  SELECT coalesce(usd_per_call, 0) INTO fee FROM ai_pricing WHERE model = 'tool:web_search';
  fee := coalesce(fee, 0.01);
  SELECT * INTO pr FROM ai_pricing WHERE model = p_model;
  IF FOUND THEN
    priced := true; brl := pr.usd_brl;
    this_usd := (coalesce(p_in, 0) * pr.usd_per_1m_in + coalesce(p_out, 0) * pr.usd_per_1m_out) / 1000000.0;
  END IF;
  this_usd := this_usd + searches * fee;
  IF p_usage_id IS NOT NULL AND EXISTS (SELECT 1 FROM ai_usage WHERE id = p_usage_id AND user_id = p_user) THEN
    UPDATE ai_usage SET model = p_model, tokens_in = coalesce(p_in, 0), tokens_out = coalesce(p_out, 0),
           estimated = coalesce(p_estimated, false), extra_usd = searches * fee WHERE id = p_usage_id;
  ELSE
    INSERT INTO ai_usage (user_id, day, kind, model, tokens_in, tokens_out, estimated, extra_usd)
    VALUES (p_user, d, 'pesquisa', p_model, coalesce(p_in, 0), coalesce(p_out, 0), coalesce(p_estimated, false), searches * fee);
  END IF;
  SELECT coalesce(sum((u.tokens_in * coalesce(p.usd_per_1m_in, 0) + u.tokens_out * coalesce(p.usd_per_1m_out, 0)) / 1000000.0 + u.extra_usd), 0)
    INTO day_usd FROM ai_usage u LEFT JOIN ai_pricing p ON p.model = u.model WHERE u.user_id = p_user AND u.day = d;
  SELECT coalesce(sum((u.tokens_in * coalesce(p.usd_per_1m_in, 0) + u.tokens_out * coalesce(p.usd_per_1m_out, 0)) / 1000000.0 + u.extra_usd), 0)
    INTO mon_usd FROM ai_usage u LEFT JOIN ai_pricing p ON p.model = u.model
   WHERE u.user_id = p_user AND u.day >= date_trunc('month', d)::date AND u.day <= d;
  SELECT count(*) INTO unpriced FROM ai_usage u WHERE u.user_id = p_user AND u.day >= date_trunc('month', d)::date
     AND u.tokens_in + u.tokens_out > 0 AND NOT EXISTS (SELECT 1 FROM ai_pricing p WHERE p.model = u.model);
  RETURN jsonb_build_object('priced', priced, 'model', p_model, 'tokens_in', coalesce(p_in, 0), 'tokens_out', coalesce(p_out, 0),
    'searches', searches, 'search_fee_usd', fee, 'usd_brl', brl,
    'cost_usd', round(this_usd, 6), 'cost_brl', round(this_usd * brl, 4),
    'day_brl', round(day_usd * brl, 4), 'month_brl', round(mon_usd * brl, 4), 'unpriced_rows', unpriced);
END $$;

-- Menu: area "pesquisa" (botao mn:pesquisa). Wrapper: o resto vai para a funcao anterior da cadeia.
DO $$ BEGIN
  IF to_regproc('agente.f_menu_pre_m5') IS NULL THEN
    ALTER FUNCTION agente.f_menu(bigint, text) RENAME TO f_menu_pre_m5;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION agente.f_menu(p_user bigint, p_key text) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE k text := lower(coalesce(btrim(p_key), 'inicio'));
BEGIN
  IF k = 'pesquisa' THEN
    RETURN jsonb_build_object('rid', 0, 'kb', 'menu', 'text',
      E'Pesquisa na web\nPergunto na internet e respondo curto, com as fontes (título e link). Se não achar fonte confiável, eu digo.\n\nTente dizer:\n- "câmbio do dólar hoje"\n- "preço médio de um notebook para arquitetura"\n- "qual a regra do IPVA em SP?"\n- "norma de acessibilidade para rampa"\n\nCusto: cada pesquisa gasta um pouco da minha conta de IA, e eu mostro no fim da resposta uma estimativa em reais, mais o total do dia e do mês. É só um aviso: a pesquisa sempre é feita. Se o gasto do dia passar do limite (padrão R$ 1,00), o aviso fica em destaque.\n\nLimite: 3 pesquisas por minuto. Eu envio à OpenAI só a sua pergunta (nada da sua agenda, finanças ou contatos), e o texto da web é tratado como informação, nunca como ordem.\n\nPedidos pessoais (agenda, gastos, lembretes) não vão para a pesquisa.');
  END IF;
  RETURN f_menu_pre_m5(p_user, p_key);
END $$;
