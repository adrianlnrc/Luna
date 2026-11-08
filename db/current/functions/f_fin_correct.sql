-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_fin_correct(p_user bigint, p jsonb)
-- Origem da definicao atual: 026_recibo_alertas.sql (linha 199) [dentro de bloco DO/EXECUTE, criacao condicional]
-- Definicoes (migracao:linha), da mais antiga a atual: 026_recibo_alertas.sql:199
CREATE FUNCTION agente.f_fin_correct(p_user bigint, p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE d date := f_safe_date(p->>'date'); e fin_entries%ROWTYPE; v_title text := btrim(coalesce(p->>'title', '')); v_found boolean := false;
        r jsonb; v_amt numeric := round(nullif(p->>'amount', '')::numeric, 2); has_other boolean;
BEGIN
  IF d IS NULL THEN RETURN f_fin_correct_pre_m2(p_user, p); END IF;
  IF v_title <> '' THEN
    SELECT * INTO e FROM fin_entries WHERE user_id = p_user AND status <> 'draft' AND norm_desc LIKE '%' || f_norm(v_title) || '%' ORDER BY id DESC LIMIT 1;
    v_found := FOUND;
  END IF;
  IF NOT v_found THEN
    SELECT * INTO e FROM fin_entries WHERE user_id = p_user AND status <> 'draft' ORDER BY id DESC LIMIT 1;
    IF NOT FOUND THEN RETURN f_fin_correct_pre_m2(p_user, p); END IF;
  END IF;
  IF e.series_id IS NOT NULL THEN
    RETURN jsonb_build_object('text', 'Esse lançamento é parcelado; para mudar a data, apague com "desfaz" e lance de novo com a data certa.', 'kb', 'none');
  END IF;
  IF e.status = 'pending' THEN
    RETURN jsonb_build_object('text', 'Essa conta ainda está a pagar; o vencimento tem aviso próprio. Apague e lance de novo com a data certa, ou diga "já paguei" quando pagar.', 'kb', 'none');
  END IF;
  UPDATE fin_entries SET occurred_on = d, paid_on = CASE WHEN status = 'paid' THEN d ELSE paid_on END WHERE id = e.id;
  has_other := (v_amt IS NOT NULL AND v_amt > 0) OR btrim(coalesce(p->>'category', '')) <> '';
  IF has_other THEN
    r := f_fin_correct_pre_m2(p_user, p - 'date');
    RETURN jsonb_set(r, '{text}', to_jsonb(rtrim(r->>'text') || ' Data: ' || to_char(d, 'DD/MM') || '.'));
  END IF;
  RETURN jsonb_build_object('text', 'Corrigido: ' || e.description || ' agora com data ' || to_char(d, 'DD/MM') || '.', 'kb', 'none');
END $function$;
