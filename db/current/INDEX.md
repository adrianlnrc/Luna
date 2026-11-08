# Indice de funcoes (gerado, nao editar)

Gerado por `build_current.py`. Colunas: arquivo, assinatura (tipos IN), migracao da definicao atual, numero de definicoes ao longo do historico.

| arquivo | assinatura | origem atual | defs | obs |
|---|---|---|---|---|
| f_ag_cal.sql | f_ag_cal(agenda_pending, text) | 012_agenda.sql:331 | 1 |  |
| f_ag_confirm.sql | f_ag_confirm(bigint) | 012_agenda.sql:130 | 1 |  |
| f_ag_dayname.sql | f_ag_dayname(date) | 012_agenda.sql:54 | 1 |  |
| f_ag_fmt.sql | f_ag_fmt(timestamp with time zone, text) | 012_agenda.sql:60 | 1 |  |
| f_ag_iso.sql | f_ag_iso(timestamp with time zone) | 012_agenda.sql:49 | 1 |  |
| f_ag_links.sql | f_ag_links(bigint, text, text, text, timestamp with time zone, text) | 012_agenda.sql:83 | 1 |  |
| f_ag_match.sql | f_ag_match(text, text) | 012_agenda.sql:66 | 1 |  |
| f_ag_ts.sql | f_ag_ts(text) | 012_agenda.sql:41 | 1 |  |
| f_agenda_after_create.sql | f_agenda_after_create(bigint, jsonb, jsonb) | 012_agenda.sql:527 | 1 |  |
| f_agenda_cb.sql | f_agenda_cb(bigint, text) | 012_agenda.sql:359 | 1 |  |
| f_agenda_db.sql | f_agenda_db(bigint, timestamp with time zone, timestamp with time zone) | 003_functions.sql:179 | 1 |  |
| f_agenda_done.sql | f_agenda_done(bigint, bigint, jsonb) | 012_agenda.sql:433 | 1 |  |
| f_agenda_invites.sql | f_agenda_invites(bigint, text, jsonb) | 012_agenda.sql:654 | 1 |  |
| f_agenda_manage.sql | f_agenda_manage(bigint, jsonb) | 012_agenda.sql:162 | 1 |  |
| f_agimp_cb.sql | f_agimp_cb(bigint, text) | 031_agenda_import.sql:222 | 1 |  |
| f_agimp_confirm.sql | f_agimp_confirm(bigint, bigint) | 032_resumo_enxuto.sql:146 | 2 |  |
| f_agimp_create.sql | f_agimp_create(bigint, jsonb) | 032_resumo_enxuto.sql:106 | 2 |  |
| f_agimp_days_label.sql | f_agimp_days_label(date[]) | 032_resumo_enxuto.sql:39 | 1 |  |
| f_agimp_done.sql | f_agimp_done(bigint, bigint, jsonb) | 032_resumo_enxuto.sql:201 | 2 |  |
| f_agimp_dow.sql | f_agimp_dow(date) | 031_agenda_import.sql:23 | 1 |  |
| f_agimp_edit.sql | f_agimp_edit(bigint, jsonb) | 032_resumo_enxuto.sql:180 | 1 |  |
| f_agimp_edit_pre_m9.sql | f_agimp_edit_pre_m9(bigint, jsonb) | 031_agenda_import.sql:132 | 1 | renomeada de f_agimp_edit (032_resumo_enxuto.sql) |
| f_agimp_iso.sql | f_agimp_iso(date, text, text) | 031_agenda_import.sql:29 | 1 |  |
| f_agimp_mark_fixed.sql | f_agimp_mark_fixed(jsonb) | 032_resumo_enxuto.sql:24 | 1 |  |
| f_agimp_render.sql | f_agimp_render(bigint) | 032_resumo_enxuto.sql:55 | 2 |  |
| f_agimp_tasks_due.sql | f_agimp_tasks_due(bigint) | 032_resumo_enxuto.sql:225 | 1 |  |
| f_agimp_tasks_mark.sql | f_agimp_tasks_mark(bigint, jsonb) | 032_resumo_enxuto.sql:236 | 1 |  |
| f_ai_brl.sql | f_ai_brl(numeric) | 028_custo_ia_anuais.sql:56 | 1 |  |
| f_ai_cost_text.sql | f_ai_cost_text(bigint) | 028_custo_ia_anuais.sql:64 | 1 |  |
| f_ai_groups.sql | f_ai_groups(bigint) | 021_locais_comandos.sql:89 | 1 |  |
| f_ai_log.sql | f_ai_log(bigint, text, text, integer, integer, boolean) | 028_custo_ia_anuais.sql:41 | 1 |  |
| f_ai_num.sql | f_ai_num(numeric) | 028_custo_ia_anuais.sql:61 | 1 |  |
| f_ai_places.sql | f_ai_places(bigint) | 021_locais_comandos.sql:84 | 1 |  |
| f_batch_open.sql | f_batch_open(bigint) | 033_acoes_recentes.sql:36 | 1 |  |
| f_batch_undo.sql | f_batch_undo(bigint, bigint) | 033_acoes_recentes.sql:237 | 1 |  |
| f_brl.sql | f_brl(numeric) | 008_financas.sql:73 | 1 |  |
| f_callback.sql | f_callback(bigint, text) | 033_acoes_recentes.sql:356 | 1 |  |
| f_callback_base.sql | f_callback_base(bigint, text) | 008_financas.sql:656 | 3 | renomeada de f_callback (011b_base_agenda.sql) |
| f_callback_pre_f10.sql | f_callback_pre_f10(bigint, text) | 031_agenda_import.sql:237 | 2 | renomeada de f_callback (033_acoes_recentes.sql) |
| f_callback_pre_f6.sql | f_callback_pre_f6(bigint, text) | 023_locais_pergunta.sql:210 | 1 | renomeada de f_callback (024_ciclo_correcoes.sql) |
| f_callback_pre_m2.sql | f_callback_pre_m2(bigint, text) | 024_ciclo_correcoes.sql:148 | 1 | renomeada de f_callback (026_recibo_alertas.sql) |
| f_callback_pre_menu.sql | f_callback_pre_menu(bigint, text) | 011b_base_agenda.sql:29 | 1 | renomeada de f_callback (022_menu.sql) |
| f_callback_pre_places.sql | f_callback_pre_places(bigint, text) | 022_menu.sql:51 | 1 | renomeada de f_callback (023_locais_pergunta.sql) |
| f_card_action.sql | f_card_action(bigint, jsonb) | 013_extras.sql:491 | 1 |  |
| f_card_alert_sync.sql | f_card_alert_sync(bigint) | 013_extras.sql:140 | 1 |  |
| f_card_alert_title.sql | f_card_alert_title(bigint, timestamp with time zone) | 013_extras.sql:123 | 1 |  |
| f_card_alerts_user.sql | f_card_alerts_user(bigint) | 026_recibo_alertas.sql:80 | 1 |  |
| f_card_close_gt.sql | f_card_close_gt(integer, date) | 013_extras.sql:56 | 1 |  |
| f_card_close_le.sql | f_card_close_le(integer, date) | 013_extras.sql:43 | 1 |  |
| f_card_date.sql | f_card_date(integer, integer, integer) | 013_extras.sql:37 | 1 |  |
| f_card_due_gt.sql | f_card_due_gt(integer, date) | 013_extras.sql:66 | 1 |  |
| f_card_due_info.sql | f_card_due_info(bigint) | 013_extras.sql:192 | 1 |  |
| f_card_find.sql | f_card_find(bigint, text) | 013_extras.sql:92 | 1 |  |
| f_card_inv_avg.sql | f_card_inv_avg(bigint, date) | 026_recibo_alertas.sql:25 | 1 |  |
| f_card_invoice_alert.sql | f_card_invoice_alert(bigint) | 026_recibo_alertas.sql:46 | 1 |  |
| f_card_link.sql | f_card_link(bigint, jsonb, jsonb) | 013_extras.sql:584 | 1 |  |
| f_card_next_alert.sql | f_card_next_alert(bigint, timestamp with time zone) | 013_extras.sql:106 | 1 |  |
| f_card_status_text.sql | f_card_status_text(bigint) | 026_recibo_alertas.sql:267 | 1 | bloco DO/EXECUTE |
| f_card_status_text_pre_m2.sql | f_card_status_text_pre_m2(bigint) | 013_extras.sql:157 | 1 | renomeada de f_card_status_text (026_recibo_alertas.sql) |
| f_card_sum.sql | f_card_sum(bigint, date, date) | 013_extras.sql:79 | 1 |  |
| f_claim_due.sql | f_claim_due() | 013_extras.sql:335 | 4 |  |
| f_command_data.sql | f_command_data(bigint) | 028_custo_ia_anuais.sql:140 | 1 | bloco DO/EXECUTE |
| f_command_data_base.sql | f_command_data_base(bigint) | 021_locais_comandos.sql:95 | 1 | renomeada de f_command_data (023_locais_pergunta.sql) |
| f_command_data_pre_m4.sql | f_command_data_pre_m4(bigint) | 023_locais_pergunta.sql:227 | 1 | renomeada de f_command_data (028_custo_ia_anuais.sql) |
| f_contact_save.sql | f_contact_save(bigint, text, text, boolean) | 007_contatos.sql:28 | 1 |  |
| f_contacts.sql | f_contacts(bigint, jsonb) | 021_locais_comandos.sql:73 | 1 |  |
| f_contacts_base.sql | f_contacts_base(bigint, jsonb) | 014_contatos_convites.sql:109 | 1 | renomeada de f_contacts (021_locais_comandos.sql) |
| f_contacts_cb.sql | f_contacts_cb(bigint, text) | 014_contatos_convites.sql:262 | 1 |  |
| f_contacts_list.sql | f_contacts_list(bigint) | 007_contatos.sql:77 | 1 |  |
| f_create_reminder.sql | f_create_reminder(bigint, text, timestamp with time zone, boolean, integer, text, text, text) | 003_functions.sql:7 | 1 |  |
| f_create_supply.sql | f_create_supply(bigint, text, integer, numeric, date, integer, text, time without time zone, integer) | 024_ciclo_correcoes.sql:85 | 1 |  |
| f_create_supply_base.sql | f_create_supply_base(bigint, text, integer, numeric, date, integer, text, time, integer) | 006_cadastro_simples.sql:48 | 1 | renomeada de f_create_supply (024_ciclo_correcoes.sql) |
| f_ct_de.sql | f_ct_de(text) | 014_contatos_convites.sql:45 | 1 |  |
| f_ct_disp.sql | f_ct_disp(text) | 014_contatos_convites.sql:38 | 1 |  |
| f_ct_find.sql | f_ct_find(bigint, text) | 014_contatos_convites.sql:20 | 1 |  |
| f_ct_group_find.sql | f_ct_group_find(bigint, text) | 014_contatos_convites.sql:32 | 1 |  |
| f_ct_iso.sql | f_ct_iso(timestamp with time zone, text) | 014_contatos_convites.sql:51 | 1 |  |
| f_days_text.sql | f_days_text(integer) | 013_extras.sql:85 | 1 |  |
| f_doc_caption.sql | f_doc_caption(text, text) | 015_documentos.sql:183 | 1 |  |
| f_doc_expiry_apply.sql | f_doc_expiry_apply(bigint, bigint, date, integer) | 015_documentos.sql:155 | 1 |  |
| f_doc_folder_ensure.sql | f_doc_folder_ensure(bigint, text) | 015_documentos.sql:106 | 1 |  |
| f_doc_folder_find.sql | f_doc_folder_find(bigint, text) | 015_documentos.sql:93 | 1 |  |
| f_doc_resolve.sql | f_doc_resolve(bigint, text, bigint, boolean) | 015_documentos.sql:125 | 1 |  |
| f_doc_search.sql | f_doc_search(bigint, text, bigint, integer) | 015_documentos.sql:69 | 1 |  |
| f_doc_tokens.sql | f_doc_tokens(text) | 015_documentos.sql:54 | 1 |  |
| f_doc_unremind.sql | f_doc_unremind(bigint) | 015_documentos.sql:142 | 1 |  |
| f_docs.sql | f_docs(bigint, jsonb) | 015_documentos.sql:288 | 1 |  |
| f_docs_cb.sql | f_docs_cb(bigint, text) | 015_documentos.sql:475 | 1 |  |
| f_docs_file.sql | f_docs_file(bigint, jsonb) | 015_documentos.sql:262 | 1 |  |
| f_docs_inbox_note.sql | f_docs_inbox_note(bigint, jsonb) | 015_documentos.sql:189 | 1 |  |
| f_docs_save.sql | f_docs_save(bigint, jsonb) | 020_docs_album_janela.sql:2 | 2 |  |
| f_enqueue_doses.sql | f_enqueue_doses() | 005_doses.sql:45 | 1 |  |
| f_enqueue_supply_alerts.sql | f_enqueue_supply_alerts() | 003_functions.sql:220 | 1 |  |
| f_extras_cb.sql | f_extras_cb(bigint, text) | 013_extras.sql:644 | 1 |  |
| f_fin.sql | f_fin(bigint, jsonb) | 027_relatorios.sql:122 | 1 | bloco DO/EXECUTE |
| f_fin_add.sql | f_fin_add(bigint, jsonb) | 008_financas.sql:245 | 1 |  |
| f_fin_alerts.sql | f_fin_alerts(bigint, bigint) | 026_recibo_alertas.sql:96 | 1 |  |
| f_fin_base.sql | f_fin_base(bigint, jsonb) | 013_extras.sql:616 | 3 | renomeada de f_fin (024_ciclo_correcoes.sql) |
| f_fin_budget.sql | f_fin_budget(bigint, jsonb) | 008_financas.sql:543 | 1 |  |
| f_fin_budget_note.sql | f_fin_budget_note(bigint, bigint, numeric, date) | 011_planejamento.sql:104 | 1 |  |
| f_fin_cat.sql | f_fin_cat(bigint, text, text, text, boolean) | 008_financas.sql:153 | 1 |  |
| f_fin_cat_find.sql | f_fin_cat_find(bigint, text, text, text) | 008_financas.sql:133 | 1 |  |
| f_fin_cat_note.sql | f_fin_cat_note(bigint, bigint, numeric, date) | 008_financas.sql:182 | 1 | renomeada de f_fin_budget_note (011_planejamento.sql) |
| f_fin_category.sql | f_fin_category(bigint, jsonb) | 008_financas.sql:593 | 1 |  |
| f_fin_cb.sql | f_fin_cb(bigint, text, bigint) | 011_planejamento.sql:241 | 2 |  |
| f_fin_closing.sql | f_fin_closing(bigint, jsonb) | 008_financas.sql:620 | 1 |  |
| f_fin_correct.sql | f_fin_correct(bigint, jsonb) | 026_recibo_alertas.sql:199 | 1 | bloco DO/EXECUTE |
| f_fin_correct_pre_m2.sql | f_fin_correct_pre_m2(bigint, jsonb) | 008_financas.sql:352 | 1 | renomeada de f_fin_correct (026_recibo_alertas.sql) |
| f_fin_edit_cb.sql | f_fin_edit_cb(bigint, bigint) | 026_recibo_alertas.sql:148 | 1 |  |
| f_fin_expired.sql | f_fin_expired(bigint) | 026_recibo_alertas.sql:15 | 1 |  |
| f_fin_gen.sql | f_fin_gen(bigint) | 008_financas.sql:221 | 1 |  |
| f_fin_goal_find.sql | f_fin_goal_find(bigint, text) | 011_planejamento.sql:52 | 1 |  |
| f_fin_goal_line.sql | f_fin_goal_line(bigint) | 011_planejamento.sql:65 | 1 |  |
| f_fin_goal_saved.sql | f_fin_goal_saved(bigint) | 011_planejamento.sql:36 | 1 |  |
| f_fin_limit_note.sql | f_fin_limit_note(bigint, numeric, date) | 011_planejamento.sql:84 | 1 |  |
| f_fin_limit_text.sql | f_fin_limit_text(bigint) | 011_planejamento.sql:109 | 1 |  |
| f_fin_materialize.sql | f_fin_materialize() | 008_financas.sql:236 | 1 |  |
| f_fin_month.sql | f_fin_month(bigint, text, text) | 013_extras.sql:384 | 1 |  |
| f_fin_next_due.sql | f_fin_next_due(integer, date) | 008_financas.sql:102 | 1 |  |
| f_fin_owed.sql | f_fin_owed(bigint, jsonb) | 008_financas.sql:532 | 1 |  |
| f_fin_pay.sql | f_fin_pay(bigint, jsonb) | 008_financas.sql:332 | 1 |  |
| f_fin_pending_text.sql | f_fin_pending_text(bigint) | 008_financas.sql:444 | 1 |  |
| f_fin_period.sql | f_fin_period(bigint, integer) | 008_financas.sql:89 | 1 |  |
| f_fin_plan.sql | f_fin_plan(bigint, jsonb) | 011_planejamento.sql:150 | 1 |  |
| f_fin_plan_text.sql | f_fin_plan_text(bigint) | 011_planejamento.sql:123 | 1 |  |
| f_fin_pre_m2.sql | f_fin_pre_m2(bigint, jsonb) | 024_ciclo_correcoes.sql:33 | 1 | renomeada de f_fin (026_recibo_alertas.sql) |
| f_fin_pre_report.sql | f_fin_pre_report(bigint, jsonb) | 026_recibo_alertas.sql:175 | 1 | renomeada de f_fin (027_relatorios.sql); bloco DO/EXECUTE |
| f_fin_query.sql | f_fin_query(bigint, jsonb) | 013_extras.sql:402 | 1 |  |
| f_fin_range.sql | f_fin_range(bigint, text) | 008_financas.sql:432 | 1 |  |
| f_fin_remind.sql | f_fin_remind(bigint) | 008_financas.sql:202 | 1 |  |
| f_fin_remove.sql | f_fin_remove(bigint, jsonb) | 008_financas.sql:388 | 1 |  |
| f_fin_report.sql | f_fin_report(bigint, jsonb) | 008_financas.sql:456 | 1 |  |
| f_fin_seed.sql | f_fin_seed(bigint) | 008_financas.sql:113 | 1 |  |
| f_fin_spent.sql | f_fin_spent(bigint, bigint, date, date) | 008_financas.sql:175 | 1 |  |
| f_fin_today.sql | f_fin_today(bigint) | 008_financas.sql:84 | 1 |  |
| f_fin_total_spent.sql | f_fin_total_spent(bigint, date, date) | 011_planejamento.sql:29 | 1 |  |
| f_find_lugar.sql | f_find_lugar(bigint, text) | 035_memoria_unificada.sql:389 | 1 |  |
| f_find_pessoa.sql | f_find_pessoa(bigint, text) | 035_memoria_unificada.sql:374 | 1 |  |
| f_find_supply.sql | f_find_supply(bigint, text) | 006_cadastro_simples.sql:29 | 1 |  |
| f_group_save.sql | f_group_save(bigint, text, text[]) | 014_contatos_convites.sql:60 | 2 |  |
| f_invite_prepare.sql | f_invite_prepare(bigint, jsonb) | 023_locais_pergunta.sql:29 | 3 |  |
| f_list_lugares.sql | f_list_lugares(bigint) | 035_memoria_unificada.sql:260 | 1 |  |
| f_list_pessoas.sql | f_list_pessoas(bigint) | 035_memoria_unificada.sql:233 | 1 |  |
| f_lists.sql | f_lists(bigint, jsonb) | 025_listas_compras.sql:28 | 1 | bloco DO/EXECUTE |
| f_lists_base.sql | f_lists_base(bigint, jsonb) | 016_listas_notas.sql:124 | 1 | renomeada de f_lists (025_listas_compras.sql) |
| f_lists_cb.sql | f_lists_cb(bigint, text) | 016_listas_notas.sql:390 | 1 |  |
| f_ls_clean.sql | f_ls_clean(text) | 016_listas_notas.sql:53 | 1 |  |
| f_ls_disp.sql | f_ls_disp(text) | 016_listas_notas.sql:59 | 1 |  |
| f_ls_find.sql | f_ls_find(bigint, text) | 016_listas_notas.sql:65 | 1 |  |
| f_ls_is_default.sql | f_ls_is_default(text) | 025_listas_compras.sql:10 | 1 |  |
| f_ls_item_find.sql | f_ls_item_find(bigint, text, boolean) | 016_listas_notas.sql:84 | 1 |  |
| f_ls_menu_ins.sql | f_ls_menu_ins(text, text) | 025_listas_compras.sql:16 | 1 |  |
| f_ls_msg.sql | f_ls_msg(text) | 016_listas_notas.sql:118 | 1 |  |
| f_ls_render.sql | f_ls_render(bigint) | 016_listas_notas.sql:103 | 1 |  |
| f_mem_add.sql | f_mem_add(bigint, text, text, text) | 035_memoria_unificada.sql:149 | 1 |  |
| f_mem_forget.sql | f_mem_forget(bigint, text) | 035_memoria_unificada.sql:334 | 1 |  |
| f_mem_list.sql | f_mem_list(bigint, text) | 035_memoria_unificada.sql:277 | 1 |  |
| f_mem_prompt_txt.sql | f_mem_prompt_txt(bigint, text) | 035_memoria_unificada.sql:220 | 1 |  |
| f_mem_relevant_txt.sql | f_mem_relevant_txt(bigint, text, integer) | 035_memoria_unificada.sql:197 | 1 |  |
| f_mem_set_switch.sql | f_mem_set_switch(bigint, text, boolean) | 035_memoria_unificada.sql:112 | 1 |  |
| f_mem_sw.sql | f_mem_sw(bigint, text) | 035_memoria_unificada.sql:88 | 1 |  |
| f_mem_switch_name.sql | f_mem_switch_name(text) | 035_memoria_unificada.sql:96 | 1 |  |
| f_mem_switches.sql | f_mem_switches(bigint) | 035_memoria_unificada.sql:105 | 1 |  |
| f_mem_tipo.sql | f_mem_tipo(text) | 035_memoria_unificada.sql:138 | 1 |  |
| f_mem_tokens.sql | f_mem_tokens(text) | 035_memoria_unificada.sql:127 | 1 |  |
| f_menu.sql | f_menu(bigint, text) | 036_menu_secretaria.sql:17 | 1 |  |
| f_menu_base.sql | f_menu_base(bigint, text) | 023_locais_pergunta.sql:246 | 2 | renomeada de f_menu (024_ciclo_correcoes.sql) |
| f_menu_pre_f13.sql | f_menu_pre_f13(bigint, text) | 029_pesquisa.sql:113 | 1 | renomeada de f_menu (036_menu_secretaria.sql) |
| f_menu_pre_m1.sql | f_menu_pre_m1(bigint, text) | 024_ciclo_correcoes.sql:179 | 1 | renomeada de f_menu (025_listas_compras.sql) |
| f_menu_pre_m2.sql | f_menu_pre_m2(bigint, text) | 025_listas_compras.sql:77 | 1 | renomeada de f_menu (026_recibo_alertas.sql); bloco DO/EXECUTE |
| f_menu_pre_m4.sql | f_menu_pre_m4(bigint, text) | 027_relatorios.sql:139 | 1 | renomeada de f_menu (028_custo_ia_anuais.sql); bloco DO/EXECUTE |
| f_menu_pre_m5.sql | f_menu_pre_m5(bigint, text) | 028_custo_ia_anuais.sql:253 | 1 | renomeada de f_menu (029_pesquisa.sql); bloco DO/EXECUTE |
| f_menu_pre_report.sql | f_menu_pre_report(bigint, text) | 026_recibo_alertas.sql:308 | 1 | renomeada de f_menu (027_relatorios.sql); bloco DO/EXECUTE |
| f_misc.sql | f_misc(bigint, jsonb) | 013_extras.sql:665 | 1 |  |
| f_multi_db.sql | f_multi_db(bigint, jsonb) | 033_acoes_recentes.sql:131 | 1 |  |
| f_multi_events.sql | f_multi_events(bigint, jsonb) | 033_acoes_recentes.sql:186 | 1 |  |
| f_multi_tasks.sql | f_multi_tasks(bigint, jsonb) | 033_acoes_recentes.sql:218 | 1 |  |
| f_norm.sql | f_norm(text) | 008_financas.sql:67 | 1 |  |
| f_notes.sql | f_notes(bigint, jsonb) | 016_listas_notas.sql:335 | 1 |  |
| f_nt_search.sql | f_nt_search(bigint, text, integer) | 016_listas_notas.sql:297 | 1 |  |
| f_nt_snip.sql | f_nt_snip(text, integer) | 016_listas_notas.sql:327 | 1 |  |
| f_offer_accept.sql | f_offer_accept(bigint, text, text, text, text, text) | 035_memoria_unificada.sql:459 | 1 |  |
| f_offer_candidates.sql | f_offer_candidates(bigint, text, text) | 035_memoria_unificada.sql:407 | 1 |  |
| f_offer_decline.sql | f_offer_decline(bigint, text, text) | 035_memoria_unificada.sql:513 | 1 |  |
| f_place_cb.sql | f_place_cb(bigint, text) | 023_locais_pergunta.sql:175 | 1 |  |
| f_place_find.sql | f_place_find(bigint, text) | 021_locais_comandos.sql:17 | 1 |  |
| f_place_is_name.sql | f_place_is_name(text) | 023_locais_pergunta.sql:20 | 1 |  |
| f_places.sql | f_places(bigint, jsonb) | 023_locais_pergunta.sql:124 | 2 |  |
| f_proj_deadline_lines.sql | f_proj_deadline_lines(bigint) | 032_resumo_enxuto.sql:247 | 1 |  |
| f_proj_fmt.sql | f_proj_fmt(date, date) | 017_projetos.sql:44 | 1 |  |
| f_proj_google_apply.sql | f_proj_google_apply(bigint, jsonb) | 030_projetos_google.sql:242 | 1 |  |
| f_proj_gt_backfill_count.sql | f_proj_gt_backfill_count(bigint) | 030_projetos_google.sql:319 | 1 |  |
| f_proj_gt_owner.sql | f_proj_gt_owner(bigint) | 030_projetos_google.sql:46 | 1 |  |
| f_proj_gt_plan.sql | f_proj_gt_plan(bigint, jsonb) | 030_projetos_google.sql:123 | 1 |  |
| f_proj_gt_reconcile.sql | f_proj_gt_reconcile(bigint, jsonb) | 030_projetos_google.sql:222 | 1 |  |
| f_proj_gt_trg_del.sql | f_proj_gt_trg_del() | 030_projetos_google.sql:96 | 1 |  |
| f_proj_gt_trg_p.sql | f_proj_gt_trg_p() | 030_projetos_google.sql:58 | 1 |  |
| f_proj_gt_trg_t.sql | f_proj_gt_trg_t() | 030_projetos_google.sql:71 | 1 |  |
| f_proj_gt_trg_t_parent.sql | f_proj_gt_trg_t_parent() | 030_projetos_google.sql:86 | 1 |  |
| f_proj_gt_users.sql | f_proj_gt_users() | 030_projetos_google.sql:312 | 1 |  |
| f_proj_gtitle.sql | f_proj_gtitle(boolean, text) | 030_projetos_google.sql:52 | 1 |  |
| f_proj_insert_tasks.sql | f_proj_insert_tasks(bigint, bigint, jsonb) | 017_projetos.sql:119 | 1 |  |
| f_proj_overdue_text.sql | f_proj_overdue_text(bigint, bigint, date, integer) | 017_projetos.sql:135 | 1 |  |
| f_proj_progress.sql | f_proj_progress(bigint, bigint) | 017_projetos.sql:50 | 1 |  |
| f_proj_resolve.sql | f_proj_resolve(bigint, text) | 017_projetos.sql:60 | 1 |  |
| f_proj_task_resolve.sql | f_proj_task_resolve(bigint, bigint, text, boolean) | 017_projetos.sql:90 | 1 |  |
| f_projects.sql | f_projects(bigint, jsonb) | 025_listas_compras.sql:55 | 1 | bloco DO/EXECUTE |
| f_projects_base.sql | f_projects_base(bigint, jsonb) | 019_projetos_direto.sql:3 | 2 | renomeada de f_projects (025_listas_compras.sql) |
| f_projects_cb.sql | f_projects_cb(bigint, text) | 017_projetos.sql:380 | 1 |  |
| f_projects_summary.sql | f_projects_summary(bigint) | 017_projetos.sql:420 | 1 |  |
| f_provide_time.sql | f_provide_time(bigint, bigint, timestamp with time zone) | 003_functions.sql:54 | 1 |  |
| f_ra_log.sql | f_ra_log(bigint, text, bigint, text, text, text) | 033_acoes_recentes.sql:47 | 1 |  |
| f_ra_trg_fin.sql | f_ra_trg_fin() | 033_acoes_recentes.sql:76 | 1 |  |
| f_ra_trg_list_items.sql | f_ra_trg_list_items() | 033_acoes_recentes.sql:100 | 1 |  |
| f_ra_trg_notes.sql | f_ra_trg_notes() | 033_acoes_recentes.sql:89 | 1 |  |
| f_ra_trg_reminders.sql | f_ra_trg_reminders() | 033_acoes_recentes.sql:60 | 1 |  |
| f_recent_actions_txt.sql | f_recent_actions_txt(bigint) | 033_acoes_recentes.sql:113 | 1 |  |
| f_recent_correct.sql | f_recent_correct(bigint, jsonb) | 033_acoes_recentes.sql:286 | 1 |  |
| f_reminder_advance.sql | f_reminder_advance(bigint) | 028_custo_ia_anuais.sql:236 | 1 | bloco DO/EXECUTE |
| f_reminder_advance_base.sql | f_reminder_advance_base(bigint) | 013_extras.sql:238 | 1 | renomeada de f_reminder_advance (028_custo_ia_anuais.sql) |
| f_reminder_advance_yearly.sql | f_reminder_advance_yearly(bigint) | 028_custo_ia_anuais.sql:188 | 1 |  |
| f_reminder_cancel.sql | f_reminder_cancel(bigint, text) | 013_extras.sql:294 | 1 |  |
| f_reminder_create_ex.sql | f_reminder_create_ex(bigint, text, timestamp with time zone, boolean, integer, text, jsonb) | 024_ciclo_correcoes.sql:161 | 1 |  |
| f_reminder_create_ex_base.sql | f_reminder_create_ex_base(bigint, text, timestamp with time zone, boolean, integer, text, jsonb) | 028_custo_ia_anuais.sql:159 | 1 | bloco DO/EXECUTE |
| f_reminder_create_ex_base_pre_m4.sql | f_reminder_create_ex_base_pre_m4(bigint, text, timestamp with time zone, boolean, integer, text, jsonb) | 013_extras.sql:211 | 1 | renomeada de f_reminder_create_ex_base (028_custo_ia_anuais.sql) |
| f_reminder_link.sql | f_reminder_link(bigint, jsonb) | 012_agenda.sql:597 | 1 |  |
| f_report_action.sql | f_report_action(bigint, jsonb) | 027_relatorios.sql:99 | 1 |  |
| f_report_data.sql | f_report_data(bigint, jsonb) | 027_relatorios.sql:5 | 1 |  |
| f_research_gate.sql | f_research_gate(bigint) | 029_pesquisa.sql:53 | 1 |  |
| f_research_log.sql | f_research_log(bigint, bigint, text, integer, integer, integer, boolean) | 029_pesquisa.sql:71 | 1 |  |
| f_resolve_invitees.sql | f_resolve_invitees(bigint, text[]) | 035_memoria_unificada.sql:532 | 3 |  |
| f_safe_date.sql | f_safe_date(text) | 008_financas.sql:77 | 1 |  |
| f_series_next.sql | f_series_next(bigint) | 012_agenda.sql:99 | 1 |  |
| f_set_lead.sql | f_set_lead(bigint, bigint, integer) | 003_functions.sql:34 | 1 |  |
| f_set_pref.sql | f_set_pref(bigint, integer, time, integer) | 003_functions.sql:167 | 1 |  |
| f_set_prefs.sql | f_set_prefs(bigint, jsonb) | 034_tom_preferencias.sql:2 | 3 |  |
| f_suggest_pick.sql | f_suggest_pick(bigint, boolean) | 035_memoria_unificada.sql:561 | 1 |  |
| f_summary_candidates.sql | f_summary_candidates() | 011_planejamento.sql:332 | 3 |  |
| f_summary_data.sql | f_summary_data(bigint) | 026_recibo_alertas.sql:286 | 1 | bloco DO/EXECUTE |
| f_summary_data_base.sql | f_summary_data_base(bigint) | 013_extras.sql:706 | 2 | renomeada de f_summary_data (018_resumo_fase4.sql) |
| f_summary_data_pre_m2.sql | f_summary_data_pre_m2(bigint) | 032_resumo_enxuto.sql:260 | 3 |  |
| f_supply_adjust.sql | f_supply_adjust(bigint, text, integer, integer) | 010_estoque_fix.sql:6 | 3 |  |
| f_supply_bought.sql | f_supply_bought(bigint, text) | 006_cadastro_simples.sql:123 | 3 |  |
| f_supply_cb.sql | f_supply_cb(bigint, text) | 024_ciclo_correcoes.sql:132 | 1 |  |
| f_supply_manage.sql | f_supply_manage(bigint, text, integer, integer, text, text) | 024_ciclo_correcoes.sql:100 | 1 |  |
| f_supply_schedule.sql | f_supply_schedule(bigint, text, text, boolean, text) | 006_cadastro_simples.sql:88 | 1 |  |
| f_supply_taken.sql | f_supply_taken(bigint, text) | 006_cadastro_simples.sql:106 | 2 |  |
| f_tip.sql | f_tip(bigint) | 022_menu.sql:61 | 1 |  |
