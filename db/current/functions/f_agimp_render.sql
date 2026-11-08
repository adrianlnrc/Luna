-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_agimp_render(p_id bigint)
-- Origem da definicao atual: 032_resumo_enxuto.sql (linha 55)
-- Definicoes (migracao:linha), da mais antiga a atual: 031_agenda_import.sql:40, 032_resumo_enxuto.sql:55
CREATE OR REPLACE FUNCTION f_agimp_render(p_id bigint) RETURNS text
LANGUAGE plpgsql STABLE SET search_path TO 'agente','public' AS $$
DECLARE r agenda_import; it jsonb; v text; last_day date; d date; n_ev int := 0; n_tk int := 0; n_fx int := 0; tks text := ''; nt text := ''; fx text := ''; g record;
BEGIN
  SELECT * INTO r FROM agenda_import WHERE id = p_id;
  IF NOT FOUND THEN RETURN ''; END IF;
  SELECT count(*) FILTER (WHERE x.e->>'kind' = 'event' AND coalesce((x.e->>'fixed')::boolean, false) = false),
         count(*) FILTER (WHERE x.e->>'kind' = 'task'),
         count(*) FILTER (WHERE x.e->>'kind' = 'event' AND coalesce((x.e->>'fixed')::boolean, false))
    INTO n_ev, n_tk, n_fx FROM jsonb_array_elements(r.items) AS x(e) WHERE coalesce((x.e->>'skip')::boolean, false) = false;
  v := 'Li sua agenda' || CASE WHEN r.week_start IS NOT NULL THEN ' da semana de ' || to_char(r.week_start, 'DD/MM') || ' a ' || to_char(r.week_start + 6, 'DD/MM/YYYY') ELSE '' END
    || '. Confira antes de eu criar: ' || n_ev || ' compromisso(s) no Google Agenda, ' || n_tk || ' tarefa(s) no Google Tarefas'
    || CASE WHEN n_fx > 0 THEN ' e ' || n_fx || ' bloco(s) fixo(s)' ELSE '' END || '.' || E'\n';
  FOR it IN SELECT x.e FROM jsonb_array_elements(r.items) AS x(e)
            WHERE x.e->>'kind' = 'event' AND coalesce((x.e->>'skip')::boolean, false) = false AND coalesce((x.e->>'fixed')::boolean, false) = false
            ORDER BY x.e->>'day', x.e->>'start' LOOP
    d := (it->>'day')::date;
    IF last_day IS DISTINCT FROM d THEN
      v := v || E'\n' || f_agimp_dow(d) || ' ' || to_char(d, 'DD/MM') || E'\n';
      last_day := d;
    END IF;
    v := v || (it->>'n') || '. ' || (it->>'start') || '–' || (it->>'end') || ' ' || (it->>'title')
      || CASE WHEN coalesce((it->>'uncertain')::boolean, false) THEN ' (?)' ELSE '' END || E'\n';
  END LOOP;
  FOR g IN SELECT x.e->>'title' AS title, x.e->>'start' AS s, x.e->>'end' AS en, array_agg((x.e->>'day')::date) AS days, string_agg(x.e->>'n', ', ' ORDER BY (x.e->>'n')::int) AS ns,
                  bool_or(coalesce((x.e->>'uncertain')::boolean, false)) AS unc
             FROM jsonb_array_elements(r.items) AS x(e)
            WHERE x.e->>'kind' = 'event' AND coalesce((x.e->>'skip')::boolean, false) = false AND coalesce((x.e->>'fixed')::boolean, false)
            GROUP BY lower(x.e->>'title'), x.e->>'title', x.e->>'start', x.e->>'end' ORDER BY min(x.e->>'start'), x.e->>'title' LOOP
    fx := fx || g.title || ' ' || g.s || '–' || g.en || ', ' || f_agimp_days_label(g.days) || ' (itens ' || g.ns || ')' || CASE WHEN g.unc THEN ' (?)' ELSE '' END || E'\n';
  END LOOP;
  IF fx <> '' THEN
    v := v || E'\nBlocos fixos (repetem no mesmo horário):\n' || fx
      || 'Quer esses fixos na agenda? Eles entram sem aviso, só para você ver os blocos; o lembrete vem no resumo da manhã. Se não quiser, diga "sem os fixos".' || E'\n';
  END IF;
  FOR it IN SELECT x.e FROM jsonb_array_elements(r.items) AS x(e)
            WHERE x.e->>'kind' = 'task' AND coalesce((x.e->>'skip')::boolean, false) = false
            ORDER BY x.e->>'day', (x.e->>'n')::int LOOP
    d := (it->>'day')::date;
    tks := tks || (it->>'n') || '. ' || CASE WHEN coalesce((it->>'urgent')::boolean, false) THEN '🔴 ' ELSE '' END || (it->>'title')
      || ' (' || f_agimp_dow(d) || ' ' || to_char(d, 'DD/MM') || ')'
      || CASE WHEN coalesce((it->>'uncertain')::boolean, false) THEN ' (?)' ELSE '' END || E'\n';
  END LOOP;
  IF tks <> '' THEN v := v || E'\nTarefas (cada uma aparece no Google Tarefas só no dia dela)\n' || tks; END IF;
  SELECT string_agg('- ' || n, E'\n') INTO nt FROM jsonb_array_elements_text(r.notes) AS n;
  IF coalesce(nt, '') <> '' THEN v := v || E'\nNão importei:\n' || nt || E'\n'; END IF;
  v := v || E'\nItens com (?) são os que eu li com dúvida. Para corrigir, escreva por exemplo "o 3 é na segunda", "o 4 termina às 16h" ou "tira o 5". Para criar, toque em Criar tudo.';
  RETURN v;
END $$;
