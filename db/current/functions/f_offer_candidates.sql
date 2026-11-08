-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_offer_candidates(p_user bigint, p_pessoa text, p_lugar text)
-- Origem da definicao atual: 035_memoria_unificada.sql (linha 407)
-- Definicoes (migracao:linha), da mais antiga a atual: 035_memoria_unificada.sql:407
CREATE OR REPLACE FUNCTION agente.f_offer_candidates(p_user bigint, p_pessoa text DEFAULT '', p_lugar text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  sw boolean := f_mem_sw(p_user, 'offer_save_enabled'); u users%ROWTYPE;
  pn text := btrim(coalesce(p_pessoa, '')); ln text := btrim(coalesce(p_lugar, ''));
  pk text; lk text; pst text := 'none'; lst text := 'none'; pid bigint; lid bigint; until_p timestamptz; until_l timestamptz;
  op boolean; ol boolean; msg text; pdisp text; ldisp text; has_mail boolean := NULL; has_addr boolean := NULL;
BEGIN
  SELECT * INTO u FROM users WHERE id = p_user;
  pk := regexp_replace(f_norm(pn), '^(a|o|as|os) ', '');
  lk := regexp_replace(f_norm(ln), '^(a|o|na|no|da|do|de|em|as|os) ', '');

  IF pk <> '' THEN
    IF pk IN ('eu', 'mim', 'voce', 'me') OR pk = f_norm(u.name) OR pk = f_norm(coalesce(u.nickname, '')) THEN pst := 'self';
    ELSIF f_ct_group_find(p_user, pn) IS NOT NULL THEN pst := 'group';
    ELSE
      pid := f_find_pessoa(p_user, pn);
      IF pid IS NOT NULL THEN
        pst := 'exists'; SELECT (email <> '') INTO has_mail FROM contacts WHERE id = pid;
      ELSE
        SELECT ate INTO until_p FROM save_offers_silenced WHERE user_id = p_user AND tipo = 'pessoa' AND norm_name = pk AND ate > now();
        pst := CASE WHEN until_p IS NOT NULL THEN 'silenced' ELSE 'new' END;
      END IF;
    END IF;
  END IF;

  IF lk <> '' THEN
    lid := f_find_lugar(p_user, ln);
    IF lid IS NOT NULL THEN
      lst := 'exists'; SELECT (address <> '') INTO has_addr FROM places WHERE id = lid;
    ELSE
      SELECT ate INTO until_l FROM save_offers_silenced WHERE user_id = p_user AND tipo = 'lugar' AND norm_name = lk AND ate > now();
      lst := CASE WHEN until_l IS NOT NULL THEN 'silenced' ELSE 'new' END;
    END IF;
  END IF;

  op := sw AND pst = 'new'; ol := sw AND lst = 'new';
  pdisp := f_ct_disp(pn); ldisp := lower(regexp_replace(ln, '^(a|o|na|no|da|do|de|em|as|os) ', '', 'i'));
  msg := CASE
    WHEN op AND ol THEN 'Quer adicionar ' || pdisp || ' nos contatos e salvar o lugar "' || ldisp || '"? Se quiser, me manda o e-mail e o endereço.'
    WHEN op THEN 'Quer adicionar ' || pdisp || ' nos contatos? Se quiser, me manda o e-mail.'
    WHEN ol THEN 'Quer salvar o lugar "' || ldisp || '"? Se quiser, me manda o endereço.'
    ELSE '' END;
  RETURN jsonb_build_object(
    'enabled', sw, 'offer', op OR ol, 'offer_person', op, 'offer_place', ol, 'ask_email', op, 'ask_address', ol,
    'person', CASE WHEN pk = '' THEN NULL ELSE jsonb_build_object('name', pn, 'status', pst, 'id', pid, 'has_email', has_mail, 'silenced_until', until_p) END,
    'place',  CASE WHEN lk = '' THEN NULL ELSE jsonb_build_object('name', ln, 'status', lst, 'id', lid, 'has_address', has_addr, 'silenced_until', until_l) END,
    'message', msg);
END $$;
