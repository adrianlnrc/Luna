-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_user_export(p_user bigint)
-- Origem da definicao atual: 040_assessor_runs.sql (linha 205)
-- Definicoes (migracao:linha), da mais antiga a atual: 040_assessor_runs.sql:205
CREATE OR REPLACE FUNCTION f_user_export(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE out jsonb; r record; j jsonb;
BEGIN
  SELECT jsonb_build_object('exportado_em', now(), 'usuario', to_jsonb(u)) INTO out FROM users u WHERE u.id = p_user;
  IF out IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'usuario'); END IF;
  FOR r IN SELECT tabela FROM f_user_tables() WHERE tabela NOT LIKE '\_bak%' AND tabela NOT IN ('oauth_states') LOOP
    IF r.tabela = 'oauth_tokens' THEN  -- nunca exporta o token; so os metadados
      SELECT coalesce(jsonb_agg(jsonb_build_object('provedor', provedor, 'escopos', escopos, 'criado_em', criado_em, 'revogado_em', revogado_em)), '[]')
        INTO j FROM oauth_tokens WHERE user_id = p_user;
    ELSE
      EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) FROM agente.%I t WHERE t.user_id = $1', r.tabela) INTO j USING p_user;
    END IF;
    out := out || jsonb_build_object(r.tabela, j);
  END LOOP;
  SELECT coalesce(jsonb_agg(to_jsonb(m)), '[]') INTO j FROM contact_group_members m JOIN contact_groups g ON g.id = m.group_id WHERE g.user_id = p_user;
  out := out || jsonb_build_object('contact_group_members', j);
  SELECT coalesce(jsonb_agg(to_jsonb(d)), '[]') INTO j FROM fin_goal_deposits d JOIN fin_goals g ON g.id = d.goal_id WHERE g.user_id = p_user;
  out := out || jsonb_build_object('fin_goal_deposits', j);
  RETURN out;
END $$;
