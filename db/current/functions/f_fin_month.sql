-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_month(p_user bigint, p_month text, p_period text, OUT m_start date, OUT m_end date, OUT m_label text)
-- Origem da definicao atual: 013_extras.sql (linha 384)
-- Definicoes (migracao:linha), da mais antiga a atual: 013_extras.sql:384
CREATE OR REPLACE FUNCTION f_fin_month(p_user bigint, p_month text, p_period text, OUT m_start date, OUT m_end date, OUT m_label text)
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE cs date; off integer; yy integer; mm integer;
  nm text[] := ARRAY['janeiro','fevereiro','março','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro'];
BEGIN
  IF p_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    yy := substr(p_month, 1, 4)::int; mm := substr(p_month, 6, 2)::int;
    SELECT p_start INTO cs FROM f_fin_period(p_user, 0);
    off := (yy - extract(year FROM cs)::int) * 12 + mm - extract(month FROM cs)::int;
    SELECT p_start, p_end INTO m_start, m_end FROM f_fin_period(p_user, off);
    m_label := 'em ' || nm[mm] || CASE WHEN yy <> extract(year FROM f_fin_today(p_user))::int THEN ' de ' || yy ELSE '' END;
  ELSE
    SELECT r_start, r_end, r_label INTO m_start, m_end, m_label FROM f_fin_range(p_user, coalesce(nullif(p_period, ''), 'current'));
    m_label := CASE m_label WHEN 'mês atual' THEN 'no mês atual' WHEN 'mês anterior' THEN 'no mês anterior' WHEN 'últimos 7 dias' THEN 'nos últimos 7 dias' ELSE m_label END;
  END IF;
  m_label := m_label || ' (' || to_char(m_start, 'DD/MM') || ' a ' || to_char(m_end, 'DD/MM') || ')';
END $$;
