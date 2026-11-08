-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_ai_cost_text(p_user bigint)
-- Origem da definicao atual: 028_custo_ia_anuais.sql (linha 64)
-- Definicoes (migracao:linha), da mais antiga a atual: 028_custo_ia_anuais.sql:64
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
