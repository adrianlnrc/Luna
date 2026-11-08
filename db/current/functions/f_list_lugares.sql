-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_list_lugares(p_user bigint)
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 260)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:260
CREATE OR REPLACE FUNCTION agente.f_list_lugares(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE r record; t text; n int;
BEGIN
  SELECT count(*) INTO n FROM places WHERE user_id = p_user;
  t := 'Lugares (' || n || '):';
  IF n = 0 THEN t := t || E'\n- nenhum ainda. Ex.: "o local igreja é Rua das Flores, 120"'; END IF;
  FOR r IN SELECT name, address, (SELECT string_agg(f_ct_disp(a), ', ') FROM unnest(aliases) a) AS apelidos
             FROM places WHERE user_id = p_user ORDER BY name LOOP
    t := t || E'\n- ' || f_ct_disp(r.name) || ': ' || CASE WHEN r.address <> '' THEN r.address ELSE 'sem endereço ainda' END
         || CASE WHEN r.apelidos IS NOT NULL THEN ' [apelidos: ' || r.apelidos || ']' ELSE '' END;
  END LOOP;
  RETURN jsonb_build_object('text', t, 'lugares', n);
END $$;
