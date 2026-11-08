-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_offer_decline(p_user bigint, p_pessoa text, p_lugar text)
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 513)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:513
CREATE OR REPLACE FUNCTION agente.f_offer_decline(p_user bigint, p_pessoa text DEFAULT '', p_lugar text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE pk text := regexp_replace(f_norm(coalesce(p_pessoa, '')), '^(a|o|as|os) ', ''); lk text := regexp_replace(f_norm(coalesce(p_lugar, '')), '^(a|o|na|no|da|do|de|em|as|os) ', '');
        v_ate timestamptz := now() + interval '30 days'; n int := 0;
BEGIN
  IF pk <> '' THEN
    INSERT INTO save_offers_silenced(user_id, tipo, norm_name, ate) VALUES (p_user, 'pessoa', pk, v_ate)
    ON CONFLICT (user_id, tipo, norm_name) DO UPDATE SET ate = EXCLUDED.ate, created_at = now();
    n := n + 1;
  END IF;
  IF lk <> '' THEN
    INSERT INTO save_offers_silenced(user_id, tipo, norm_name, ate) VALUES (p_user, 'lugar', lk, v_ate)
    ON CONFLICT (user_id, tipo, norm_name) DO UPDATE SET ate = EXCLUDED.ate, created_at = now();
    n := n + 1;
  END IF;
  RETURN jsonb_build_object('ok', n > 0, 'silenced', n, 'until', v_ate, 'text', CASE WHEN n > 0 THEN 'Ok, não pergunto de novo por um tempo.' ELSE '' END);
END $$;
