-- 035: Etapa 3 da secretaria natural (spec-secretaria-natural.md, decisoes 8, 9, 10, 12).
--   (1) memoria por pessoa (agente.user_memory) + interruptores por usuario (agente.user_switches)
--   (2) estrutura Pessoas / Lugares / Memoria SEM recriar tabelas: contacts = Pessoas, places = Lugares (colunas novas + views + listagens por tipo)
--   (3) oferta de salvar pessoa/lugar novos (agente.save_offers_silenced, f_offer_*)
--   (4) sugestao proativa (agente.suggestions_log, f_suggest_pick), no maximo 1 por dia por pessoa
--   (5) gancho unico para o prompt: f_mem_prompt_txt
-- NAO foi aplicado em producao. Idempotente (CREATE ... IF NOT EXISTS / CREATE OR REPLACE / ADD COLUMN IF NOT EXISTS).
-- Sem chamada de IA no banco. Depende de: f_norm, f_ct_disp, f_ct_group_find, f_brl, tabelas users, contacts, contact_groups,
--   contact_group_members, places, fin_entries, fin_recurring, reminders.
-- Compatibilidade: nenhuma funcao f_* existente muda de assinatura. Unica funcao existente redefinida: f_resolve_invitees
--   (identica ao original, exceto que um contato SEM e-mail passa a cair em "unknown" em vez de gerar convite com e-mail vazio).
-- Dados: nada e movido ou apagado. contacts ja so guarda pessoas (e-mail validado) e places ja so guarda lugares; a duplicidade
--   que existia era de ROTEAMENTO/EXIBICAO (f_contacts desviava place_* para f_places e o texto de /contatos listava os locais).
SET search_path TO agente, public;

-- ---------------------------------------------------------------- backup (so cria uma vez; preserva o retrato original)
CREATE TABLE IF NOT EXISTS agente._bak_f11_contacts              AS SELECT * FROM agente.contacts;
CREATE TABLE IF NOT EXISTS agente._bak_f11_places                AS SELECT * FROM agente.places;
CREATE TABLE IF NOT EXISTS agente._bak_f11_contact_groups        AS SELECT * FROM agente.contact_groups;
CREATE TABLE IF NOT EXISTS agente._bak_f11_contact_group_members AS SELECT * FROM agente.contact_group_members;

-- ---------------------------------------------------------------- Pessoas e Lugares: colunas novas (sem recriar tabelas)
-- Pessoa: parentesco (ex.: "sogra") e apelidos. Pessoa sem e-mail guarda email = '' (a coluna segue NOT NULL para nao
-- quebrar as funcoes antigas, que concatenam c.email).
ALTER TABLE agente.contacts ADD COLUMN IF NOT EXISTS relation text   NOT NULL DEFAULT '';
ALTER TABLE agente.contacts ADD COLUMN IF NOT EXISTS aliases  text[] NOT NULL DEFAULT '{}';
-- Lugar: apelidos (ex.: "matriz" para "igreja"). Endereco vazio ('') = salvo sem endereco ainda.
ALTER TABLE agente.places   ADD COLUMN IF NOT EXISTS aliases  text[] NOT NULL DEFAULT '{}';

CREATE OR REPLACE VIEW agente.v_pessoas AS
  SELECT c.id, c.user_id, c.name AS nome, nullif(c.email, '') AS email, nullif(c.relation, '') AS parentesco, c.favorite AS favorito,
         c.aliases AS apelidos,
         coalesce((SELECT string_agg(g.name, ', ' ORDER BY g.name)
                     FROM agente.contact_group_members m JOIN agente.contact_groups g ON g.id = m.group_id
                    WHERE m.contact_id = c.id), '') AS grupos,
         c.created_at AS criado_em
    FROM agente.contacts c;

CREATE OR REPLACE VIEW agente.v_lugares AS
  SELECT p.id, p.user_id, p.name AS nome, nullif(p.address, '') AS endereco, p.aliases AS apelidos, p.created_at AS criado_em
    FROM agente.places p;

-- ---------------------------------------------------------------- tabelas novas
CREATE TABLE IF NOT EXISTS agente.user_switches (
  user_id            bigint PRIMARY KEY REFERENCES agente.users(id) ON DELETE CASCADE,
  mem_enabled        boolean NOT NULL DEFAULT true,
  offer_save_enabled boolean NOT NULL DEFAULT true,
  suggest_enabled    boolean NOT NULL DEFAULT true,
  updated_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS agente.user_memory (
  id         bigserial PRIMARY KEY,
  user_id    bigint NOT NULL REFERENCES agente.users(id) ON DELETE CASCADE,
  texto      text NOT NULL,
  norm       text NOT NULL,
  tipo       text NOT NULL DEFAULT 'fato' CHECK (tipo IN ('habito', 'preferencia', 'fato', 'relacao')),
  origem     text NOT NULL DEFAULT 'ia',
  criado_em  timestamptz NOT NULL DEFAULT now(),
  ultimo_uso timestamptz,
  usos       integer NOT NULL DEFAULT 0,
  ativo      boolean NOT NULL DEFAULT true
);
CREATE INDEX IF NOT EXISTS user_memory_user ON agente.user_memory (user_id, ativo, id DESC);

CREATE TABLE IF NOT EXISTS agente.save_offers_silenced (
  user_id    bigint NOT NULL REFERENCES agente.users(id) ON DELETE CASCADE,
  tipo       text NOT NULL CHECK (tipo IN ('pessoa', 'lugar')),
  norm_name  text NOT NULL,
  ate        timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, tipo, norm_name)
);

CREATE TABLE IF NOT EXISTS agente.suggestions_log (
  id         bigserial PRIMARY KEY,
  user_id    bigint NOT NULL REFERENCES agente.users(id) ON DELETE CASCADE,
  day        date NOT NULL,
  kind       text NOT NULL,
  key        text NOT NULL,
  texto      text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, day)        -- garante no maximo 1 por dia por pessoa, mesmo com chamadas concorrentes
);
CREATE INDEX IF NOT EXISTS suggestions_log_key ON agente.suggestions_log (user_id, key, created_at DESC);

-- ---------------------------------------------------------------- interruptores
CREATE OR REPLACE FUNCTION agente.f_mem_sw(p_user bigint, p_name text) RETURNS boolean
LANGUAGE sql STABLE SET search_path TO 'agente', 'public' AS $$
  SELECT coalesce((SELECT CASE p_name WHEN 'mem_enabled' THEN s.mem_enabled WHEN 'offer_save_enabled' THEN s.offer_save_enabled
                                      WHEN 'suggest_enabled' THEN s.suggest_enabled END
                     FROM agente.user_switches s WHERE s.user_id = p_user), true)
$$;

-- aceita os nomes tecnicos e apelidos em portugues
CREATE OR REPLACE FUNCTION agente.f_mem_switch_name(p_name text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente', 'public' AS $$
  SELECT CASE
    WHEN f_norm(p_name) IN ('mem enabled', 'memoria', 'memorias', 'mem', 'lembrar') OR p_name = 'mem_enabled' THEN 'mem_enabled'
    WHEN f_norm(p_name) IN ('offer save enabled', 'oferta', 'oferta de salvar', 'perguntar se salvo', 'salvar', 'offer') OR p_name = 'offer_save_enabled' THEN 'offer_save_enabled'
    WHEN f_norm(p_name) IN ('suggest enabled', 'sugestao', 'sugestoes', 'sugestao diaria', 'suggest') OR p_name = 'suggest_enabled' THEN 'suggest_enabled'
  END
$$;

CREATE OR REPLACE FUNCTION agente.f_mem_switches(p_user bigint) RETURNS jsonb
LANGUAGE sql STABLE SET search_path TO 'agente', 'public' AS $$
  SELECT jsonb_build_object('mem_enabled', f_mem_sw(p_user, 'mem_enabled'),
                            'offer_save_enabled', f_mem_sw(p_user, 'offer_save_enabled'),
                            'suggest_enabled', f_mem_sw(p_user, 'suggest_enabled'))
$$;

CREATE OR REPLACE FUNCTION agente.f_mem_set_switch(p_user bigint, p_name text, p_value boolean) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE n text := f_mem_switch_name(p_name); lbl text;
BEGIN
  IF n IS NULL OR p_value IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'nome_invalido', 'text', 'Não entendi qual recurso ligar ou desligar (memória, sugestões ou perguntar se salvo).');
  END IF;
  INSERT INTO user_switches(user_id) VALUES (p_user) ON CONFLICT (user_id) DO NOTHING;
  EXECUTE format('UPDATE user_switches SET %I = $1, updated_at = now() WHERE user_id = $2', n) USING p_value, p_user;
  lbl := CASE n WHEN 'mem_enabled' THEN 'a memória' WHEN 'offer_save_enabled' THEN 'a pergunta de salvar contatos e lugares' ELSE 'as sugestões' END;
  RETURN jsonb_build_object('ok', true, 'name', n, 'value', p_value,
           'text', CASE WHEN p_value THEN 'Pronto, liguei ' ELSE 'Pronto, desliguei ' END || lbl || '.');
END $$;

-- ---------------------------------------------------------------- memoria
CREATE OR REPLACE FUNCTION agente.f_mem_tokens(p text) RETURNS text[]
LANGUAGE sql IMMUTABLE SET search_path TO 'agente', 'public' AS $$
  SELECT coalesce(array_agg(DISTINCT s.stem), '{}')
    FROM (SELECT CASE WHEN length(w) > 4 AND w ~ 's$' THEN left(w, -1) ELSE w END AS stem
            FROM unnest(string_to_array(f_norm(p), ' ')) w
           WHERE length(w) >= 4
             AND w <> ALL (ARRAY['para','como','mais','quero','tenho','pode','poderia','esse','essa','isso','esta','este','sobre','quando',
                                 'muito','fazer','favor','preciso','amanha','hoje','marca','marcar','agenda','lembra','lembrar','lembrete',
                                 'que','com','uma','uns','umas','dos','das','nos','nas','pelo','pela','meu','minha','seu','sua','vai','ser'])) s
$$;

CREATE OR REPLACE FUNCTION agente.f_mem_tipo(p text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'agente', 'public' AS $$
  SELECT CASE f_norm(p)
    WHEN 'habito' THEN 'habito' WHEN 'habitos' THEN 'habito'
    WHEN 'preferencia' THEN 'preferencia' WHEN 'preferencias' THEN 'preferencia'
    WHEN 'relacao' THEN 'relacao' WHEN 'relacoes' THEN 'relacao' WHEN 'parentesco' THEN 'relacao'
    ELSE 'fato' END
$$;

-- Guarda um fato duradouro. Deduplicacao simples (texto igual/contido ou 80% das palavras iguais). Teto de 40 ativos por usuario:
-- ao passar, desativa os menos usados e mais antigos. Respeita mem_enabled.
CREATE OR REPLACE FUNCTION agente.f_mem_add(p_user bigint, p_texto text, p_tipo text DEFAULT 'fato', p_origem text DEFAULT 'ia') RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  v_txt text := left(btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')), 200);
  v_norm text; v_cur text; v_tipo text := f_mem_tipo(p_tipo); d user_memory%ROWTYPE; v_id bigint; v_ev int := 0; v_cap constant int := 40;
BEGIN
  IF NOT f_mem_sw(p_user, 'mem_enabled') THEN
    RETURN jsonb_build_object('ok', false, 'disabled', true, 'text', '');
  END IF;
  v_norm := f_norm(v_txt);
  IF length(v_norm) < 3 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vazio', 'text', '');
  END IF;
  DELETE FROM user_memory WHERE user_id = p_user AND NOT ativo AND coalesce(ultimo_uso, criado_em) < now() - interval '30 days';

  SELECT * INTO d FROM user_memory m
   WHERE m.user_id = p_user AND m.ativo
     AND (m.norm = v_norm
          OR (length(v_norm) >= 10 AND length(m.norm) >= 10 AND (position(v_norm IN m.norm) > 0 OR position(m.norm IN v_norm) > 0))
          OR (SELECT count(*) FROM (SELECT unnest(string_to_array(m.norm, ' ')) INTERSECT SELECT unnest(string_to_array(v_norm, ' '))) i)::numeric
             / greatest((SELECT count(*) FROM (SELECT unnest(string_to_array(m.norm, ' ')) UNION SELECT unnest(string_to_array(v_norm, ' '))) u), 1) >= 0.8)
   ORDER BY m.id LIMIT 1;
  IF FOUND THEN
    UPDATE user_memory SET ultimo_uso = now(),
           texto = CASE WHEN length(v_txt) > length(texto) AND position(norm IN v_norm) > 0 THEN v_txt ELSE texto END,
           norm  = CASE WHEN length(v_txt) > length(texto) AND position(norm IN v_norm) > 0 THEN v_norm ELSE norm END
     WHERE id = d.id RETURNING id, texto INTO v_id, v_cur;
    RETURN jsonb_build_object('ok', true, 'duplicate', true, 'id', v_id, 'text', 'Já estava anotado: ' || v_cur);
  END IF;

  -- um fato que foi esquecido e volta a ser dito: reativa a linha antiga em vez de criar outra
  SELECT id INTO v_id FROM user_memory WHERE user_id = p_user AND NOT ativo AND norm = v_norm ORDER BY id DESC LIMIT 1;
  IF v_id IS NOT NULL THEN
    UPDATE user_memory SET ativo = true, texto = v_txt, tipo = v_tipo, origem = left(coalesce(p_origem, 'ia'), 30), ultimo_uso = now() WHERE id = v_id;
  ELSE
    INSERT INTO user_memory(user_id, texto, norm, tipo, origem) VALUES (p_user, v_txt, v_norm, v_tipo, left(coalesce(p_origem, 'ia'), 30)) RETURNING id INTO v_id;
  END IF;

  WITH over AS (
    SELECT id FROM user_memory WHERE user_id = p_user AND ativo AND id <> v_id
     ORDER BY usos DESC, coalesce(ultimo_uso, criado_em) DESC, criado_em DESC OFFSET v_cap - 1)
  UPDATE user_memory SET ativo = false WHERE id IN (SELECT id FROM over);
  GET DIAGNOSTICS v_ev = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'duplicate', false, 'id', v_id, 'evicted', v_ev, 'tipo', v_tipo, 'text', 'Anotei: ' || v_txt);
END $$;

-- Ate p_max fatos relevantes a mensagem (palavras em comum primeiro) + ate 4 dos mais recentes para completar. Uma linha por fato.
-- Marca ultimo_uso/usos nos fatos que casaram (e so neles): e o que protege os uteis do descarte do teto.
CREATE OR REPLACE FUNCTION agente.f_mem_relevant_txt(p_user bigint, p_msg text, p_max int DEFAULT 8) RETURNS text
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE toks text[] := f_mem_tokens(p_msg); res text; ids bigint[]; v_max int := greatest(coalesce(p_max, 8), 1);
BEGIN
  IF NOT f_mem_sw(p_user, 'mem_enabled') THEN RETURN ''; END IF;
  WITH sc AS (
    SELECT m.id, m.texto, m.criado_em, m.ultimo_uso,
           (SELECT count(*) FROM unnest(toks) t WHERE strpos(' ' || m.norm || ' ', ' ' || t) > 0) AS s
      FROM user_memory m WHERE m.user_id = p_user AND m.ativo),
  matched AS (SELECT * FROM sc WHERE s > 0 ORDER BY s DESC, greatest(criado_em, coalesce(ultimo_uso, criado_em)) DESC, id DESC LIMIT v_max),
  recent  AS (SELECT * FROM sc WHERE s = 0 ORDER BY greatest(criado_em, coalesce(ultimo_uso, criado_em)) DESC, id DESC
               LIMIT least(4, greatest(v_max - (SELECT count(*) FROM matched), 0))),
  u AS (SELECT 0 AS grp, row_number() OVER (ORDER BY s DESC, id DESC) AS ord, id, texto FROM matched
        UNION ALL
        SELECT 1, row_number() OVER (ORDER BY id DESC), id, texto FROM recent)
  SELECT string_agg('- ' || texto, E'\n' ORDER BY grp, ord), array_agg(id) FILTER (WHERE grp = 0) INTO res, ids FROM u;
  IF ids IS NOT NULL THEN
    UPDATE user_memory SET ultimo_uso = now(), usos = usos + 1 WHERE id = ANY (ids);
  END IF;
  RETURN coalesce(res, '');
END $$;

-- Gancho unico do prompt. Devolve '' se a memoria esta desligada ou nao ha fatos. Concatenar ao fim da query "Buscar usuario".
CREATE OR REPLACE FUNCTION agente.f_mem_prompt_txt(p_user bigint, p_msg text) RETURNS text
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE t text;
BEGIN
  IF NOT f_mem_sw(p_user, 'mem_enabled') THEN RETURN ''; END IF;
  t := f_mem_relevant_txt(p_user, p_msg, 8);
  IF t = '' THEN RETURN ''; END IF;
  RETURN 'MEMORIA (fatos duradouros sobre o usuario; use so se ajudarem neste pedido):' || E'\n' || t;
EXCEPTION WHEN others THEN
  RETURN '';
END $$;

-- ---------------------------------------------------------------- listagens por tipo
CREATE OR REPLACE FUNCTION agente.f_list_pessoas(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE r record; t text; g text; nc int; ng int;
BEGIN
  SELECT count(*) INTO nc FROM contacts WHERE user_id = p_user;
  SELECT count(*) INTO ng FROM contact_groups WHERE user_id = p_user;
  t := 'Pessoas (' || nc || '):';
  IF nc = 0 THEN t := t || E'\n- nenhuma ainda. Ex.: "salva o e-mail da Claudia: claudia@x.com"'; END IF;
  FOR r IN SELECT c.name, c.email, c.favorite, c.relation,
                  (SELECT string_agg(f_ct_disp(a), ', ') FROM unnest(c.aliases) a) AS apelidos
             FROM contacts c WHERE c.user_id = p_user ORDER BY c.favorite DESC, c.name LOOP
    t := t || E'\n- ' || f_ct_disp(r.name)
         || CASE WHEN r.relation <> '' THEN ' (' || r.relation || ')' ELSE '' END
         || CASE WHEN r.favorite THEN ' (favorito)' ELSE '' END
         || CASE WHEN r.email <> '' THEN ' - ' || r.email ELSE ' - sem e-mail' END
         || CASE WHEN r.apelidos IS NOT NULL THEN ' [apelidos: ' || r.apelidos || ']' ELSE '' END;
  END LOOP;
  g := 'Grupos (' || ng || '):';
  IF ng = 0 THEN g := g || E'\n- nenhum ainda. Ex.: "cria o grupo família com Ana e Bia"'; END IF;
  FOR r IN SELECT cg.name, (SELECT string_agg(f_ct_disp(ct.name), ', ' ORDER BY ct.name)
                              FROM contact_group_members m JOIN contacts ct ON ct.id = m.contact_id WHERE m.group_id = cg.id) AS membros
             FROM contact_groups cg WHERE cg.user_id = p_user ORDER BY cg.name LOOP
    g := g || E'\n- ' || f_ct_disp(r.name) || ': ' || coalesce(r.membros, 'sem ninguém');
  END LOOP;
  RETURN jsonb_build_object('text', t || E'\n\n' || g, 'pessoas', nc, 'grupos', ng);
END $$;

CREATE OR REPLACE FUNCTION agente.f_list_lugares(p_user bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE r record; t text; n int;
BEGIN
  SELECT count(*) INTO n FROM places WHERE user_id = p_user;
  t := 'Lugares (' || n || '):';
  IF n = 0 THEN t := t || E'\n- nenhum ainda. Ex.: "o local igreja é Rua das Flores, 120"'; END IF;
  FOR r IN SELECT name, address, (SELECT string_agg(f_ct_disp(a), ', ') FROM unnest(aliases) a) AS apelidos
             FROM places WHERE user_id = p_user ORDER BY name LOOP
    t := t || E'\n- ' || f_ct_disp(r.name) || ': ' || CASE WHEN r.address <> '' THEN r.address ELSE 'sem endereço ainda' END
         || CASE WHEN r.apelidos IS NOT NULL THEN ' [apelidos: ' || r.apelidos || ']' ELSE '' END;
  END LOOP;
  RETURN jsonb_build_object('text', t, 'lugares', n);
END $$;

-- /memoria: tudo (pessoas, lugares e fatos) com filtro. filtro: '' | pessoas | lugares | memoria | habito | preferencia | fato | relacao | texto livre.
-- items traz so os fatos da memoria (id + tipo + texto) para o workflow montar botoes/apagar por id.
CREATE OR REPLACE FUNCTION agente.f_mem_list(p_user bigint, p_filtro text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE
  fl text := f_norm(p_filtro); vp boolean := false; vl boolean := false; vm boolean := false; v_tipo text; v_q text;
  t text := ''; r record; n int; items jsonb := '[]'::jsonb; np int := 0; nl int := 0; nm int := 0; sec text;
BEGIN
  IF fl IN ('', 'tudo', 'todos', 'todas', 'tudo tudo') THEN vp := true; vl := true; vm := true;
  ELSIF fl IN ('pessoa', 'pessoas', 'contato', 'contatos', 'grupo', 'grupos') THEN vp := true;
  ELSIF fl IN ('lugar', 'lugares', 'local', 'locais') THEN vl := true;
  ELSIF fl IN ('memoria', 'memorias', 'anotacoes', 'anotacao') THEN vm := true;
  ELSIF fl IN ('habito', 'habitos', 'preferencia', 'preferencias', 'fato', 'fatos', 'relacao', 'relacoes', 'parentesco') THEN vm := true; v_tipo := f_mem_tipo(fl);
  ELSE vp := true; vl := true; vm := true; v_q := fl;
  END IF;

  IF vp THEN
    sec := '';
    FOR r IN SELECT c.name, c.email, c.relation FROM contacts c
              WHERE c.user_id = p_user AND (v_q IS NULL OR f_norm(c.name || ' ' || c.email || ' ' || c.relation || ' ' || array_to_string(c.aliases, ' ')) LIKE '%' || v_q || '%')
              ORDER BY c.favorite DESC, c.name LOOP
      np := np + 1;
      sec := sec || E'\n- ' || f_ct_disp(r.name) || CASE WHEN r.relation <> '' THEN ' (' || r.relation || ')' ELSE '' END || CASE WHEN r.email <> '' THEN ' - ' || r.email ELSE '' END;
    END LOOP;
    IF v_q IS NULL OR np > 0 THEN t := t || 'Pessoas (' || np || '):' || CASE WHEN np = 0 THEN E'\n- nenhuma' ELSE sec END || E'\n\n'; END IF;
  END IF;
  IF vl THEN
    sec := '';
    FOR r IN SELECT p.name, p.address FROM places p
              WHERE p.user_id = p_user AND (v_q IS NULL OR f_norm(p.name || ' ' || p.address || ' ' || array_to_string(p.aliases, ' ')) LIKE '%' || v_q || '%')
              ORDER BY p.name LOOP
      nl := nl + 1;
      sec := sec || E'\n- ' || f_ct_disp(r.name) || ': ' || CASE WHEN r.address <> '' THEN r.address ELSE 'sem endereço ainda' END;
    END LOOP;
    IF v_q IS NULL OR nl > 0 THEN t := t || 'Lugares (' || nl || '):' || CASE WHEN nl = 0 THEN E'\n- nenhum' ELSE sec END || E'\n\n'; END IF;
  END IF;
  IF vm THEN
    sec := '';
    FOR r IN SELECT m.id, m.tipo, m.texto FROM user_memory m
              WHERE m.user_id = p_user AND m.ativo AND (v_tipo IS NULL OR m.tipo = v_tipo) AND (v_q IS NULL OR m.norm LIKE '%' || v_q || '%')
              ORDER BY m.tipo, m.id LOOP
      nm := nm + 1;
      items := items || jsonb_build_array(jsonb_build_object('id', r.id, 'tipo', r.tipo, 'texto', r.texto));
      sec := sec || E'\n- #' || r.id || ' ' || r.texto || ' (' || CASE r.tipo WHEN 'habito' THEN 'hábito' WHEN 'preferencia' THEN 'preferência' WHEN 'relacao' THEN 'relação' ELSE 'fato' END || ')';
    END LOOP;
    IF v_q IS NULL OR nm > 0 THEN
      t := t || 'Memória' || CASE WHEN v_tipo IS NOT NULL THEN ' (' || v_tipo || ')' ELSE '' END || ' (' || nm || '):'
             || CASE WHEN nm = 0 THEN E'\n- nada ainda' ELSE sec END || E'\n\n';
    END IF;
  END IF;
  t := btrim(t, E'\n ');
  IF t = '' THEN t := 'Não achei nada com "' || btrim(p_filtro) || '".'; END IF;
  IF vm AND nm > 0 THEN t := t || E'\n\nPara apagar um fato: "esquece o #' || (items->0->>'id') || '" ou "esquece que ...".'; END IF;
  RETURN jsonb_build_object('text', t, 'total', np + nl + nm, 'pessoas', np, 'lugares', nl, 'memoria', nm, 'items', items,
                            'switches', f_mem_switches(p_user));
END $$;

-- Apaga (desativa) um fato da memoria do usuario. p_ref = id (numero ou #numero), texto parcial, ou ''/'isso'/'ultimo' = o ultimo anotado.
-- Mais de um candidato: nao apaga, devolve ambiguous com ids para perguntar qual.
CREATE OR REPLACE FUNCTION agente.f_mem_forget(p_user bigint, p_ref text) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  ref text := btrim(coalesce(p_ref, '')); q text; v_id bigint; ids bigint[]; cand jsonb; n int; toks text[]; d user_memory%ROWTYPE;
BEGIN
  IF ref ~ '^#?[0-9]+$' THEN
    UPDATE user_memory SET ativo = false WHERE id = ltrim(ref, '#')::bigint AND user_id = p_user AND ativo RETURNING id INTO v_id;
    IF v_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'found', false, 'text', 'Não achei esse item na sua memória.'); END IF;
    SELECT * INTO d FROM user_memory WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'found', true, 'removed', jsonb_build_array(d.texto), 'text', 'Esqueci: ' || d.texto);
  END IF;

  q := f_norm(ref);
  IF q IN ('', 'isso', 'esse', 'essa', 'ultimo', 'o ultimo', 'esse ultimo', 'isso ai') THEN
    UPDATE user_memory SET ativo = false
     WHERE id = (SELECT id FROM user_memory WHERE user_id = p_user AND ativo ORDER BY id DESC LIMIT 1) AND user_id = p_user
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'found', false, 'text', 'Não tenho nada na memória para esquecer.'); END IF;
    SELECT * INTO d FROM user_memory WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'found', true, 'removed', jsonb_build_array(d.texto), 'text', 'Esqueci: ' || d.texto);
  END IF;

  toks := f_mem_tokens(ref);
  SELECT array_agg(m.id ORDER BY m.id) INTO ids FROM user_memory m
   WHERE m.user_id = p_user AND m.ativo
     AND (m.norm LIKE '%' || q || '%'
          OR (cardinality(toks) > 0 AND NOT EXISTS (SELECT 1 FROM unnest(toks) t WHERE strpos(' ' || m.norm || ' ', ' ' || t) = 0)));
  n := coalesce(cardinality(ids), 0);
  IF n = 0 THEN RETURN jsonb_build_object('ok', false, 'found', false, 'text', 'Não achei isso na sua memória. Veja com /memoria.'); END IF;
  IF n > 1 THEN
    SELECT jsonb_agg(jsonb_build_object('id', m.id, 'texto', m.texto) ORDER BY m.id) INTO cand FROM user_memory m WHERE m.id = ANY (ids[1:8]);
    RETURN jsonb_build_object('ok', false, 'found', true, 'count', n, 'ambiguous', cand,
             'text', 'Achei ' || n || ': ' || (SELECT string_agg('#' || m.id || ' ' || m.texto, '; ' ORDER BY m.id) FROM user_memory m WHERE m.id = ANY (ids[1:5]))
                     || CASE WHEN n > 5 THEN ' (e mais ' || (n - 5) || ')' ELSE '' END || '. Qual eu esqueço?');
  END IF;
  UPDATE user_memory SET ativo = false WHERE id = ids[1] RETURNING * INTO d;
  RETURN jsonb_build_object('ok', true, 'found', true, 'removed', jsonb_build_array(d.texto), 'text', 'Esqueci: ' || d.texto);
END $$;

-- ---------------------------------------------------------------- busca tolerante de pessoa e de lugar (acento, caixa, apelido, nome parcial unico)
CREATE OR REPLACE FUNCTION agente.f_find_pessoa(p_user bigint, p_name text) RETURNS bigint
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE n text := regexp_replace(f_norm(p_name), '^(a|o|as|os) ', ''); v bigint; k int;
BEGIN
  IF n = '' THEN RETURN NULL; END IF;
  SELECT c.id INTO v FROM contacts c
   WHERE c.user_id = p_user AND (f_norm(c.name) = n OR EXISTS (SELECT 1 FROM unnest(c.aliases) a WHERE f_norm(a) = n))
   ORDER BY c.id LIMIT 1;
  IF v IS NOT NULL THEN RETURN v; END IF;
  SELECT count(*), min(c.id) INTO k, v FROM contacts c
   WHERE c.user_id = p_user AND (f_norm(c.name) LIKE n || ' %' OR n LIKE f_norm(c.name) || ' %');
  IF k = 1 THEN RETURN v; END IF;
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION agente.f_find_lugar(p_user bigint, p_name text) RETURNS bigint
LANGUAGE plpgsql STABLE SET search_path TO 'agente', 'public' AS $$
DECLARE n text := regexp_replace(f_norm(p_name), '^(a|o|na|no|da|do|de|em|as|os) ', ''); v bigint; k int;
BEGIN
  IF n = '' THEN RETURN NULL; END IF;
  SELECT p.id INTO v FROM places p
   WHERE p.user_id = p_user AND (p.norm_name = n OR EXISTS (SELECT 1 FROM unnest(p.aliases) a WHERE f_norm(a) = n))
   ORDER BY p.id LIMIT 1;
  IF v IS NOT NULL THEN RETURN v; END IF;
  SELECT count(*), min(p.id) INTO k, v FROM places p
   WHERE p.user_id = p_user AND (p.norm_name LIKE n || ' %' OR n LIKE p.norm_name || ' %');
  IF k = 1 THEN RETURN v; END IF;
  RETURN NULL;
END $$;

-- ---------------------------------------------------------------- oferta de salvar
-- Diz, para a pessoa e o lugar que apareceram na tarefa, se vale oferecer salvar. Nao grava nada.
-- status: new | exists | silenced | self | group | none (nome vazio). offer = true so se houver algo "new" e a oferta estiver ligada.
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

-- "Sim": salva (ou completa) a pessoa e/ou o lugar. E-mail, endereco e parentesco opcionais. Chamar de novo com o e-mail/endereco
-- que o usuario mandar depois completa o registro (nao duplica).
CREATE OR REPLACE FUNCTION agente.f_offer_accept(p_user bigint, p_pessoa text DEFAULT '', p_email text DEFAULT '', p_lugar text DEFAULT '',
                                                 p_endereco text DEFAULT '', p_parentesco text DEFAULT '') RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  pn text := lower(left(btrim(coalesce(p_pessoa, '')), 80)); em text := lower(btrim(coalesce(p_email, '')));
  ln text := btrim(regexp_replace(btrim(coalesce(p_lugar, '')), '^(a|o|na|no|da|do|de|em) ', '', 'i')); ad text := left(btrim(coalesce(p_endereco, '')), 200);
  rel text := left(btrim(coalesce(p_parentesco, '')), 40);
  pid bigint; lid bigint; pres jsonb := NULL; lres jsonb := NULL; mail_bad boolean := false; parts text[] := '{}'; c contacts%ROWTYPE; pl places%ROWTYPE;
BEGIN
  IF em <> '' AND em !~ '^[^@ ]+@[^@ ]+\.[^@ ]+$' THEN mail_bad := true; em := ''; END IF;

  IF pn <> '' THEN
    pid := f_find_pessoa(p_user, pn);
    IF pid IS NULL THEN
      INSERT INTO contacts(user_id, name, email, relation) VALUES (p_user, pn, em, rel)
      ON CONFLICT (user_id, name) DO UPDATE SET email = CASE WHEN EXCLUDED.email <> '' THEN EXCLUDED.email ELSE contacts.email END,
                                                relation = CASE WHEN EXCLUDED.relation <> '' THEN EXCLUDED.relation ELSE contacts.relation END
      RETURNING * INTO c;
      pres := jsonb_build_object('status', 'created', 'id', c.id, 'name', c.name, 'email', nullif(c.email, ''), 'parentesco', nullif(c.relation, ''));
      parts := parts || ('Salvei ' || f_ct_disp(c.name) || ' nos contatos' || CASE WHEN c.email = '' THEN ' (sem e-mail)' ELSE ' (' || c.email || ')' END);
    ELSE
      UPDATE contacts SET email = CASE WHEN em <> '' THEN em ELSE email END, relation = CASE WHEN rel <> '' THEN rel ELSE relation END
       WHERE id = pid AND user_id = p_user RETURNING * INTO c;
      pres := jsonb_build_object('status', 'updated', 'id', c.id, 'name', c.name, 'email', nullif(c.email, ''), 'parentesco', nullif(c.relation, ''));
      parts := parts || ('Atualizei ' || f_ct_disp(c.name) || CASE WHEN c.email <> '' THEN ' (' || c.email || ')' ELSE '' END);
    END IF;
    DELETE FROM save_offers_silenced WHERE user_id = p_user AND tipo = 'pessoa' AND norm_name = regexp_replace(f_norm(pn), '^(a|o|as|os) ', '');
  END IF;

  IF ln <> '' THEN
    lid := f_find_lugar(p_user, ln);
    IF lid IS NULL THEN
      INSERT INTO places(user_id, name, norm_name, address) VALUES (p_user, lower(left(ln, 60)), f_norm(left(ln, 60)), ad)
      ON CONFLICT (user_id, norm_name) DO UPDATE SET address = CASE WHEN EXCLUDED.address <> '' THEN EXCLUDED.address ELSE places.address END
      RETURNING * INTO pl;
      lres := jsonb_build_object('status', 'created', 'id', pl.id, 'name', pl.name, 'address', nullif(pl.address, ''));
      parts := parts || ('salvei o lugar ' || pl.name || CASE WHEN pl.address = '' THEN ' (sem endereço)' ELSE ': ' || pl.address END);
    ELSE
      UPDATE places SET address = CASE WHEN ad <> '' THEN ad ELSE address END WHERE id = lid AND user_id = p_user RETURNING * INTO pl;
      lres := jsonb_build_object('status', 'updated', 'id', pl.id, 'name', pl.name, 'address', nullif(pl.address, ''));
      parts := parts || ('atualizei o lugar ' || pl.name || CASE WHEN pl.address <> '' THEN ': ' || pl.address ELSE '' END);
    END IF;
    DELETE FROM save_offers_silenced WHERE user_id = p_user AND tipo = 'lugar' AND norm_name = f_norm(left(ln, 60));
  END IF;

  IF pres IS NULL AND lres IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'nada_para_salvar', 'text', 'Não entendi o que salvar. Me diga o nome da pessoa ou do lugar.');
  END IF;
  RETURN jsonb_build_object('ok', true, 'person', pres, 'place', lres, 'email_invalid', mail_bad,
           'text', upper(left(array_to_string(parts, ' e '), 1)) || substr(array_to_string(parts, ' e '), 2) || '.'
                   || CASE WHEN mail_bad THEN ' Esse e-mail não parece válido; me manda de novo se quiser guardar.' ELSE '' END);
END $$;

-- "Nao": silencia a pessoa e/ou o lugar por 30 dias.
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

-- Convites: contato SEM e-mail nao pode virar convidado. Igual ao original, mas cai em "unknown" (o bot pede o e-mail).
CREATE OR REPLACE FUNCTION agente.f_resolve_invitees(p_user bigint, p_names text[]) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE n text; found jsonb := '[]'; unknown text[] := '{}'; g bigint; cid bigint;
BEGIN
  FOREACH n IN ARRAY COALESCE(p_names, '{}') LOOP
    n := lower(trim(COALESCE(n, '')));
    IF n = '' THEN CONTINUE; END IF;
    g := f_ct_group_find(p_user, n);
    IF g IS NOT NULL THEN
      found := found || COALESCE((SELECT jsonb_agg(jsonb_build_object('name', c.name, 'email', c.email) ORDER BY c.name)
        FROM contact_group_members m JOIN contacts c ON c.id = m.contact_id WHERE m.group_id = g AND c.email <> ''), '[]'::jsonb);
      CONTINUE;
    END IF;
    cid := f_ct_find(p_user, n);
    IF cid IS NOT NULL AND EXISTS (SELECT 1 FROM contacts WHERE id = cid AND email <> '') THEN
      found := found || (SELECT jsonb_build_array(jsonb_build_object('name', name, 'email', email)) FROM contacts WHERE id = cid);
    ELSIF n ~ '^[^@ ]+@[^@ ]+\.[^@ ]+$' THEN
      found := found || jsonb_build_array(jsonb_build_object('name', n, 'email', n));
    ELSE unknown := unknown || n; END IF;
  END LOOP;
  RETURN jsonb_build_object('invitees', found, 'unknown', to_jsonb(unknown));
END $$;

-- ---------------------------------------------------------------- sugestao proativa
-- No maximo 1 por dia por usuario (UNIQUE user_id+day em suggestions_log). Padroes (so dados que ja existem):
--   conta: gasto com a mesma descricao em 3+ meses, no mesmo dia do mes (variacao ate 4 dias), sem lancamento neste mes,
--          sem conta fixa cadastrada, e hoje ja e (ou passou pouco) o dia tipico;
--   lembrete: mesmo titulo criado 3+ vezes nos ultimos 60 dias, sem repeticao configurada.
-- Nao repete a mesma sugestao (key) em 30 dias. Respeita suggest_enabled. Chamar e CONSOME a vez do dia, salvo p_dry = true.
CREATE OR REPLACE FUNCTION agente.f_suggest_pick(p_user bigint, p_dry boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SET search_path TO 'agente', 'public' AS $$
DECLARE
  tz text; v_today date; v_dom int; r record; v_kind text; v_key text; v_txt text; v_data jsonb; v_n int;
  dias text[] := ARRAY['domingos', 'segundas', 'terças', 'quartas', 'quintas', 'sextas', 'sábados'];
BEGIN
  IF NOT f_mem_sw(p_user, 'suggest_enabled') THEN RETURN jsonb_build_object('suggest', false, 'reason', 'disabled'); END IF;
  SELECT coalesce(nullif(timezone, ''), 'America/Sao_Paulo') INTO tz FROM users WHERE id = p_user;
  IF tz IS NULL THEN RETURN jsonb_build_object('suggest', false, 'reason', 'no_user'); END IF;
  v_today := (now() AT TIME ZONE tz)::date; v_dom := extract(day FROM v_today)::int;
  IF EXISTS (SELECT 1 FROM suggestions_log WHERE user_id = p_user AND day = v_today) THEN
    RETURN jsonb_build_object('suggest', false, 'reason', 'already_today');
  END IF;

  -- (a) conta que costuma aparecer todo mes
  SELECT x.norm_desc, x.descr, x.dia, x.valor, x.meses INTO r
    FROM (SELECT e.norm_desc,
                 (array_agg(e.description ORDER BY e.d DESC))[1] AS descr,
                 count(DISTINCT date_trunc('month', e.d)) AS meses,
                 percentile_disc(0.5) WITHIN GROUP (ORDER BY extract(day FROM e.d)) ::int AS dia,
                 max(extract(day FROM e.d)) - min(extract(day FROM e.d)) AS spread,
                 percentile_disc(0.5) WITHIN GROUP (ORDER BY e.amount) AS valor,
                 max(e.d) AS ultimo
            FROM (SELECT fe.norm_desc, fe.description, fe.amount, coalesce(fe.due_on, fe.occurred_on) AS d
                    FROM fin_entries fe
                   WHERE fe.user_id = p_user AND fe.kind = 'expense' AND fe.status IN ('paid', 'pending')
                     AND fe.recurring_id IS NULL AND coalesce(fe.installments, 1) <= 1 AND coalesce(fe.installment_no, 1) = 1
                     AND coalesce(fe.due_on, fe.occurred_on) >= date_trunc('month', v_today)::date - interval '6 months'
                     AND coalesce(fe.due_on, fe.occurred_on) <  date_trunc('month', v_today)::date) e
           GROUP BY e.norm_desc) x
   WHERE x.meses >= 3 AND x.spread <= 4 AND x.ultimo >= v_today - 75
     AND v_dom >= x.dia - 2 AND v_dom <= x.dia + 10
     AND NOT EXISTS (SELECT 1 FROM fin_entries t WHERE t.user_id = p_user AND t.norm_desc = x.norm_desc
                        AND coalesce(t.due_on, t.occurred_on) >= date_trunc('month', v_today)::date
                        AND coalesce(t.due_on, t.occurred_on) <  (date_trunc('month', v_today) + interval '1 month')::date)
     AND NOT EXISTS (SELECT 1 FROM fin_recurring fr WHERE fr.user_id = p_user AND fr.active AND f_norm(fr.description) = x.norm_desc)
     AND NOT EXISTS (SELECT 1 FROM suggestions_log s WHERE s.user_id = p_user AND s.key = 'conta:' || x.norm_desc AND s.created_at > now() - interval '30 days')
   ORDER BY x.meses DESC, x.ultimo DESC LIMIT 1;
  IF FOUND THEN
    v_kind := 'conta'; v_key := 'conta:' || r.norm_desc;
    v_txt := initcap(r.descr) || ' costuma cair no dia ' || r.dia || ' (em geral ' || f_brl(r.valor) || '). Já cadastro este mês?';
    v_data := jsonb_build_object('description', r.descr, 'day', r.dia, 'amount', r.valor, 'months', r.meses);
  ELSE
    -- (b) lembrete que sempre se repete e ainda nao tem repeticao
    SELECT x.nt, x.titulo, x.n, x.dows INTO r
      FROM (SELECT f_norm(rm.title) AS nt, (array_agg(rm.title ORDER BY rm.created_at DESC))[1] AS titulo, count(*) AS n,
                   array_agg(DISTINCT extract(dow FROM rm.due_at AT TIME ZONE tz)::int) AS dows
              FROM reminders rm
             WHERE rm.user_id = p_user AND rm.kind = 'reminder' AND rm.repeat_rule IS NULL AND rm.repeat_of IS NULL AND rm.card_id IS NULL
                   AND rm.status <> 'cancelled' AND rm.due_at IS NOT NULL AND rm.created_at > now() - interval '60 days'
             GROUP BY f_norm(rm.title) HAVING count(*) >= 3) x
     WHERE x.nt <> ''
       AND NOT EXISTS (SELECT 1 FROM reminders q WHERE q.user_id = p_user AND f_norm(q.title) = x.nt AND q.repeat_rule IS NOT NULL AND q.status IN ('pending', 'awaiting_time'))
       AND NOT EXISTS (SELECT 1 FROM suggestions_log s WHERE s.user_id = p_user AND s.key = 'lembrete:' || x.nt AND s.created_at > now() - interval '30 days')
     ORDER BY x.n DESC LIMIT 1;
    IF FOUND THEN
      v_kind := 'lembrete'; v_key := 'lembrete:' || r.nt;
      v_txt := 'Você já criou "' || r.titulo || '" ' || r.n || ' vezes nos últimos dois meses. Quer que eu deixe repetir sozinho'
               || CASE WHEN cardinality(r.dows) = 1 THEN ' toda semana, às ' || dias[r.dows[1] + 1] ELSE '' END || '?';
      v_data := jsonb_build_object('title', r.titulo, 'times', r.n, 'weekday', CASE WHEN cardinality(r.dows) = 1 THEN r.dows[1] END);
    END IF;
  END IF;

  IF v_kind IS NULL THEN RETURN jsonb_build_object('suggest', false, 'reason', 'no_pattern'); END IF;
  IF NOT p_dry THEN
    INSERT INTO suggestions_log(user_id, day, kind, key, texto) VALUES (p_user, v_today, v_kind, v_key, v_txt) ON CONFLICT (user_id, day) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n = 0 THEN RETURN jsonb_build_object('suggest', false, 'reason', 'already_today'); END IF;
  END IF;
  RETURN jsonb_build_object('suggest', true, 'kind', v_kind, 'key', v_key, 'text', v_txt, 'data', v_data, 'dry', p_dry);
END $$;
