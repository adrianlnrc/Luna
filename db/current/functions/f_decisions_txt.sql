-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_decisions_txt(p_user bigint)
-- Origem da definicao atual: 040_assessor_runs.sql (linha 131)
-- Definicoes (migracao:linha), da mais antiga a atual: 040_assessor_runs.sql:131
CREATE OR REPLACE FUNCTION f_decisions_txt(p_user bigint) RETURNS text
LANGUAGE sql STABLE SET search_path = agente, public AS $$
  SELECT coalesce(string_agg('- ' || linha, E'\n' ORDER BY quando DESC), '') FROM (
    SELECT quando, linha FROM (
      SELECT pa.criado_em AS quando,
             to_char(pa.criado_em AT TIME ZONE u.timezone, 'DD/MM') || ': propus "' || left(pa.resumo, 110) || '" -> '
             || CASE pa.status WHEN 'executada' THEN 'confirmou' WHEN 'cancelada' THEN 'recusou' WHEN 'expirada' THEN 'nao respondeu'
                               WHEN 'pendente' THEN 'aguardando' ELSE pa.status END AS linha
        FROM pending_actions pa JOIN users u ON u.id = pa.user_id
       WHERE pa.user_id = p_user AND pa.criado_em > now() - interval '30 days' AND pa.resumo <> ''
      UNION ALL
      SELECT l.enviado_em,
             to_char(l.enviado_em AT TIME ZONE u.timezone, 'DD/MM') || ': avisei "' || left(l.texto, 110) || '" -> '
             || CASE coalesce(l.resposta, '') WHEN 'aceito' THEN 'aceitou' WHEN 'agora_nao' THEN 'disse agora nao'
                               WHEN 'silenciado' THEN 'pediu para nao avisar mais' WHEN 'ignorado' THEN 'ignorou' ELSE 'sem resposta' END
        FROM insights_log l JOIN users u ON u.id = l.user_id
       WHERE l.user_id = p_user AND l.enviado_em > now() - interval '30 days'
    ) todos ORDER BY quando DESC LIMIT 10) ult
$$;
