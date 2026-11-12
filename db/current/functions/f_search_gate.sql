-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_search_gate(p_user bigint, p_max integer)
-- Origem da definicao atual: 042_assessor_ajustes.sql (linha 8)
-- Definicoes (migracao:linha), da mais antiga a atual: 042_assessor_ajustes.sql:8
CREATE OR REPLACE FUNCTION f_search_gate(p_user bigint, p_max integer DEFAULT 3) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = agente, public AS $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM ai_usage WHERE user_id = p_user AND kind = 'pesquisa' AND created_at > now() - interval '1 minute';
  IF n >= p_max THEN
    RETURN jsonb_build_object('ok', false, 'recentes', n,
      'text', 'Você fez ' || n || ' pesquisas no último minuto. Espere um pouco e peça de novo.');
  END IF;
  RETURN jsonb_build_object('ok', true, 'recentes', n);
END $$;
