-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_projects(p_user bigint, p jsonb)
-- Origem da definicao atual: 025_listas_compras.sql (linha 55) [dentro de bloco DO/EXECUTE, criacao condicional]
-- Definicoes (migracao:linha), da mais antiga a atual: 025_listas_compras.sql:55
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
END $f$;
