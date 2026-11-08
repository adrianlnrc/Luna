-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_menu_pre_m1(p_user bigint, p_key text)
-- Origem da definicao atual: 024_ciclo_correcoes.sql (linha 179)
-- Definicoes (migracao:linha), da mais antiga a atual: 024_ciclo_correcoes.sql:179
-- Renomeada de f_menu para f_menu_pre_m1 em 025_listas_compras.sql; o texto abaixo ainda traz o nome ORIGINAL (a funcao no banco chama-se f_menu_pre_m1).
CREATE OR REPLACE FUNCTION agente.f_menu(p_user bigint, p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'agente', 'public'
AS $function$
DECLARE r jsonb := f_menu_base(p_user, p_key); k text := lower(coalesce(btrim(p_key), 'inicio')); t text := r->>'text';
BEGIN
  IF k = 'remedios' THEN
    t := t || E'\n\nCorrigir e apagar:\n- "o nome é sertralina" (corrijo o nome de um item genérico)\n- "apaga o remédio sertralina" (peço confirmação por botão)\nSe faltar o nome ao cadastrar, eu pergunto.';
  ELSIF k = 'dinheiro' THEN
    t := t || E'\n\nDois gastos de uma vez: "gastei 120 na farmácia e 80 no mercado" vira dois lançamentos.';
  END IF;
  IF k <> 'inicio' AND k NOT IN ('', 'menu') THEN
    t := t || E'\n\nDica: uma coisa por mensagem funciona melhor. Se vierem vários pedidos juntos, eu faço o principal e aviso o que ficou de fora.';
  END IF;
  RETURN jsonb_set(r, '{text}', to_jsonb(t));
END $function$;
