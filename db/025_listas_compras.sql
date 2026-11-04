-- Onda 2, M1: lista de compras (padrao "Mercado"), apelidos, tarefa solta para projeto, menu.
-- Idempotente. Cada wrapper so e criado na PRIMEIRA aplicacao (junto do renomeio guardado), para
-- nunca sobrescrever a cadeia viva se outro modulo embrulhar a mesma funcao depois.
--   f_lists   -> f_lists_base      (apelidos compras/mercado/supermercado/feira -> mercado; sem nome = Mercado)
--   f_projects-> f_projects_base   (tarefa solta colocada no projeto: aviso sobre o Google Tasks)
--   f_menu    -> f_menu_pre_m1     (textos de Listas e notas, Projetos e Tarefas)
SET search_path TO agente, public;

-- apelido da lista padrao
CREATE OR REPLACE FUNCTION f_ls_is_default(p text) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT f_norm(f_ls_clean(p)) IN ('mercado','compras','compra','supermercado','super','feira','feiras','mercados')
$$;

-- insere um bloco no texto do menu antes da "Dica:" final (ou no fim)
CREATE OR REPLACE FUNCTION f_ls_menu_ins(p_text text, p_block text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente','public' AS $$
  SELECT CASE WHEN position(E'\n\nDica:' IN p_text) > 0
    THEN substr(p_text, 1, position(E'\n\nDica:' IN p_text) - 1) || p_block || substr(p_text, position(E'\n\nDica:' IN p_text))
    ELSE p_text || p_block END
$$;

DO $$
BEGIN
  IF to_regproc('agente.f_lists_base') IS NULL THEN
    ALTER FUNCTION agente.f_lists(bigint, jsonb) RENAME TO f_lists_base;
    EXECUTE $w$
CREATE OR REPLACE FUNCTION agente.f_lists(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $f$
DECLARE
  act text := lower(COALESCE(NULLIF(btrim(p->>'list_action'), ''), 'show'));
  nm text := f_ls_clean(p->>'list_name');
  q jsonb := p;
  v_merc bigint;
BEGIN
  SELECT id INTO v_merc FROM lists WHERE user_id = p_user AND name_norm = 'mercado' ORDER BY id LIMIT 1;
  IF nm <> '' THEN
    -- apelido -> mercado (se existir uma lista antiga com o proprio nome do apelido e nao houver mercado, usa ela)
    IF f_ls_is_default(nm) AND NOT (v_merc IS NULL AND EXISTS (SELECT 1 FROM lists WHERE user_id = p_user AND name_norm = f_norm(nm))) THEN
      q := jsonb_set(q, '{list_name}', to_jsonb('mercado'::text));
    END IF;
  ELSIF act IN ('add','create') THEN
    q := jsonb_set(q, '{list_name}', to_jsonb('mercado'::text));
  ELSIF act IN ('show','remove','check','uncheck','clear') AND v_merc IS NOT NULL THEN
    q := jsonb_set(q, '{list_name}', to_jsonb('mercado'::text));
  END IF;
  RETURN f_lists_base(p_user, q);
END $f$
    $w$;
  END IF;

  IF to_regproc('agente.f_projects_base') IS NULL THEN
    ALTER FUNCTION agente.f_projects(bigint, jsonb) RENAME TO f_projects_base;
    EXECUTE $w$
CREATE OR REPLACE FUNCTION agente.f_projects(p_user bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente','public' AS $f$
DECLARE
  loose boolean := lower(btrim(coalesce(p->>'task', ''))) = 'solta' AND lower(coalesce(p->>'action', '')) = 'add_tasks';
  q jsonb := p; r jsonb; ttl text;
BEGIN
  IF loose THEN
    q := jsonb_set(q, '{task}', to_jsonb(''::text));
    ttl := btrim(split_part(coalesce(p->'tasks'->>0, ''), '|', 1));
  END IF;
  r := f_projects_base(p_user, q);
  IF loose AND ttl <> '' AND (r->>'text') LIKE 'Tarefa adicionada ao projeto%' THEN
    r := jsonb_set(r, '{text}', to_jsonb((r->>'text') || E'\nA tarefa solta no Google Tasks continua lá. Se quiser, diga "conclui a tarefa ' || ttl || '" para dar baixa nela.'));
  END IF;
  RETURN r;
END $f$
    $w$;
  END IF;

  IF to_regproc('agente.f_menu_pre_m1') IS NULL THEN
    ALTER FUNCTION agente.f_menu(bigint, text) RENAME TO f_menu_pre_m1;
    EXECUTE $w$
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
END $f$
    $w$;
  END IF;
END $$;
