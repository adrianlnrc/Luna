-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_supply_manage(p_user bigint, p_item text, p_units_left integer, p_pause_days integer, p_action text, p_new_name text)
-- Origem da definicao atual: 024_ciclo_correcoes.sql (linha 100)
-- Definicoes (migracao:linha), da mais antiga a atual: 024_ciclo_correcoes.sql:100
CREATE OR REPLACE FUNCTION agente.f_supply_manage(p_user bigint, p_item text, p_units_left integer, p_pause_days integer, p_action text, p_new_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE v_id bigint; s supplies%ROWTYPE; nn text := nullif(btrim(coalesce(p_new_name, '')), '');
        it text := lower(btrim(coalesce(p_item, '')));
        generic text[] := ARRAY['', 'remedio', 'remédio', 'medicamento', 'comprimido', 'pilula', 'pílula', 'capsula', 'cápsula', 'generico', 'genérico'];
BEGIN
  IF coalesce(p_action, '') = 'rename' THEN
    IF nn IS NULL THEN RETURN jsonb_build_object('action', 'rename', 'found', false, 'need_name', true); END IF;
    IF it = ANY (generic) THEN
      SELECT id INTO v_id FROM supplies WHERE user_id = p_user AND status = 'active' AND lower(btrim(item)) = ANY (generic) ORDER BY created_at DESC LIMIT 1;
    ELSE
      v_id := f_find_supply(p_user, p_item);
    END IF;
    IF v_id IS NULL THEN RETURN jsonb_build_object('action', 'rename', 'found', false); END IF;
    SELECT * INTO s FROM supplies WHERE id = v_id;
    IF EXISTS (SELECT 1 FROM supplies WHERE user_id = p_user AND status = 'active' AND id <> v_id AND lower(btrim(item)) = lower(nn)) THEN
      RETURN jsonb_build_object('action', 'rename', 'found', true, 'conflict', true, 'item', nn, 'old_item', s.item);
    END IF;
    UPDATE supplies SET item = nn WHERE id = v_id;
    RETURN jsonb_build_object('action', 'rename', 'found', true, 'old_item', s.item, 'item', nn, 'take_time', to_char(s.take_time, 'HH24:MI'));
  ELSIF coalesce(p_action, '') = 'delete' THEN
    v_id := f_find_supply(p_user, p_item);
    IF v_id IS NULL THEN RETURN jsonb_build_object('action', 'delete', 'found', false); END IF;
    SELECT * INTO s FROM supplies WHERE id = v_id;
    RETURN jsonb_build_object('action', 'delete', 'found', true, 'confirm', true, 'sid', v_id, 'item', s.item, 'take_time', to_char(s.take_time, 'HH24:MI'));
  END IF;
  RETURN f_supply_adjust(p_user, p_item, p_units_left, p_pause_days);
END $function$;
