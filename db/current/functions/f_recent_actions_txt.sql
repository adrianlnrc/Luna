-- GERADO por db/current/build_current.py. NAO EDITAR: edite uma nova migracao e rode o script.
-- Funcao: agente.f_recent_actions_txt(p_user bigint)
-- Origem da definicao atual: 033_acoes_recentes.sql (linha 113)
-- Definicoes (migracao:linha), da mais antiga a atual: 033_acoes_recentes.sql:113
CREATE OR REPLACE FUNCTION agente.f_recent_actions_txt(p_user bigint) RETURNS text
LANGUAGE sql STABLE SET search_path TO 'agente', 'public' AS $$
  SELECT string_agg(
           '[' || s.id || '] ' ||
           CASE s.kind WHEN 'reminder' THEN 'lembrete' WHEN 'event' THEN 'compromisso' WHEN 'expense' THEN 'gasto'
                       WHEN 'note' THEN 'nota' WHEN 'task' THEN 'tarefa' ELSE s.kind END ||
           ': ' || s.label || ' (ha ' ||
           CASE WHEN now() - s.created_at < interval '60 minutes' THEN greatest(1, floor(extract(epoch FROM now() - s.created_at) / 60)::int) || ' min'
                ELSE floor(extract(epoch FROM now() - s.created_at) / 3600)::int || ' h' END || ')',
           E'\n' ORDER BY s.id DESC)
    FROM (SELECT id, kind, label, created_at FROM agente.recent_actions
           WHERE user_id = p_user AND NOT undone AND kind <> 'list_item' AND created_at > now() - interval '24 hours'
           ORDER BY id DESC LIMIT 10) s
$$;
