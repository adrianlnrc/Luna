-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_menu_pre_m5(p_user bigint, p_key text)
-- Origem da definicao atual: 028_custo_ia_anuais.sql (linha 253) [dentro de bloco DO/EXECUTE, criacao condicional]
-- Definicoes (migracao:linha), da mais antiga a atual: 028_custo_ia_anuais.sql:253
-- Renomeada de f_menu para f_menu_pre_m5 em 029_pesquisa.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_menu_pre_m5).
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
END $b$;
