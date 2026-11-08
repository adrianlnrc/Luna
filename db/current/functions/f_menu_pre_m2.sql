-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_menu_pre_m2(p_user bigint, p_key text)
-- Origem da definicao atual: 025_listas_compras.sql (linha 77) [dentro de bloco DO/EXECUTE, criacao condicional]
-- Definicoes (migracao:linha), da mais antiga a atual: 025_listas_compras.sql:77
-- Renomeada de f_menu para f_menu_pre_m2 em 026_recibo_alertas.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_menu_pre_m2).
CREATE OR REPLACE FUNCTION agente.f_menu(p_user bigint, p_key text) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $f$
DECLARE r jsonb := f_menu_pre_m1(p_user, p_key); k text := lower(coalesce(btrim(p_key), 'inicio')); t text := r->>'text';
BEGIN
  IF k = 'listas' THEN
    t := f_ls_menu_ins(t, E'\n\nLista de compras:\n- "preciso comprar leite" ou "acabou o café" (sem hora) entra na lista Mercado\n- "me lembra de comprar pão às 18h" (com hora) vira lembrete\n- mande vários itens, um por linha, começando com traço (- leite, - 2 pães, - ovos): todos entram na lista Mercado\n- se a primeira linha tiver outro nome ("Farmácia:"), os itens vão para essa lista\n"Compras", "mercado", "supermercado" e "feira" são a mesma lista.');
  ELSIF k = 'projetos' THEN
    t := f_ls_menu_ins(t, E'\n\nTarefa solta e urgência:\n- "coloca a tarefa ligar pro contador no projeto Reforma" (a tarefa do Google Tasks continua lá; diga "conclui a tarefa ..." para dar baixa)\n- "marca contratar pintor como urgente" ou "tira a urgência de contratar pintor"');
  ELSIF k = 'tarefas' THEN
    t := f_ls_menu_ins(t, E'\n\nPara comprar algo, sem hora: "preciso comprar leite" vai para a lista de compras. Com hora, eu crio um lembrete.');
  END IF;
  RETURN jsonb_set(r, '{text}', to_jsonb(t));
END $f$;
