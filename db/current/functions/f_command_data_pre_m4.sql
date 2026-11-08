-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_command_data_pre_m4(p_user bigint)
-- Origem da definicao atual: 023_locais_pergunta.sql (linha 227)
-- Definicoes (migracao:linha), da mais antiga a atual: 023_locais_pergunta.sql:227
-- Renomeada de f_command_data para f_command_data_pre_m4 em 028_custo_ia_anuais.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_command_data_pre_m4).
CREATE OR REPLACE FUNCTION f_command_data(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE r record; l text; np integer;
BEGIN
  SELECT count(*) INTO np FROM places WHERE user_id = p_user;
  l := 'Locais salvos (' || np || '):';
  IF np = 0 THEN l := l || E'\n- nenhum ainda.'; END IF;
  FOR r IN SELECT name, address FROM places WHERE user_id = p_user ORDER BY name LOOP
    l := l || E'\n- ' || f_ct_disp(r.name) || ': ' || CASE WHEN f_norm(r.address) = r.name OR lower(r.address) = lower(r.name) OR f_norm(r.address) = f_norm(r.name) THEN '(sem endereço)' ELSE r.address END;
  END LOOP;
  l := l || E'\n\nOs locais ficam guardados só para você, no meu banco de dados.'
    || E'\nPara salvar: "o local igreja é Rua das Flores, 120".'
    || E'\nPara tirar: "tira o local igreja".'
    || E'\nQuando você marcar algo num lugar que eu não conheço (por exemplo "na igreja"), eu pergunto o endereço e salvo para as próximas vezes.'
    || E'\n\n/contatos mostra também contatos e grupos.';
  RETURN f_command_data_base(p_user) || jsonb_build_object('locais', l);
END $$;
