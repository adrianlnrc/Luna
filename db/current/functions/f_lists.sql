-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_lists(p_user bigint, p jsonb)
-- Origem da definicao atual: 025_listas_compras.sql (linha 28) [dentro de bloco DO/EXECUTE, criacao condicional]
-- Definicoes (migracao:linha), da mais antiga a atual: 025_listas_compras.sql:28
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
END $f$;
