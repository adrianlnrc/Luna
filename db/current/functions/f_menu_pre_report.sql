-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_menu_pre_report(p_user bigint, p_key text)
-- Origem da definicao atual: 026_recibo_alertas.sql (linha 308) [dentro de bloco DO/EXECUTE, criacao condicional]
-- Definicoes (migracao:linha), da mais antiga a atual: 026_recibo_alertas.sql:308
-- Renomeada de f_menu para f_menu_pre_report em 027_relatorios.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_menu_pre_report).
CREATE FUNCTION agente.f_menu(p_user bigint, p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE r jsonb := f_menu_pre_m2(p_user, p_key); t text := r->>'text'; x text;
BEGIN
  IF lower(coalesce(btrim(p_key), '')) = 'dinheiro' THEN
    t := replace(t, 'O botão Desfazer apaga o último lançamento.',
      E'Cada lançamento vem com Desfazer e Editar, que valem por 24 horas. Depois disso, ou para outro lançamento, diga: "corrige para 50", "isso é Lazer" ou "foi dia 12".');
    IF position('Editar' in t) = 0 THEN
      t := t || E'\n\nCada lançamento vem com Desfazer e Editar, que valem por 24 horas. Para corrigir: "corrige para 50", "isso é Lazer" ou "foi dia 12".';
    END IF;
    x := E'\n\nAvisos automáticos (sem bloquear nada): assinatura que mudou de valor ("Spotify subiu de R$ 21,90 para R$ 27,90"), cobrança que parece repetida e fatura do cartão 30% ou mais acima da média.';
    IF position(E'\n\nDica:' in t) > 0 THEN
      t := replace(t, E'\n\nDica:', x || E'\n\nDica:');
    ELSE
      t := t || x;
    END IF;
  END IF;
  RETURN jsonb_set(r, '{text}', to_jsonb(t));
END $function$;
