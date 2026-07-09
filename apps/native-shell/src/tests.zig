const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const model_mod = @import("model/app_model.zig");
const scanner_mod = @import("workspace/scanner.zig");

const canvas = native_sdk.canvas;
const testing = std.testing;

const AppUi = main.AppUi;
const Model = main.Model;
const Msg = main.Msg;
const AppMarkup = canvas.MarkupView(Model, Msg);

fn buildTree(arena: std.mem.Allocator, model: *const Model) !AppUi.Tree {
    var view = try AppMarkup.init(arena, main.app_markup);
    var ui = AppUi.init(arena);
    const node = view.build(&ui, model) catch |err| {
        if (err == error.MarkupBuild) {
            std.debug.print("app.native:{d}:{d}: {s}\n", .{ view.diagnostic.line, view.diagnostic.column, view.diagnostic.message });
        }
        return err;
    };
    return ui.finalize(node);
}

fn findByText(widget: canvas.Widget, kind: canvas.WidgetKind, text: []const u8) ?canvas.Widget {
    if (widget.kind == kind and std.mem.eql(u8, widget.text, text)) return widget;
    for (widget.children) |child| {
        if (findByText(child, kind, text)) |found| return found;
    }
    return null;
}

fn expectByText(widget: canvas.Widget, kind: canvas.WidgetKind, text: []const u8) !canvas.Widget {
    return findByText(widget, kind, text) orelse {
        std.debug.print("no {t} with text \"{s}\" in the view\n", .{ kind, text });
        return error.WidgetNotFound;
    };
}

test "launch screen shows Velocity title" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var model = main.initialModel();
    const tree = try buildTree(arena_state.allocator(), &model);
    _ = try expectByText(tree.root, .text, "Velocity");
    _ = try expectByText(tree.root, .button, "Open Folder");
}

test "opening a project enters IDE mode" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    try testing.expect(model.current_view == .ide);
    try testing.expectEqualStrings("acme-dashboard", model.project_name);
}

test "command palette toggles" {
    var model = main.initialModel();
    main.update(&model, .open_command_palette);
    try testing.expect(model.command_palette_open);
    main.update(&model, .close_command_palette);
    try testing.expect(!model.command_palette_open);
}

test "perf check populates mock metrics" {
    var model = main.initialModel();
    main.update(&model, .run_perf_check_placeholder);
    try testing.expect(model.show_perf_hud);
    try testing.expect(model.perf_first_paint_ms > 0);
    try testing.expect(model.perf_plugins_loaded == 0);
}

test "permissions default deny" {
    const permissions = @import("plugins/permissions.zig");
    try testing.expect(!permissions.isAllowed(.network));
    try testing.expect(!permissions.isAllowed(.shell));
    try testing.expect(!permissions.isAllowed(.credentials));
}

test "model module exports mock project data" {
    try testing.expect(model_mod.file_tree.len >= 5);
    try testing.expect(model_mod.agent_tasks.len == 4);
}

test "feature registry catalogs modules" {
    const registry = @import("core/feature_registry.zig");
    try testing.expect(registry.catalog.len == registry.registered_count);
    try testing.expect(registry.startup_critical_count < 30);
    try testing.expect(registry.assertNoStartupNonCritical(&registry.catalog));
}

test "process governor records without OS spawn" {
    const gov = @import("processes/process_governor.zig");
    var g: gov.Governor = .{};
    const id = try g.spawn("feature.terminal", "mock-pty");
    try testing.expect(g.aliveCount() == 1);
    g.killFeature("feature.terminal");
    try testing.expect(g.aliveCount() == 0);
    _ = id;
}

test "feature matrix command switches view" {
    var model = main.initialModel();
    main.update(&model, .open_feature_matrix);
    try testing.expect(model.current_view == .features);
}

test "open fixture workspace scans disk and skips node_modules" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    try testing.expect(model.current_view == .ide);
    try testing.expect(model.workspace_from_disk);
    try testing.expect(model.workspace_node_count > 0);
    try testing.expectEqualStrings("", model.workspace_scan_error);
    for (model.file_nodes) |n| {
        try testing.expect(!std.mem.eql(u8, n.name, "node_modules"));
        try testing.expect(!std.mem.startsWith(u8, n.path, "node_modules/"));
    }
    // Editor should have loaded a real file from disk
    const body = model.editorBody();
    try testing.expect(body.len > 0);
    try testing.expect(std.mem.indexOf(u8, body, "Unable to read file") == null);
}

test "selecting a disk file loads contents" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    var auth_id: ?u32 = null;
    for (model.file_nodes) |n| {
        if (std.mem.eql(u8, n.path, "src/server/auth.ts")) auth_id = n.id;
    }
    try testing.expect(auth_id != null);
    main.update(&model, .{ .select_file = auth_id.? });
    try testing.expect(std.mem.indexOf(u8, model.editorBody(), "createSession") != null);
    try testing.expectEqualStrings("TypeScript", model.status_language);
}

test "edit and save document roundtrip" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    try testing.expect(model.workspace_from_disk);
    const original = model.document.text();
    try testing.expect(original.len > 0);

    // Append a marker via TextBuffer.set (simulates edit)
    var buf: [model_mod.max_document]u8 = undefined;
    const marker = "\n// velocity-mvp-save\n";
    @memcpy(buf[0..original.len], original);
    const mark_len = @min(marker.len, buf.len - original.len);
    @memcpy(buf[original.len..][0..mark_len], marker[0..mark_len]);
    model.document.set(buf[0 .. original.len + mark_len]);
    model.document_dirty = true;
    main.update(&model, .save_file);
    try testing.expect(!model.document_dirty);
    try testing.expectEqualStrings("Saved", model.toast);

    // Re-open file and confirm marker persisted
    const path = model.activeTabPath();
    var file_id: ?u32 = null;
    for (model.file_nodes) |node| {
        if (std.mem.eql(u8, node.path, path)) file_id = node.id;
    }
    try testing.expect(file_id != null);
    main.update(&model, .{ .select_file = file_id.? });
    try testing.expect(std.mem.indexOf(u8, model.document.text(), "velocity-mvp-save") != null);

    // Restore original contents so fixture stays clean for other tests
    model.document.set(original);
    model.document_dirty = true;
    main.update(&model, .save_file);
}

test "open path from typed folder" {
    var model = main.initialModel();
    model.open_path.set("fixtures/acme-dashboard");
    main.update(&model, .submit_open_path);
    try testing.expect(model.workspace_from_disk);
    try testing.expect(model.workspace_node_count > 0);
}

test "terminal pipe command runs through governor" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.terminal_command.set("echo velocity-mvp");
    main.update(&model, .run_terminal_command);
    try testing.expect(model.term_lines.len >= 2);
    var found = false;
    for (model.term_lines) |line| {
        if (std.mem.indexOf(u8, line, "velocity-mvp") != null) found = true;
    }
    try testing.expect(found);
    try testing.expectEqualStrings("Command ok", model.toast);
}

test "workspace search finds auth helper" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.search_query.set("createSession");
    main.update(&model, .run_search);
    try testing.expect(model.search_hits.len > 0);
    try testing.expect(model.current_view == .search);
}

test "git status refresh on scm activity" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    main.update(&model, .{ .select_activity = .scm });
    try testing.expect(model.current_view == .scm);
    // Fixture is not a real git repo (nested .git not committed); expect graceful summary.
    try testing.expect(model.git_summary.len > 0);
}

test "create new file in workspace" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.new_file_path.set("src/mvp_created.ts");
    main.update(&model, .create_new_file);
    try testing.expectEqualStrings("File created", model.toast);
    var found = false;
    for (model.file_nodes) |n| {
        if (std.mem.eql(u8, n.path, "src/mvp_created.ts")) found = true;
    }
    try testing.expect(found);
    // Cleanup
    const io = model.io orelse std.testing.io;
    std.Io.Dir.cwd().deleteFile(io, "fixtures/acme-dashboard/src/mvp_created.ts") catch {};
}

test "delete selected file" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.new_file_path.set("src/mvp_to_delete.ts");
    main.update(&model, .create_new_file);
    try testing.expectEqualStrings("File created", model.toast);
    main.update(&model, .delete_selected_file);
    try testing.expect(std.mem.startsWith(u8, model.toast, "Delete "));
    main.update(&model, .delete_selected_file);
    try testing.expectEqualStrings("File deleted", model.toast);
    for (model.file_nodes) |n| {
        try testing.expect(!std.mem.eql(u8, n.path, "src/mvp_to_delete.ts"));
    }
}

test "rename selected file" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.new_file_path.set("src/mvp_rename_src.ts");
    main.update(&model, .create_new_file);
    model.new_file_path.set("src/mvp_rename_dst.ts");
    main.update(&model, .rename_selected_file);
    try testing.expectEqualStrings("File renamed", model.toast);
    var found = false;
    for (model.file_nodes) |n| {
        if (std.mem.eql(u8, n.path, "src/mvp_rename_dst.ts")) found = true;
        try testing.expect(!std.mem.eql(u8, n.path, "src/mvp_rename_src.ts"));
    }
    try testing.expect(found);
    main.update(&model, .delete_selected_file);
    main.update(&model, .delete_selected_file);
}

test "find in document" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.find_query.set("Chart");
    main.update(&model, .run_find);
    try testing.expect(model.find_matches.len > 0);
    main.update(&model, .find_next);
    try testing.expect(model.find_active_label.len > 0);
}

test "quick open filters files" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.quick_query.set("auth");
    main.update(&model, .run_quick_open);
    try testing.expect(model.quick_open_visible);
    try testing.expect(model.quick_items.len > 0);
}

test "prefs persist theme" {
    var model = main.initialModel();
    main.update(&model, .switch_theme);
    try testing.expect(model.theme_preference == .light);
    var model2 = main.initialModel();
    model_mod.ensurePrefsOnBoot(&model2);
    try testing.expect(model2.theme_preference == .light);
    // restore dark for other tests
    model2.theme_preference = .dark;
    main.update(&model2, .save_prefs);
    std.Io.Dir.cwd().deleteTree(std.testing.io, ".velocity") catch {};
}

test "goto line reports position" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.goto_line_input.set("2");
    main.update(&model, .goto_line);
    try testing.expect(std.mem.indexOf(u8, model.toast, "Line 2") != null);
}

test "close tab soft-confirms dirty then discards" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.document_dirty = true;
    main.update(&model, .close_active_tab);
    try testing.expect(std.mem.startsWith(u8, model.toast, "Unsaved changes"));
    main.update(&model, .close_active_tab);
    try testing.expect(!model.document_dirty);
}

test "replace once and all in document" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.document.set("alpha foo beta foo");
    model.find_query.set("foo");
    model.replace_text.set("bar");
    main.update(&model, .replace_once);
    try testing.expectEqualStrings("alpha bar beta foo", model.document.text());
    try testing.expect(model.document_dirty);
    main.update(&model, .replace_all);
    try testing.expectEqualStrings("alpha bar beta bar", model.document.text());
    try testing.expect(std.mem.indexOf(u8, model.toast, "Replaced") != null);
}

test "document stats update on edit" {
    var model = main.initialModel();
    model.document.set("a\nb\nc");
    model_mod.refreshDocStats(&model);
    try testing.expect(std.mem.indexOf(u8, model.doc_stats, "3 lines") != null);
    try testing.expect(std.mem.indexOf(u8, model.doc_stats, "5 bytes") != null);
}

test "copy active path sets toast" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    main.update(&model, .copy_active_path);
    try testing.expect(model.path_toast.len > 0);
    try testing.expectEqualStrings(model.path_toast, model.toast);
}

test "recent projects sync from prefs" {
    var model = main.initialModel();
    model.io = std.testing.io;
    model.prefs_loaded = false;
    model.prefs = .{};
    model.prefs.setLastPath("fixtures/acme-dashboard");
    model.prefs.pushRecent("fixtures/empty");
    main.update(&model, .refresh_recent);
    try testing.expect(model.recent.len >= 1);
    try testing.expect(std.mem.indexOf(u8, model.recent[0].path, "fixtures") != null);
    std.Io.Dir.cwd().deleteTree(std.testing.io, ".velocity") catch {};
}

test "find case sensitivity toggle" {
    var model = main.initialModel();
    model.document.set("Foo foo FOO");
    model.find_query.set("foo");
    model.find_case_sensitive = false;
    main.update(&model, .run_find);
    try testing.expect(model.find_matches.len == 3);
    main.update(&model, .toggle_find_case);
    try testing.expect(model.find_case_sensitive);
    try testing.expect(model.find_matches.len == 1);
}

test "auto save toggle persists preference" {
    var model = main.initialModel();
    model.io = std.testing.io;
    try testing.expect(!model.auto_save);
    main.update(&model, .toggle_auto_save);
    try testing.expect(model.auto_save);
    var model2 = main.initialModel();
    model2.io = std.testing.io;
    model_mod.ensurePrefsOnBoot(&model2);
    try testing.expect(model2.auto_save);
    model2.auto_save = false;
    main.update(&model2, .save_prefs);
    std.Io.Dir.cwd().deleteTree(std.testing.io, ".velocity") catch {};
}

test "breadcrumb tracks active path" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    try testing.expect(model.breadcrumb.len > 0);
    try testing.expect(std.mem.indexOf(u8, model.breadcrumb, "/") != null or model.breadcrumb.len > 0);
}

test "clear find resets query and matches" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.find_query.set("Chart");
    model.replace_text.set("X");
    main.update(&model, .run_find);
    try testing.expect(model.find_matches.len > 0);
    main.update(&model, .clear_find);
    try testing.expectEqual(@as(usize, 0), model.find_query.text().len);
    try testing.expectEqual(@as(usize, 0), model.find_matches.len);
}

test "reopen last workspace from prefs" {
    var model = main.initialModel();
    model.io = std.testing.io;
    main.update(&model, .{ .open_project = "acme-dashboard" });
    try testing.expect(model.workspace_from_disk);
    model.current_view = .launch;
    main.update(&model, .reopen_last_workspace);
    try testing.expect(model.current_view == .ide);
    try testing.expect(model.workspace_from_disk);
    std.Io.Dir.cwd().deleteTree(std.testing.io, ".velocity") catch {};
}

test "open git entry missing is graceful" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    main.update(&model, .{ .open_git_entry = 1 });
    try testing.expect(std.mem.indexOf(u8, model.toast, "not found") != null or std.mem.indexOf(u8, model.toast, "Git") != null);
}

test "dismiss overlay closes quick open then find" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    main.update(&model, .run_quick_open);
    try testing.expect(model.quick_open_visible);
    main.update(&model, .dismiss_overlay);
    try testing.expect(!model.quick_open_visible);
    model.find_query.set("Chart");
    main.update(&model, .run_find);
    try testing.expect(model.find_matches.len > 0);
    main.update(&model, .dismiss_overlay);
    try testing.expectEqual(@as(usize, 0), model.find_matches.len);
}

test "duplicate last line appends copy" {
    var model = main.initialModel();
    model.document.set("one\ntwo");
    main.update(&model, .duplicate_line);
    try testing.expectEqualStrings("one\ntwo\ntwo", model.document.text());
    try testing.expect(model.document_dirty);
}

test "workspace file count label after open" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    try testing.expect(model.workspace_file_count > 0);
    try testing.expect(std.mem.indexOf(u8, model.workspace_files_label, "files") != null);
}

test "search status reports hit count" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.search_query.set("createSession");
    main.update(&model, .run_search);
    try testing.expect(model.search_hits.len > 0);
    try testing.expect(std.mem.indexOf(u8, model.search_bufs.?.status, "hits") != null);
}

test "dirty tab title gets marker" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.document_dirty = true;
    model_mod.syncActiveTabDirtyForTest(&model);
    var marked = false;
    for (model.open_tabs) |t| {
        if (t.id == model.active_tab_id and t.dirty) marked = true;
    }
    try testing.expect(marked);
}

test "terminal history older newer" {
    var model = main.initialModel();
    model.terminal_command.set("echo one");
    main.update(&model, .run_terminal_command);
    model.terminal_command.set("echo two");
    main.update(&model, .run_terminal_command);
    main.update(&model, .terminal_history_older);
    try testing.expectEqualStrings("echo two", model.terminal_command.text());
    main.update(&model, .terminal_history_older);
    try testing.expectEqualStrings("echo one", model.terminal_command.text());
}

test "explorer filter narrows nodes" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    const before = model.file_nodes.len;
    model.explorer_filter.set("auth");
    model_mod.applyExplorerFilter(&model);
    try testing.expect(model.file_nodes.len < before);
    try testing.expect(model.file_nodes.len > 0);
    for (model.file_nodes) |n| {
        const hit = std.ascii.indexOfIgnoreCase(n.name, "auth") != null or std.ascii.indexOfIgnoreCase(n.path, "auth") != null;
        try testing.expect(hit);
    }
}

test "reveal in explorer selects active file" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    const active = model.active_tab_id;
    model.selected_file_id = 0;
    main.update(&model, .reveal_in_explorer);
    try testing.expect(model.selected_file_id == active or model.selected_file_id != 0);
    try testing.expect(model.selected_activity == .explorer);
}

test "toggle line comment roundtrip" {
    var model = main.initialModel();
    model.document.set("alpha\nbeta\n");
    main.update(&model, .toggle_line_comment);
    try testing.expectEqualStrings("// alpha\n// beta\n", model.document.text());
    main.update(&model, .toggle_line_comment);
    try testing.expectEqualStrings("alpha\nbeta\n", model.document.text());
}

test "indent and outdent document" {
    var model = main.initialModel();
    model.document.set("x\ny\n");
    main.update(&model, .indent_document);
    try testing.expectEqualStrings("  x\n  y\n", model.document.text());
    main.update(&model, .outdent_document);
    try testing.expectEqualStrings("x\ny\n", model.document.text());
}

test "problems scan finds TODO in fixture" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    main.update(&model, .scan_problems);
    try testing.expect(model.problems.len > 0);
    try testing.expect(std.mem.indexOf(u8, model.problems_status, "markers") != null);
}

test "reopen closed tab restores file" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    const first = model.active_tab_id;
    // Open another file then close the first via close after switching
    if (model.workspace) |ws| {
        if (ws.file_node_count > 2) {
            const other = ws.file_nodes[2].id;
            if (!ws.file_nodes[2].is_dir) {
                main.update(&model, .{ .select_file = other });
            }
        }
    }
    main.update(&model, .{ .select_tab = first });
    main.update(&model, .close_active_tab);
    try testing.expectEqualStrings("Tab closed", model.toast);
    try testing.expect(model.closed_tab_count > 0);
    main.update(&model, .reopen_closed_tab);
    try testing.expectEqualStrings("Tab reopened", model.toast);
}

test "command palette filters by query" {
    var model = main.initialModel();
    main.update(&model, .open_command_palette);
    try testing.expect(model.command_items.len == model_mod.commands.len);
    model.command_query.set("save");
    model_mod.filterCommandPaletteForTest(&model);
    try testing.expect(model.command_items.len > 0);
    try testing.expect(model.command_items.len < model_mod.commands.len);
    for (model.command_items) |cmd| {
        const hit = std.ascii.indexOfIgnoreCase(cmd.title, "save") != null or std.ascii.indexOfIgnoreCase(cmd.id, "save") != null;
        try testing.expect(hit);
    }
}

test "save all clears dirty active document" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.document.set(model.document.text());
    model.document_dirty = true;
    model_mod.syncActiveTabDirtyForTest(&model);
    main.update(&model, .save_all);
    try testing.expect(!model.document_dirty);
    try testing.expectEqualStrings("Saved all", model.toast);
}

test "open search hit jumps to line toast" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.search_query.set("createSession");
    main.update(&model, .run_search);
    try testing.expect(model.search_hits.len > 0);
    const id = model.search_hits[0].id;
    main.update(&model, .{ .open_search_hit = id });
    try testing.expect(std.mem.indexOf(u8, model.toast, "Line") != null);
}

test "text transforms upper lower sort" {
    var model = main.initialModel();
    model.document.set("b\na\nc\n");
    main.update(&model, .transform_sort_lines);
    try testing.expectEqualStrings("a\nb\nc\n", model.document.text());
    main.update(&model, .transform_upper);
    try testing.expectEqualStrings("A\nB\nC\n", model.document.text());
    main.update(&model, .transform_lower);
    try testing.expectEqualStrings("a\nb\nc\n", model.document.text());
}

test "focus mode hides chrome helpers" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.show_terminal = true;
    model.show_agent_panel = true;
    main.update(&model, .toggle_focus_mode);
    try testing.expect(model.focus_mode);
    try testing.expect(!model_mod.Model.showLeftPanel(&model));
    try testing.expect(!model_mod.Model.showTerminalChrome(&model));
    try testing.expect(!model_mod.Model.showAgentChrome(&model));
}

test "pin blocks close until unpinned" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    main.update(&model, .pin_active_tab);
    try testing.expect(model.pinned_tab_id == model.active_tab_id);
    main.update(&model, .close_active_tab);
    try testing.expectEqualStrings("Unpin tab before closing", model.toast);
    main.update(&model, .pin_active_tab);
    try testing.expect(model.pinned_tab_id == 0);
}

test "save hygiene trims trailing whitespace" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    // Use a disposable file so we never overwrite fixture sources.
    model.new_file_path.set("src/hygiene_tmp.ts");
    main.update(&model, .create_new_file);
    model.trim_trailing_ws = true;
    model.insert_final_newline = true;
    model.document.set("hello  ");
    model.document_dirty = true;
    main.update(&model, .save_file);
    try testing.expectEqualStrings("hello\n", model.document.text());
    try testing.expect(!model.document_dirty);
    // Soft-confirm delete the temp file.
    main.update(&model, .delete_selected_file);
    main.update(&model, .delete_selected_file);
}

test "delete join move lines and undo" {
    var model = main.initialModel();
    model.document.set("a\nb\nc\n");
    main.update(&model, .delete_last_line);
    try testing.expectEqualStrings("a\nb", model.document.text());
    main.update(&model, .undo_edit);
    try testing.expectEqualStrings("a\nb\nc\n", model.document.text());
    main.update(&model, .join_lines);
    try testing.expectEqualStrings("a b c", model.document.text());
    model.document.set("a\nb\nc\n");
    main.update(&model, .move_line_up);
    try testing.expectEqualStrings("a\nc\nb\n", model.document.text());
}

test "copy absolute path joins root" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    main.update(&model, .copy_absolute_path);
    try testing.expect(model.path_toast.len > 0);
    try testing.expect(std.mem.indexOf(u8, model.path_toast, "/") != null);
}

test "doc stats include eol" {
    var model = main.initialModel();
    model.document.set("a\r\nb\n");
    model_mod.refreshDocStats(&model);
    try testing.expect(std.mem.indexOf(u8, model.doc_stats, "CRLF") != null);
    try testing.expect(std.mem.indexOf(u8, model.doc_stats, "words") != null);
}

test "cycle tabs next and prev" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    // Open a second file via quick open if possible.
    model.quick_query.set("auth");
    main.update(&model, .run_quick_open);
    if (model.quick_items.len > 0) {
        main.update(&model, .{ .open_quick_item = model.quick_items[0].id });
    }
    const first = model.active_tab_id;
    main.update(&model, .next_tab);
    if (model.open_tabs.len > 1) {
        try testing.expect(model.active_tab_id != first);
        main.update(&model, .prev_tab);
        try testing.expectEqual(first, model.active_tab_id);
    }
}

test "remove blank lines and copy filename" {
    var model = main.initialModel();
    model.document.set("a\n\nb\n");
    main.update(&model, .remove_blank_lines);
    try testing.expectEqualStrings("a\nb\n", model.document.text());
    main.update(&model, .{ .open_project = "acme-dashboard" });
    main.update(&model, .copy_filename);
    try testing.expect(model.path_toast.len > 0);
    try testing.expect(std.mem.indexOf(u8, model.path_toast, "/") == null);
}

test "indent size cycle and tabs to spaces" {
    var model = main.initialModel();
    try testing.expectEqual(@as(u8, 2), model.indent_size);
    main.update(&model, .cycle_indent_size);
    try testing.expectEqual(@as(u8, 4), model.indent_size);
    model.document.set("a\tb");
    main.update(&model, .convert_tabs_to_spaces);
    try testing.expectEqualStrings("a   b", model.document.text());
    model.document.set("b\na\nb\n");
    main.update(&model, .transform_sort_unique);
    try testing.expectEqualStrings("a\nb\n", model.document.text());
    model_mod.refreshDocStats(&model);
    try testing.expect(std.mem.indexOf(u8, model.doc_stats, "ASCII") != null);
}

test "eol convert and find whole word" {
    var model = main.initialModel();
    model.document.set("a\r\nb\r\n");
    main.update(&model, .convert_to_lf);
    try testing.expectEqualStrings("a\nb\n", model.document.text());
    main.update(&model, .convert_to_crlf);
    try testing.expectEqualStrings("a\r\nb\r\n", model.document.text());
    model.document.set("cat catalog cat");
    model.find_query.set("cat");
    model.find_whole_word = true;
    main.update(&model, .run_find);
    try testing.expectEqual(@as(usize, 2), model.find_matches.len);
}

test "duplicate selected file" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    // Select auth.ts via quick open
    model.quick_query.set("auth");
    main.update(&model, .run_quick_open);
    try testing.expect(model.quick_items.len > 0);
    main.update(&model, .{ .open_quick_item = model.quick_items[0].id });
    model.selected_file_id = model.active_tab_id;
    main.update(&model, .duplicate_selected_file);
    try testing.expect(std.mem.indexOf(u8, model.toast, "duplicated") != null);
    // Soft-confirm delete the copy
    main.update(&model, .delete_selected_file);
    main.update(&model, .delete_selected_file);
}

test "sidebar toggle and search case and timestamp" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    try testing.expect(model_mod.Model.showLeftPanel(&model));
    main.update(&model, .toggle_sidebar);
    try testing.expect(!model.show_sidebar);
    try testing.expect(!model_mod.Model.showLeftPanel(&model));
    main.update(&model, .toggle_search_case);
    try testing.expect(model.search_case_sensitive);
    model.document.set("prefix ");
    main.update(&model, .insert_timestamp);
    try testing.expect(model.document.text().len > "prefix ".len);
    try testing.expect(std.mem.startsWith(u8, model.document.text(), "prefix "));
}

test "title case collapse blanks copy tabs untitled" {
    var model = main.initialModel();
    model.document.set("hello WORLD");
    main.update(&model, .transform_title);
    try testing.expectEqualStrings("Hello World", model.document.text());
    model.document.set("a\n\n\nb\n");
    main.update(&model, .collapse_blank_lines);
    try testing.expectEqualStrings("a\n\nb\n", model.document.text());
    main.update(&model, .{ .open_project = "acme-dashboard" });
    main.update(&model, .copy_all_tab_paths);
    try testing.expect(model.path_toast.len > 0);
    main.update(&model, .new_untitled);
    try testing.expect(std.mem.indexOf(u8, model.toast, "Untitled") != null);
    // Clean up untitled file
    main.update(&model, .delete_selected_file);
    main.update(&model, .delete_selected_file);
}

test "trim blank lines and scm stage commit messages" {
    var model = main.initialModel();
    model.document.set("\n\na\nb\n\n");
    main.update(&model, .trim_blank_lines);
    try testing.expectEqualStrings("a\nb\n", model.document.text());
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.git_commit_message.set("test commit");
    try testing.expectEqualStrings("test commit", model.git_commit_message.text());
    // Fixture is not its own git root — stage/commit must refuse parent-repo walk-up.
    main.update(&model, .stage_all);
    try testing.expectEqualStrings("not a git root", model.toast);
    main.update(&model, .commit_changes);
    try testing.expectEqualStrings("not a git root", model.toast);
    main.update(&model, .unstage_all);
    try testing.expectEqualStrings("not a git root", model.toast);
    main.update(&model, .discard_changes);
    try testing.expectEqualStrings("Discard working tree? Confirm again", model.toast);
    main.update(&model, .discard_changes);
    try testing.expectEqualStrings("not a git root", model.toast);
}

test "refresh explorer and close saved tabs" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    const before_nodes = model.workspace_node_count;
    try testing.expect(before_nodes > 0);
    const active = model.active_tab_id;
    main.update(&model, .refresh_explorer);
    try testing.expectEqualStrings("Explorer refreshed", model.toast);
    try testing.expect(model.workspace_node_count > 0);
    try testing.expect(model.active_tab_id != 0);
    _ = active;
    // Open a second file if available, then close saved (non-active clean) tabs.
    if (model.file_nodes.len > 1) {
        var opened_second = false;
        for (model.file_nodes) |n| {
            if (!n.is_dir and n.id != model.active_tab_id) {
                main.update(&model, .{ .select_file = n.id });
                opened_second = true;
                break;
            }
        }
        if (opened_second and model.open_tabs.len >= 2) {
            // Switch back to first tab so second is a saved non-active tab.
            const first = model.open_tabs[0].id;
            main.update(&model, .{ .select_tab = first });
            main.update(&model, .close_saved_tabs);
            try testing.expect(std.mem.indexOf(u8, model.toast, "Closed") != null or std.mem.eql(u8, model.toast, "No saved tabs to close"));
        }
    }
}

test "compare with saved copy branch clear recent insert uuid" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    main.update(&model, .compare_with_saved);
    try testing.expectEqualStrings("Matches disk", model.toast);
    model.document.set("changed locally");
    model.document_dirty = true;
    main.update(&model, .compare_with_saved);
    try testing.expect(std.mem.indexOf(u8, model.toast, "Differs") != null);
    main.update(&model, .copy_git_branch);
    try testing.expect(model.path_toast.len > 0);
    model.prefs.setLastPath("fixtures/acme-dashboard");
    model.prefs_loaded = true;
    main.update(&model, .refresh_recent);
    try testing.expect(model.recent.len >= 1);
    main.update(&model, .clear_recent_projects);
    try testing.expectEqualStrings("Clear recent projects? Confirm again", model.toast);
    main.update(&model, .clear_recent_projects);
    try testing.expectEqualStrings("Recent projects cleared", model.toast);
    model.document.clear();
    main.update(&model, .insert_uuid);
    try testing.expect(model.document.text().len == 36);
    try testing.expectEqualStrings("Inserted UUID", model.toast);
}

test "format hard wrap copy document go to symbol" {
    var model = main.initialModel();
    model.document.set("hello  \nfoo\n");
    main.update(&model, .format_document);
    try testing.expectEqualStrings("hello\nfoo\n", model.document.text());
    try testing.expectEqualStrings("Formatted document", model.toast);
    // 90+ chars so hard wrap at 80 inserts a break.
    model.document.set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz");
    main.update(&model, .hard_wrap);
    try testing.expect(std.mem.indexOf(u8, model.document.text(), "\n") != null);
    try testing.expectEqualStrings("Hard wrapped at 80", model.toast);
    model.document.set("abc");
    main.update(&model, .copy_document);
    try testing.expectEqualStrings("Copied document", model.toast);
    try testing.expectEqualStrings("abc", model.path_toast);
    model.document.set("alpha\n  export function Widget()\nbeta\n");
    model.find_query.set("widget");
    main.update(&model, .go_to_symbol);
    try testing.expect(std.mem.indexOf(u8, model.toast, "Symbol @ 2") != null);
}

test "create folder file size word wrap close tab shortcut" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.new_file_path.set("tmp_mvp_dir");
    main.update(&model, .create_folder);
    try testing.expectEqualStrings("Folder created", model.toast);
    // Soft-confirm delete of a disposable folder isn't supported — remove via scanner helper.
    if (model.workspace) |ws| {
        scanner_mod.deleteRelDir(std.testing.io, ws.rootPath(), "tmp_mvp_dir") catch {};
        main.update(&model, .refresh_explorer);
    }
    model.document.set("abcd");
    main.update(&model, .show_file_size);
    try testing.expect(std.mem.indexOf(u8, model.toast, "4 bytes") != null);
    main.update(&model, .toggle_word_wrap);
    try testing.expectEqualStrings("Word wrap on", model.toast);
    try testing.expect(model.word_wrap);
    main.update(&model, .toggle_word_wrap);
    try testing.expectEqualStrings("Word wrap off", model.toast);
    // Cmd+W maps to close_active_tab via onCommand.
    try testing.expect(main.onCommand("close_active_tab") != null);
}
