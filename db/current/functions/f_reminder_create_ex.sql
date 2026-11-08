-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_reminder_create_ex(p_user bigint, p_title text, p_due timestamp with time zone, p_shared boolean, p_lead integer, p_source text, p_repeat jsonb)
-- Origem da definicao atual: 024_ciclo_correcoes.sql (linha 161)
-- Definicoes (migracao:linha), da mais antiga a atual: 024_ciclo_correcoes.sql:161
CREATE OR REPLACE FUNCTION agente.f_reminder_create_ex(p_user bigint, p_title text, p_due timestamp with time zone, p_shared boolean DEFAULT false, p_lead integer DEFAULT NULL::integer, p_source text DEFAULT 'text'::text, p_repeat jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE v_id bigint;
BEGIN
  SELECT id INTO v_id FROM reminders
   WHERE user_id = p_user AND kind = 'reminder' AND status = 'pending' AND due_at = p_due
     AND lower(btrim(title)) = lower(btrim(p_title))
   ORDER BY id LIMIT 1;
  IF v_id IS NOT NULL THEN
    RETURN jsonb_build_object('reminder_id', v_id, 'ask_lead', false, 'title', p_title, 'due_at', p_due, 'duplicate', true);
  END IF;
  RETURN f_reminder_create_ex_base(p_user, p_title, p_due, p_shared, p_lead, p_source, p_repeat);
END $function$;
