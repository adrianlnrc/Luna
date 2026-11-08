-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_create_supply_base(p_user bigint, p_item text, p_total integer, p_per_day numeric, p_started date, p_alert_days integer, p_kind text, p_take_time time, p_left integer)
-- Origem da definicao atual: 006_cadastro_simples.sql (linha 48)
-- Definicoes (migracao:linha), da mais antiga a atual: 006_cadastro_simples.sql:48
-- Renomeada de f_create_supply para f_create_supply_base em 024_ciclo_correcoes.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_create_supply_base).
CREATE OR REPLACE FUNCTION f_create_supply(p_user bigint, p_item text, p_total integer DEFAULT NULL,
  p_per_day numeric DEFAULT 1, p_started date DEFAULT NULL, p_alert_days integer DEFAULT NULL,
  p_kind text DEFAULT NULL, p_take_time time DEFAULT NULL, p_left integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint; v_alert integer; v_kind text := CASE WHEN p_kind = 'remedio' THEN 'remedio' ELSE 'suplemento' END;
        v_row supplies_status%ROWTYPE; v_cur supplies_status%ROWTYPE; v_created boolean := false;
BEGIN
  SELECT supply_alert_days INTO v_alert FROM users WHERE id = p_user;
  v_alert := COALESCE(p_alert_days, CASE WHEN v_kind = 'remedio' THEN 7 END, v_alert, 5);
  v_id := f_find_supply(p_user, p_item);
  IF v_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM supplies WHERE id = v_id AND (item ILIKE '%' || p_item || '%' OR p_item ILIKE '%' || item || '%')) THEN
    -- caiu no "so existe um item": so reaproveita se o pedido nao traz nome proprio de outro item
    IF COALESCE(trim(p_item), '') NOT IN ('', 'comprimido', 'remedio', 'pilula', 'capsula') THEN v_id := NULL; END IF;
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO supplies(user_id, item, units_total, pack_size, units_per_day, started_on, alert_days, kind, take_time)
    VALUES (p_user, p_item, COALESCE(p_left, p_total), COALESCE(p_total, p_left), COALESCE(p_per_day, 1),
            COALESCE(p_started, CURRENT_DATE), v_alert, v_kind, p_take_time) RETURNING id INTO v_id;
    v_created := true;
  ELSE
    SELECT * INTO v_cur FROM supplies_status WHERE id = v_id;
    IF p_left IS NOT NULL OR p_total IS NOT NULL THEN
      UPDATE supplies SET units_total = COALESCE(p_left, p_total), pack_size = COALESCE(p_total, p_left, pack_size),
        started_on = COALESCE(p_started, CURRENT_DATE), paused_days = 0, alert_notified_on = NULL WHERE id = v_id;
    ELSIF p_take_time IS NOT NULL AND v_cur.take_time IS NULL AND v_cur.units_left IS NOT NULL THEN
      -- ligou o lembrete de tomar: passa a contar a partir do que resta hoje
      UPDATE supplies SET units_total = GREATEST(1, round(v_cur.units_left)::int), started_on = CURRENT_DATE, paused_days = 0 WHERE id = v_id;
    END IF;
    UPDATE supplies SET units_per_day = COALESCE(p_per_day, units_per_day), alert_days = COALESCE(p_alert_days, alert_days),
      kind = CASE WHEN p_kind IS NOT NULL THEN v_kind ELSE kind END, take_time = COALESCE(p_take_time, take_time) WHERE id = v_id;
  END IF;
  SELECT * INTO v_row FROM supplies_status WHERE id = v_id;
  RETURN jsonb_build_object('id', v_id, 'item', v_row.item, 'created', v_created, 'kind', v_row.kind,
    'units_left', v_row.units_left, 'needs_total', v_row.units_left IS NULL,
    'take_time', to_char(v_row.take_time, 'HH24:MI'),
    'runs_out_on', to_char(v_row.runs_out_on, 'DD/MM'), 'alert_on', to_char(v_row.alert_on, 'DD/MM'), 'alert_days', v_row.alert_days);
END $$;
