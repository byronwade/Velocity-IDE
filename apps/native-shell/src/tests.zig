const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const model_mod = @import("model/app_model.zig");
const scanner_mod = @import("workspace/scanner.zig");
const hot_exit_store = @import("workspace/hot_exit_store.zig");
const command_registry = @import("core/command_registry.zig");
const keybinding_registry = @import("core/keybinding_registry.zig");
const feature_registry = @import("core/feature_registry.zig");
const settings_store = @import("core/settings_store.zig");

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

fn findByIcon(widget: canvas.Widget, kind: canvas.WidgetKind, icon: []const u8) ?canvas.Widget {
    if (widget.kind == kind and std.mem.eql(u8, widget.icon, icon)) return widget;
    for (widget.children) |child| {
        if (findByIcon(child, kind, icon)) |found| return found;
    }
    return null;
}

/// Assert an icon-only control is present. The markup a11y validator already
/// fails the build if an icon-only control has no accessible name, so matching
/// the icon confirms the control exists in the chrome while accessibility is
/// enforced at markup-check time.
fn expectByIcon(widget: canvas.Widget, kind: canvas.WidgetKind, icon: []const u8) !canvas.Widget {
    return findByIcon(widget, kind, icon) orelse {
        std.debug.print("no {t} with icon \"{s}\" in the view\n", .{ kind, icon });
        return error.WidgetNotFound;
    };
}

fn shortcutMatchesHint(shortcut: native_sdk.Shortcut, hint: []const u8) bool {
    var primary = false;
    var control = false;
    var shift = false;
    var option = false;
    var key: []const u8 = "";
    var parts = std.mem.splitScalar(u8, hint, '+');
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, "Cmd")) {
            primary = true;
        } else if (std.mem.eql(u8, part, "Ctrl")) {
            control = true;
        } else if (std.mem.eql(u8, part, "Shift")) {
            shift = true;
        } else if (std.mem.eql(u8, part, "Alt")) {
            option = true;
        } else {
            key = part;
        }
    }
    return std.ascii.eqlIgnoreCase(shortcut.key, key) and
        shortcut.modifiers.primary == primary and
        shortcut.modifiers.control == control and
        shortcut.modifiers.shift == shift and
        shortcut.modifiers.option == option;
}

fn hasShortcutHint(hint: []const u8) bool {
    for (main.app_shortcuts) |shortcut| {
        if (shortcutMatchesHint(shortcut, hint)) return true;
    }
    return false;
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

test "performance refresh reports measured zeros and unavailable fields honestly" {
    var test_clock: native_sdk.TestClock = .{};
    test_clock.advanceMs(10);
    var model = model_mod.initialModelAt(test_clock.clock(), test_clock.clock().monotonicNanoseconds());
    main.update(&model, .run_perf);
    try testing.expect(model.show_perf_hud);
    try testing.expect(model.perf_snapshot.plugins_loaded.available);
    try testing.expectEqual(@as(u64, 0), model.perf_snapshot.plugins_loaded.value);
    try testing.expect(!model.perf_snapshot.rss_bytes.available);
    try testing.expect(!model.perf_snapshot.external_launch_to_window_ns.available);
    try testing.expectEqual(feature_registry.registered_count, model.features_registered);
    try testing.expectEqual(feature_registry.countLoaded(&feature_registry.catalog), model.features_loaded);
}

test "on_frame resolves palette and terminal request-to-present marks" {
    var test_clock: native_sdk.TestClock = .{};
    test_clock.advanceMs(20);
    var model = model_mod.initialModelAt(test_clock.clock(), test_clock.clock().monotonicNanoseconds());

    main.update(&model, .open_command_palette);
    test_clock.advanceMs(4);
    const palette_frame = native_sdk.GpuFrame{
        .timestamp_ns = test_clock.clock().monotonicNanoseconds(),
        .first_frame_latency_ns = 2 * std.time.ns_per_ms,
        .nonblank = true,
    };
    main.update(&model, main.onFrame(&model, palette_frame).?);
    try testing.expectEqual(@as(u64, 4 * std.time.ns_per_ms), model.perf_timer.marks.command_palette_request_to_present_ns.value_ns);

    main.update(&model, .close_command_palette);
    main.update(&model, .toggle_terminal);
    test_clock.advanceMs(6);
    const terminal_frame = native_sdk.GpuFrame{
        .timestamp_ns = test_clock.clock().monotonicNanoseconds(),
        .nonblank = true,
    };
    main.update(&model, main.onFrame(&model, terminal_frame).?);
    try testing.expectEqual(@as(u64, 6 * std.time.ns_per_ms), model.perf_timer.marks.terminal_panel_request_to_present_ns.value_ns);
}

test "chrome callback semantics use monotonic boot origin" {
    var test_clock: native_sdk.TestClock = .{};
    test_clock.advanceMs(30);
    var model = model_mod.initialModelAt(test_clock.clock(), test_clock.clock().monotonicNanoseconds());
    test_clock.advanceMs(3);
    main.update(&model, main.onChrome(.{}).?);

    try testing.expectEqual(@as(u64, 3 * std.time.ns_per_ms), model.perf_timer.marks.boot_to_first_chrome_callback_ns.value_ns);
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

fn pendingTimerByKey(fx: *model_mod.Effects, key: u64) ?model_mod.Effects.TimerRequest {
    var index: usize = 0;
    while (index < fx.pendingTimerCount()) : (index += 1) {
        const request = fx.pendingTimerAt(index).?;
        if (request.key == key) return request;
    }
    return null;
}

test "updateFx arms one fixed disk poll timer and cancels it on launch" {
    var fx = model_mod.Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = main.initialModel();
    model.disk_poll_interval_ms = 731;

    model_mod.updateFx(&model, .{ .open_project = "acme-dashboard" }, &fx);
    const timer = pendingTimerByKey(&fx, model_mod.disk_poll_timer_key).?;
    try testing.expectEqual(@as(u64, 731), timer.interval_ms);
    try testing.expectEqual(native_sdk.TimerMode.repeating, timer.mode);
    try testing.expect(model.disk_poll_armed);

    model_mod.updateFx(&model, .go_launch, &fx);
    try testing.expect(pendingTimerByKey(&fx, model_mod.disk_poll_timer_key) == null);
    try testing.expect(!model.disk_poll_armed);

    model_mod.updateFx(&model, .{ .open_project = "acme-dashboard" }, &fx);
    model.terminal_command.set("sleep 10");
    model_mod.updateFx(&model, .run_terminal_command, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    model_mod.updateFx(&model, .close_window, &fx);
    try testing.expect(pendingTimerByKey(&fx, model_mod.disk_poll_timer_key) == null);
    try testing.expectEqual(@as(usize, 0), fx.activeCount());
    try testing.expectEqual(@as(u32, 0), model.process_count);
    try testing.expect(!model.terminal_async);
}

test "rejected disk poll stays disarmed without re-arm storm" {
    var fx = model_mod.Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = main.initialModel();
    model_mod.updateFx(&model, .{ .open_project = "acme-dashboard" }, &fx);
    fx.cancelTimer(model_mod.disk_poll_timer_key);

    model_mod.updateFx(&model, .{ .disk_poll_timer = .{
        .key = model_mod.disk_poll_timer_key,
        .outcome = .rejected,
    } }, &fx);
    try testing.expect(model.disk_poll_rejected);
    try testing.expect(!model.disk_poll_armed);
    try testing.expect(pendingTimerByKey(&fx, model_mod.disk_poll_timer_key) == null);

    model_mod.updateFx(&model, .clear_toast, &fx);
    try testing.expect(pendingTimerByKey(&fx, model_mod.disk_poll_timer_key) == null);
}

test "async terminal refuses double run and Stop cancels stable effect" {
    var fx = model_mod.Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = main.initialModel();
    model_mod.updateFx(&model, .{ .open_project = "acme-dashboard" }, &fx);
    model.terminal_command.set("sleep 10");

    model_mod.updateFx(&model, .run_terminal_command, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    try testing.expectEqual(model_mod.terminal_process_effect_key, fx.pendingSpawnAt(0).?.key);
    try testing.expectEqual(@as(u32, 1), model.terminal_process_count);
    try testing.expectEqual(@as(u32, 0), model.governor.recordForEffect(model.terminal_effect_key).?.os_pid);

    model.terminal_command.set("echo interleaved");
    model_mod.updateFx(&model, .run_terminal_command, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    try testing.expect(std.mem.indexOf(u8, model.toast, "Stop Terminal/Task") != null);

    model_mod.updateFx(&model, .stop_terminal_task, &fx);
    try testing.expect(model.terminal_stopping);
    try testing.expectEqual(@as(usize, 0), fx.activeCount());
    model_mod.updateFx(&model, .{ .terminal_exit = .{
        .key = model.terminal_effect_key,
        .code = native_sdk.effect_error_exit_code,
        .reason = .cancelled,
    } }, &fx);
    try testing.expect(!model.terminal_async);
    try testing.expectEqualStrings("cancelled", model.terminal.?.status);
    try testing.expectEqual(
        @import("processes/process_governor.zig").ProcessStatus.cancelled,
        model.governor.recordForEffect(model.terminal_effect_key).?.status,
    );
}

test "task and terminal share one governed effect budget" {
    var fx = model_mod.Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = main.initialModel();
    model_mod.updateFx(&model, .{ .open_project = "acme-dashboard" }, &fx);
    try testing.expect(model.workspace_tasks.len > 0);

    model_mod.updateFx(&model, .run_selected_task, &fx);
    const record = model.governor.recordForEffect(model.terminal_effect_key).?;
    try testing.expect(record.terminal_owned);
    try testing.expect(record.task_owned);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());

    model_mod.updateFx(&model, .run_selected_task, &fx);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
}

test "workspace detects and runs bounded launch profile through shared effect" {
    var fx = model_mod.Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = main.initialModel();
    model_mod.updateFx(&model, .{ .open_project = "acme-dashboard" }, &fx);
    try testing.expectEqual(@as(usize, 1), model.launch_profiles.len);
    try testing.expectEqualStrings("Launch Smoke", model.launch_profiles[0].name);

    model_mod.updateFx(&model, .run_launch_profile, &fx);
    try testing.expect(model.launch_running);
    try testing.expect(std.mem.indexOf(u8, model.launch_status, "Running profile") != null);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    const record = model.governor.recordForEffect(model.terminal_effect_key).?;
    try testing.expect(record.terminal_owned);
    try testing.expect(record.task_owned);

    model_mod.updateFx(&model, .stop_terminal_task, &fx);
    model_mod.updateFx(&model, .{ .terminal_exit = .{
        .key = model.terminal_effect_key,
        .code = native_sdk.effect_error_exit_code,
        .reason = .cancelled,
    } }, &fx);
    try testing.expectEqualStrings("Launch cancelled", model.launch_status);
}

test "output channel selection and clear preserve other sources" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    main.update(&model, .refresh_git);
    try testing.expect(model.output_git_count > 0);
    main.update(&model, .{ .select_output_channel = .git });
    try testing.expectEqual(model.output_git_count, model.output_filtered_count);
    for (model.output_lines) |line| {
        try testing.expectEqual(model_mod.OutputChannel.git, line.channel);
        try testing.expectEqualStrings("git", line.source_label);
    }
    main.update(&model, .clear_output);
    try testing.expectEqual(@as(u32, 0), model.output_git_count);
}

test "toast history is structured deduplicated and safely actionable" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.toast = "diagnostic failed";
    model_mod.update(&model, .save_prefs);
    model_mod.update(&model, .clear_toast);
    model.toast = "diagnostic failed";
    model_mod.update(&model, .save_prefs);
    try testing.expect(model.notification_count > 0);
    const item = model.notification_store.items[0];
    try testing.expectEqual(@as(u32, 2), item.count);
    try testing.expectEqualStrings("open_problems", item.action_id);
    main.update(&model, .{ .run_notification_action = item.id });
    try testing.expect(model.bottom_panel_tab == .problems);
}

test "settings metadata and bounded disk poll cycling reflect persisted prefs" {
    try testing.expect(settings_store.entries.len >= 6);
    var model = main.initialModel();
    model.disk_poll_interval_ms = 500;
    main.update(&model, .cycle_disk_poll_interval);
    try testing.expectEqual(@as(u32, 1000), model.disk_poll_interval_ms);
    try testing.expectEqual(@as(u32, 1000), model.prefs.disk_poll_interval_ms);
    std.Io.Dir.cwd().deleteTree(std.testing.io, ".velocity") catch {};
}

test "workspace search finds auth helper" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.search_query.set("createSession");
    main.update(&model, .run_search);
    try testing.expect(model.search_hits.len > 0);
    try testing.expect(model.current_view == .ide);
    try testing.expect(model.selected_activity == .search);
}

test "incremental workspace search uses one fixed one-shot timer and manual fire" {
    var fx = model_mod.Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = main.initialModel();
    model_mod.updateFx(&model, .{ .open_project = "acme-dashboard" }, &fx);
    model.search_query.set("createSession");
    model_mod.scheduleWorkspaceSearchForTest(&model, &fx);
    model_mod.scheduleWorkspaceSearchForTest(&model, &fx);
    const timer = pendingTimerByKey(&fx, model_mod.search_debounce_timer_key).?;
    try testing.expectEqual(model_mod.search_debounce_ms, timer.interval_ms);
    try testing.expectEqual(native_sdk.TimerMode.one_shot, timer.mode);
    try testing.expect(model.search_debounce_armed);

    fx.cancelTimer(model_mod.search_debounce_timer_key);
    model_mod.updateFx(&model, .{ .search_debounce_timer = .{
        .key = model_mod.search_debounce_timer_key,
        .outcome = .fired,
    } }, &fx);
    try testing.expect(!model.search_debounce_armed);
    try testing.expect(model.search_hits.len > 0);

    model.search_query.clear();
    model_mod.scheduleWorkspaceSearchForTest(&model, &fx);
    try testing.expect(pendingTimerByKey(&fx, model_mod.search_debounce_timer_key) == null);
    try testing.expectEqual(@as(usize, 0), model.search_hits.len);
}

test "rejected incremental search timer stays disarmed and manual search still works" {
    var fx = model_mod.Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = main.initialModel();
    model_mod.updateFx(&model, .{ .open_project = "acme-dashboard" }, &fx);
    model.search_query.set("createSession");
    model_mod.scheduleWorkspaceSearchForTest(&model, &fx);
    fx.cancelTimer(model_mod.search_debounce_timer_key);
    model_mod.updateFx(&model, .{ .search_debounce_timer = .{
        .key = model_mod.search_debounce_timer_key,
        .outcome = .rejected,
    } }, &fx);
    try testing.expect(!model.search_debounce_armed);
    try testing.expect(std.mem.indexOf(u8, model.toast, "press Search") != null);
    model_mod.updateFx(&model, .run_search, &fx);
    try testing.expect(model.search_hits.len > 0);
}

test "workspace search scope and whole word match workspace replace preview" {
    const root = "zig-out/test-model-search-scope";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root ++ "/src");
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/src/a.txt", .data = "cat catalog cat\n" });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/outside.txt", .data = "cat\n" });
    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    model.search_query.set("cat");
    model.search_include.set("src/*");
    model.search_whole_word = true;
    main.update(&model, .run_search);
    try testing.expectEqual(@as(usize, 1), model.search_hits.len);
    model.replace_text.set("dog");
    main.update(&model, .preview_workspace_replace);
    try testing.expectEqual(@as(usize, 1), model.replace_previews.len);
    try testing.expectEqual(@as(u32, 2), model.replace_previews[0].replacements);
}

test "search and line jumps populate back forward navigation and branch" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    const initial_path = model.activeTabPath();
    model.search_query.set("createSession");
    main.update(&model, .run_search);
    try testing.expect(model.search_hits.len > 0);
    main.update(&model, .{ .open_search_hit = model.search_hits[0].id });
    const target_path = model.activeTabPath();
    try testing.expect(model.navigation.canBack());
    main.update(&model, .navigate_back);
    try testing.expectEqualStrings(initial_path, model.activeTabPath());
    main.update(&model, .navigate_forward);
    try testing.expectEqualStrings(target_path, model.activeTabPath());
    main.update(&model, .navigate_back);
    model.goto_line_input.set("2");
    main.update(&model, .goto_line);
    try testing.expect(!model.navigation.canForward());
}

test "editor chrome exposes accessible navigation controls" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    main.update(&model, .{ .select_activity = .search });
    const tree = try buildTree(arena_state.allocator(), &model);
    // Back/Forward are icon-only (chevron) controls in the Precision Workbench
    // chrome. The a11y validator guarantees they carry an accessible name; the
    // chevron icons are unique to the navigation controls in this view.
    _ = try expectByIcon(tree.root, .button, "chevron-left");
    _ = try expectByIcon(tree.root, .button, "chevron-right");
    _ = try expectByText(tree.root, .button, "Whole Word");
}

test "git status refresh on scm activity" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    main.update(&model, .{ .select_activity = .scm });
    try testing.expect(model.current_view == .ide);
    try testing.expect(model.selected_activity == .scm);
    // Fixture is not a real git repo (nested .git not committed); expect graceful summary.
    try testing.expect(model.git_summary.len > 0);
    try testing.expectEqual(@as(usize, 0), model.git_entries.len);
    for (model.file_nodes) |node| try testing.expect(!node.has_scm);
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

test "explorer filter searches full tree and includes matching ancestors" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    const before = model.file_nodes.len;
    var folder_id: u32 = 0;
    for (model.file_nodes) |node| {
        if (node.is_dir) {
            folder_id = node.id;
            break;
        }
    }
    try testing.expect(folder_id != 0);
    main.update(&model, .{ .toggle_explorer_folder = folder_id });
    const collapsed_count = model.file_nodes.len;
    model.explorer_filter.set("auth");
    model_mod.applyExplorerFilter(&model);
    try testing.expect(model.file_nodes.len < before);
    try testing.expect(model.file_nodes.len > 0);
    var direct_hits: usize = 0;
    for (model.file_nodes) |n| {
        const hit = std.ascii.indexOfIgnoreCase(n.name, "auth") != null or std.ascii.indexOfIgnoreCase(n.path, "auth") != null;
        if (hit) direct_hits += 1;
    }
    try testing.expect(direct_hits > 0);
    try testing.expect(model.file_nodes.len >= direct_hits);
    model.explorer_filter.clear();
    model_mod.applyExplorerFilter(&model);
    try testing.expectEqual(collapsed_count, model.file_nodes.len);
}

test "reveal in explorer expands active file ancestors" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    const active = model.active_tab_id;
    main.update(&model, .collapse_all_explorer);
    try testing.expect(model.explorer_collapse.count > 0);
    model.selected_file_id = 0;
    main.update(&model, .reveal_in_explorer);
    try testing.expect(model.selected_file_id == active or model.selected_file_id != 0);
    try testing.expect(model.selected_activity == .explorer);
    try testing.expect(model.explorer_collapse.count == 0 or model.file_nodes.len > 1);
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
    try testing.expect(!model_mod.Model.showBottomPanel(&model));
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
    try testing.expect(model.diff_review_open);
    try testing.expect(model.diff_lines.len >= 3);
    try testing.expect(std.mem.indexOf(u8, model.diff_review_title, "Diff Review") != null);
    main.update(&model, .close_diff_review);
    try testing.expect(!model.diff_review_open);
    model.document.set("changed locally");
    model.document_dirty = true;
    main.update(&model, .compare_with_saved);
    try testing.expect(model.diff_review_open);
    var saw_addition = false;
    var saw_deletion = false;
    for (model.diff_lines) |line| {
        if (line.kind == .addition) saw_addition = true;
        if (line.kind == .deletion) saw_deletion = true;
    }
    try testing.expect(saw_addition);
    try testing.expect(saw_deletion);
    main.update(&model, .dismiss_overlay);
    try testing.expect(!model.diff_review_open);
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

test "fixture snippet picker appends literally and undo restores document" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    const before = try testing.allocator.dupe(u8, model.document.text());
    defer testing.allocator.free(before);
    main.update(&model, .open_snippet_picker);
    try testing.expect(model.snippet_picker_open);
    try testing.expect(model.snippet_items.len >= 2);
    const snippet = model.snippet_items[0];
    main.update(&model, .{ .append_snippet = snippet.id });
    try testing.expect(!model.snippet_picker_open);
    try testing.expect(model.document_dirty);
    try testing.expect(std.mem.endsWith(u8, model.document.text(), snippet.body));
    main.update(&model, .undo_edit);
    try testing.expectEqualStrings(before, model.document.text());
}

test "snippet append refuses the document cap" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    main.update(&model, .open_snippet_picker);
    try testing.expect(model.snippet_items.len > 0);
    var full: [model_mod.max_document]u8 = [_]u8{'x'} ** model_mod.max_document;
    model.document.set(&full);
    main.update(&model, .{ .append_snippet = model.snippet_items[0].id });
    try testing.expectEqualStrings("Append Snippet refused: document limit exceeded", model.toast);
    try testing.expectEqual(@as(usize, model_mod.max_document), model.document.text().len);
}

test "format hard wrap copy document go to symbol" {
    var model = main.initialModel();
    model.document.set("hello  \nfoo\n");
    main.update(&model, .format_document);
    try testing.expectEqualStrings("hello\nfoo\n", model.document.text());
    try testing.expectEqualStrings("Formatted document", model.toast);
    // Idempotent when already clean.
    main.update(&model, .format_document);
    try testing.expectEqualStrings("Already formatted", model.toast);
    // Missing final newline + trailing spaces.
    model.document.set("line  ");
    main.update(&model, .format_document);
    try testing.expectEqualStrings("line\n", model.document.text());
    // CRLF documents keep CR when formatting.
    model.document.set("a  \r\nb\t");
    main.update(&model, .format_document);
    try testing.expectEqualStrings("a\r\nb\r\n", model.document.text());
    // Shortcut wiring.
    try testing.expect(main.onCommand("format_document") != null);
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
    try testing.expect(model.editor_focus_line == 2);
    try testing.expect(model.hasPeek());
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

test "toast notification history and update check" {
    var model = main.initialModel();
    main.update(&model, .check_for_updates);
    try testing.expect(model.update_banner_visible);
    try testing.expect(std.mem.indexOf(u8, model.update_banner, "up to date") != null);
    try testing.expect(model.hasToast());
    try testing.expect(model.notification_count >= 1);
    main.update(&model, .clear_toast);
    try testing.expect(!model.hasToast());
    main.update(&model, .dismiss_update_banner);
    try testing.expect(!model.hasUpdateBanner());
    main.update(&model, .toggle_notifications_panel);
    try testing.expect(model.notifications_panel_open);
}

test "sidebar keeps editor for search scm problems" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    try testing.expect(model.showIdeChrome());
    main.update(&model, .{ .select_activity = .search });
    try testing.expect(model.current_view == .ide);
    try testing.expect(model.isSearch());
    try testing.expect(model.showLeftPanel());
    try testing.expect(model.showIdeChrome());
    main.update(&model, .{ .select_activity = .scm });
    try testing.expect(model.current_view == .ide);
    try testing.expect(model.isScm());
    try testing.expect(model.showIdeChrome());
    main.update(&model, .{ .select_activity = .problems });
    try testing.expect(model.current_view == .ide);
    try testing.expect(model.showBottomProblems());
    try testing.expect(model.problemsSelected());
    try testing.expect(model.showIdeChrome());
}

test "find panel opens on find command and clears on escape" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    try testing.expect(!model.show_find_panel);
    main.update(&model, .run_find);
    try testing.expect(model.show_find_panel);
    main.update(&model, .dismiss_overlay);
    try testing.expect(!model.show_find_panel);
}

test "quiet boot defaults hide agent and terminal" {
    var model = main.initialModel();
    try testing.expect(!model.show_terminal);
    try testing.expect(!model.show_agent_panel);
    model_mod.ensurePrefsOnBoot(&model);
    try testing.expect(!model.update_banner_visible);
}

test "file tree indent marks and folder select" {
    var model = main.initialModel();
    try testing.expectEqualStrings(">", model.file_nodes[0].kind_mark);
    try testing.expectEqualStrings("-", model.file_nodes[1].kind_mark);
    try testing.expect(model.file_nodes[1].indent.len > 0);
    main.update(&model, .{ .open_project = "acme-dashboard" });
    // Select a directory node — should not open as editor.
    var dir_id: u32 = 0;
    for (model.file_nodes) |n| {
        if (n.is_dir) {
            dir_id = n.id;
            break;
        }
    }
    try testing.expect(dir_id != 0);
    main.update(&model, .{ .select_file = dir_id });
    try testing.expectEqualStrings("Folder selected", model.toast);
}

test "settings sections and chrome trailing" {
    var model = main.initialModel();
    main.update(&model, .open_settings);
    try testing.expect(model.isSettings());
    try testing.expect(model.showSettingsAppearance());
    model.settings_query.set("editor");
    try testing.expect(model.showSettingsEditor());
    try testing.expect(!model.showSettingsAppearance());
    main.update(&model, .{ .chrome_changed = .{ .insets = .{ .left = 78, .top = 52, .right = 12 } } });
    try testing.expect(model.chrome_leading == 78);
    try testing.expect(model.chrome_trailing == 12);
    try testing.expect(model.chrome_seen_insets);
    main.update(&model, .{ .chrome_changed = .{ .insets = .{} } });
    try testing.expect(model.window_fullscreen);
    try testing.expectEqualStrings("Entered fullscreen", model.toast);
}

test "settings accessibility labels and empty search state" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var model = main.initialModel();
    main.update(&model, .open_settings);
    model.appearance.high_contrast = true;
    model.appearance.reduce_motion = true;
    try testing.expect(model.showSettingsAccessibility());
    try testing.expectEqualStrings("System high contrast: enabled", model.systemHighContrastLabel());
    try testing.expectEqualStrings("System reduce motion: enabled", model.systemReduceMotionLabel());
    const accessibility_tree = try buildTree(arena_state.allocator(), &model);
    _ = try expectByText(accessibility_tree.root, .text, "Accessibility");
    _ = try expectByText(accessibility_tree.root, .button, "Keyboard Shortcuts");
    _ = try expectByText(accessibility_tree.root, .button, "Notification History");

    model.settings_query.set("does-not-exist");
    try testing.expect(model.showSettingsNoResults());
    const empty_tree = try buildTree(arena_state.allocator(), &model);
    _ = try expectByText(empty_tree.root, .text, "No settings found");
}

test "outline sidebar and symbol palette" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    var auth_id: ?u32 = null;
    for (model.file_nodes) |n| {
        if (std.mem.eql(u8, n.path, "src/server/auth.ts")) auth_id = n.id;
    }
    try testing.expect(auth_id != null);
    main.update(&model, .{ .select_file = auth_id.? });
    main.update(&model, .open_outline);
    try testing.expect(model.showSidebarOutline());
    try testing.expect(model.outline_symbols.len > 0);
    main.update(&model, .go_to_symbol);
    try testing.expect(model.symbol_palette_open);
    const first = model.outline_symbols[0];
    main.update(&model, .{ .select_outline_symbol = first.id });
    try testing.expect(model.editor_focus_line == first.line);
    try testing.expect(model.hasPeek());
}

test "go to definition finds symbol in workspace" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.find_query.set("createSession");
    main.update(&model, .go_to_definition);
    try testing.expect(model.def_hits.len > 0 or model.editor_focus_line > 0);
    try testing.expect(model.hasPeek() or std.mem.indexOf(u8, model.toast, "Definition") != null or std.mem.indexOf(u8, model.toast, "not found") == null);
}

test "bottom panel tabs terminal output problems" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    try testing.expect(!model.showBottomPanel());
    main.update(&model, .toggle_terminal);
    try testing.expect(model.showBottomTerminal());
    try testing.expect(model.terminalSelected());
    main.update(&model, .{ .select_bottom_tab = .output });
    try testing.expect(model.showBottomOutput());
    main.update(&model, .{ .select_bottom_tab = .problems });
    try testing.expect(model.showBottomProblems());
    main.update(&model, .scan_problems);
    try testing.expect(model.problems.len > 0);
    main.update(&model, .toggle_bottom_panel);
    try testing.expect(!model.showBottomPanel());
}

test "palette terminal command uses bottom panel state" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    main.update(&model, .{ .run_command = "toggle_terminal" });
    try testing.expect(model.bottom_panel_open);
    try testing.expect(model.bottom_panel_tab == .terminal);
    try testing.expectEqualStrings("Integrated terminal panel: shown", model.terminalPanelLabel());

    main.update(&model, .{ .select_bottom_tab = .output });
    try testing.expectEqualStrings("Integrated terminal panel: hidden", model.terminalPanelLabel());
    main.update(&model, .{ .run_command = "toggle_terminal" });
    try testing.expect(model.bottom_panel_open);
    try testing.expect(model.bottom_panel_tab == .terminal);
    main.update(&model, .{ .run_command = "toggle_terminal" });
    try testing.expect(!model.bottom_panel_open);
}

test "breadcrumb segments are clickable" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    var auth_id: ?u32 = null;
    for (model.file_nodes) |n| {
        if (std.mem.eql(u8, n.path, "src/server/auth.ts")) auth_id = n.id;
    }
    try testing.expect(auth_id != null);
    main.update(&model, .{ .select_file = auth_id.? });
    try testing.expect(model.breadcrumb_segs.len >= 2);
    const root = model.breadcrumb_segs[0];
    main.update(&model, .{ .select_breadcrumb = root.id });
    try testing.expect(model.selected_activity == .explorer);
}

test "quick open prefers recent files" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    var auth_id: ?u32 = null;
    for (model.file_nodes) |n| {
        if (std.mem.eql(u8, n.path, "src/server/auth.ts")) auth_id = n.id;
    }
    try testing.expect(auth_id != null);
    main.update(&model, .{ .select_file = auth_id.? });
    try testing.expect(model.recent_file_count > 0);
    model.quick_query.clear();
    main.update(&model, .run_quick_open);
    try testing.expect(model.quick_items.len > 0);
    try testing.expect(std.mem.indexOf(u8, model.quick_items[0].path, "auth") != null);
}

test "line peek dismisses on escape" {
    var model = main.initialModel();
    model.document.set("a\nb\nc\nd\ne\n");
    model.goto_line_input.set("3");
    main.update(&model, .goto_line);
    try testing.expect(model.editor_focus_line == 3);
    try testing.expect(model.hasPeek());
    main.update(&model, .dismiss_overlay);
    try testing.expect(!model.hasPeek());
}

test "terminal diagnostics populate clickable problems" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.terminal_command.set("echo 'src/server/auth.ts(1,1): error TS9999: smoke failure'");
    main.update(&model, .run_terminal_command);
    try testing.expect(model.problems.len == 1);
    try testing.expectEqualStrings("src/server/auth.ts", model.problems[0].path);
    try testing.expectEqualStrings("error", model.problems[0].severity_label);
    try testing.expectEqualStrings("TS9999", model.problems[0].kind);
    try testing.expect(model.showBottomProblems());
    const id = model.problems[0].id;
    main.update(&model, .{ .open_problem = id });
    try testing.expectEqualStrings("src/server/auth.ts", model.activeTabPath());
    try testing.expect(model.editor_focus_line == 1);
    try testing.expect(model.hasPeek());
}

test "manual diagnostic parse reports empty terminal" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    main.update(&model, .parse_terminal_diagnostics);
    try testing.expectEqualStrings("No terminal output", model.toast);
}

test "find navigation updates line peek" {
    var model = main.initialModel();
    model.document.set("alpha\nneedle\nbeta\nneedle\n");
    model.find_query.set("needle");
    main.update(&model, .run_find);
    try testing.expect(model.editor_focus_line == 2);
    try testing.expect(model.hasPeek());
    main.update(&model, .find_next);
    try testing.expect(model.editor_focus_line == 4);
}

test "dirty tab text survives switching" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    var first: u32 = 0;
    var second: u32 = 0;
    for (model.file_nodes) |node| {
        if (node.is_dir) continue;
        if (first == 0) {
            first = node.id;
        } else {
            second = node.id;
            break;
        }
    }
    try testing.expect(first != 0 and second != 0);
    main.update(&model, .{ .select_file = first });
    model.document.set("unsaved working copy\n");
    model.document_dirty = true;
    model_mod.syncActiveTabDirtyForTest(&model);
    main.update(&model, .{ .select_file = second });
    main.update(&model, .{ .select_tab = first });
    try testing.expectEqualStrings("unsaved working copy\n", model.document.text());
    try testing.expect(model.document_dirty);
}

test "save all writes every dirty tab" {
    const root = "zig-out/test-model-save-all";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "a\n" });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/b.txt", .data = "b\n" });

    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    const ws = model.workspace.?;
    const a = ws.findNodeByPath("a.txt").?;
    const b = ws.findNodeByPath("b.txt").?;

    main.update(&model, .{ .select_file = a.id });
    model.document.set("a saved all\n");
    model.document_dirty = true;
    model_mod.syncActiveTabDirtyForTest(&model);
    main.update(&model, .{ .select_file = b.id });
    model.document.set("b saved all\n");
    model.document_dirty = true;
    model_mod.syncActiveTabDirtyForTest(&model);
    main.update(&model, .save_all);
    try testing.expectEqualStrings("Saved all", model.toast);

    var out: [64]u8 = undefined;
    const a_disk = try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/a.txt", &out);
    try testing.expectEqualStrings("a saved all\n", a_disk);
    const b_disk = try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/b.txt", &out);
    try testing.expectEqualStrings("b saved all\n", b_disk);
}

test "save all preserves conflicts while saving unaffected dirty tabs" {
    const root = "zig-out/test-model-save-all-partial";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "a\n" });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/b.txt", .data = "b\n" });
    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    const ws = model.workspace.?;
    const a = ws.findNodeByPath("a.txt").?;
    const b = ws.findNodeByPath("b.txt").?;
    main.update(&model, .{ .select_file = a.id });
    model.document.set("a working\n");
    model.document_dirty = true;
    model_mod.syncActiveTabDirtyForTest(&model);
    main.update(&model, .{ .select_file = b.id });
    model.document.set("b working\n");
    model.document_dirty = true;
    model_mod.syncActiveTabDirtyForTest(&model);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "a external\n" });

    main.update(&model, .save_all);
    try testing.expect(ws.tabIsDirty(a.id));
    try testing.expect(!ws.tabIsDirty(b.id));
    try testing.expect(std.mem.indexOf(u8, model.toast, "1 conflicts") != null);
    var out: [64]u8 = undefined;
    try testing.expectEqualStrings(
        "a external\n",
        try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/a.txt", &out),
    );
    try testing.expectEqualStrings(
        "b working\n",
        try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/b.txt", &out),
    );
}

test "safe save blocks external changes and requires overwrite confirmation" {
    const root = "zig-out/test-safe-save";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "original\n" });

    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    model.document.set("working copy\n");
    model.document_dirty = true;
    model_mod.syncActiveTabDirtyForTest(&model);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "external edit\n" });

    main.update(&model, .save_file);
    try testing.expect(model.disk_changed);
    try testing.expect(model.document_dirty);
    try testing.expect(std.mem.startsWith(u8, model.toast, "File changed on disk"));
    var out: [64]u8 = undefined;
    const protected = try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/a.txt", &out);
    try testing.expectEqualStrings("external edit\n", protected);

    main.update(&model, .overwrite_file);
    try testing.expect(std.mem.startsWith(u8, model.toast, "Overwrite changed file"));
    main.update(&model, .overwrite_file);
    try testing.expect(!model.disk_changed);
    try testing.expect(!model.document_dirty);
    const overwritten = try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/a.txt", &out);
    try testing.expectEqualStrings("working copy\n", overwritten);
}

test "forced overwrite creates backup and refreshes disk baseline" {
    const root = "zig-out/test-model-backup-overwrite";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "original\n" });

    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    model.document.set("working\n");
    model.document_dirty = true;
    model_mod.syncActiveTabDirtyForTest(&model);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "external\n" });
    main.update(&model, .save_file);
    main.update(&model, .overwrite_file);
    main.update(&model, .overwrite_file);

    var out: [64]u8 = undefined;
    const backup = try std.Io.Dir.cwd().readFile(
        std.testing.io,
        root ++ "/.velocity/backups/a.txt.bak",
        &out,
    );
    try testing.expectEqualStrings("external\n", backup);
    try testing.expect(!model.disk_changed);
    try testing.expect(!model.workspace.?.activeFileChanged(std.testing.io));
}

test "bounded edit history supports multi-level undo and redo" {
    var model = main.initialModel();
    model.document.set("start\n");
    var i: usize = 0;
    while (i < 20) : (i += 1) main.update(&model, .insert_blank_line);
    const latest_len = model.document.text().len;
    i = 0;
    while (i < 16) : (i += 1) main.update(&model, .undo_edit);
    try testing.expect(model.document.text().len < latest_len);
    const undone_len = model.document.text().len;
    i = 0;
    while (i < 16) : (i += 1) main.update(&model, .redo_edit);
    try testing.expect(model.document.text().len > undone_len);
    try testing.expectEqualStrings("Redone", model.toast);
}

test "undo histories survive tab switches without mixing documents" {
    const root = "zig-out/test-model-tab-histories";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "a\n" });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/b.txt", .data = "b\n" });

    var model = main.initialModel();
    defer model.deinit();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    const ws = model.workspace.?;
    const a = ws.findNodeByPath("a.txt").?;
    const b = ws.findNodeByPath("b.txt").?;

    main.update(&model, .{ .select_file = a.id });
    main.update(&model, .insert_blank_line);
    try testing.expectEqualStrings("a\n\n", model.document.text());
    main.update(&model, .{ .select_file = b.id });
    main.update(&model, .insert_blank_line);
    try testing.expectEqualStrings("b\n\n", model.document.text());

    main.update(&model, .{ .select_tab = a.id });
    main.update(&model, .undo_edit);
    try testing.expectEqualStrings("a\n", model.document.text());
    main.update(&model, .{ .select_tab = b.id });
    try testing.expectEqualStrings("b\n\n", model.document.text());
    main.update(&model, .undo_edit);
    try testing.expectEqualStrings("b\n", model.document.text());
    try testing.expectEqual(@as(usize, 2), model.tab_histories.?.count());

    main.update(&model, .{ .close_tab = a.id });
    main.update(&model, .{ .close_tab = a.id });
    try testing.expect(model.tab_histories.?.get("a.txt") == null);
    try testing.expect(model.tab_histories.?.get("b.txt") != null);
}

test "clean tab eviction drops undo history and reopen starts fresh" {
    const root = "zig-out/test-model-tab-history-eviction";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    const names = [_][]const u8{
        "a.txt", "b.txt", "c.txt", "d.txt", "e.txt",
        "f.txt", "g.txt", "h.txt", "i.txt",
    };
    for (names) |name| {
        var path_buf: [128]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ root, name });
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = name });
    }

    var model = main.initialModel();
    defer model.deinit();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    main.update(&model, .insert_blank_line);
    main.update(&model, .save_file);
    try testing.expect(model.tab_histories.?.get("a.txt").?.canUndo());

    for (names[1..]) |name| {
        const node = model.workspace.?.findNodeByPath(name).?;
        main.update(&model, .{ .select_file = node.id });
    }
    try testing.expect(model.tab_histories.?.get("a.txt") == null);

    const reopened = model.workspace.?.findNodeByPath("a.txt").?;
    main.update(&model, .{ .select_file = reopened.id });
    try testing.expect(!model.tab_histories.?.get("a.txt").?.canUndo());
}

test "active backup restore previews confirms and refuses unsafe states" {
    const root = "zig-out/test-model-backup-restore";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "original\n" });

    var model = main.initialModel();
    defer model.deinit();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);

    main.update(&model, .restore_backup);
    try testing.expectEqualStrings("No backup exists for the active file", model.backup_restore_status);

    model.document.set("working\n");
    model.document_dirty = true;
    model_mod.syncActiveTabDirtyForTest(&model);
    main.update(&model, .restore_backup);
    try testing.expect(std.mem.startsWith(u8, model.backup_restore_status, "Save or discard"));

    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "external\n" });
    main.update(&model, .save_file);
    main.update(&model, .overwrite_file);
    main.update(&model, .overwrite_file);
    try testing.expect(!model.document_dirty);

    main.update(&model, .restore_backup);
    try testing.expect(std.mem.startsWith(u8, model.backup_restore_status, "Backup preview:"));
    var out: [64]u8 = undefined;
    try testing.expectEqualStrings(
        "working\n",
        try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/a.txt", &out),
    );
    main.update(&model, .restore_backup);
    try testing.expectEqualStrings(
        "external\n",
        try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/a.txt", &out),
    );
    try testing.expectEqualStrings("external\n", model.document.text());
    try testing.expect(!model.workspace.?.activeFileChanged(std.testing.io));
}

test "folder deletion removes only empty directories and refuses trees" {
    const root = "zig-out/test-model-folder-delete";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root ++ "/empty");
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root ++ "/full");
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/full/keep.txt", .data = "keep\n" });

    var model = main.initialModel();
    defer model.deinit();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    const ws = model.workspace.?;
    const keep = ws.findNodeByPath("full/keep.txt").?;
    main.update(&model, .{ .select_file = keep.id });
    const tab_count = ws.tab_count;

    const full = ws.findNodeByPath("full").?;
    main.update(&model, .{ .select_file = full.id });
    main.update(&model, .delete_selected_file);
    main.update(&model, .delete_selected_file);
    try testing.expectEqualStrings("Folder is not empty; recursive deletion is refused", model.toast);
    _ = try std.Io.Dir.cwd().statFile(std.testing.io, root ++ "/full/keep.txt", .{});
    try testing.expectEqual(tab_count, ws.tab_count);

    const empty = ws.findNodeByPath("empty").?;
    main.update(&model, .{ .select_file = empty.id });
    main.update(&model, .delete_selected_file);
    main.update(&model, .delete_selected_file);
    try testing.expectEqualStrings("Folder deleted", model.toast);
    try testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().statFile(std.testing.io, root ++ "/empty", .{}),
    );
    try testing.expectEqual(tab_count, ws.tab_count);
    try testing.expectEqualStrings("keep\n", model.document.text());
}

test "all dirty tabs and oversized files map to non-destructive UX" {
    const root = "zig-out/test-model-open-errors";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    var names: [9][16]u8 = undefined;
    var name_lens: [9]usize = undefined;
    for (0..9) |i| {
        const name = try std.fmt.bufPrint(&names[i], "{d}.txt", .{i});
        name_lens[i] = name.len;
        var path: [96]u8 = undefined;
        const full = try std.fmt.bufPrint(&path, "{s}/{s}", .{ root, name });
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = full, .data = "text" });
    }
    var oversized: [model_mod.max_document + 1]u8 = undefined;
    @memset(&oversized, 'x');
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/z-large.txt", .data = &oversized });

    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    const ws = model.workspace.?;
    for (0..8) |i| {
        const node = ws.findNodeByPath(names[i][0..name_lens[i]]).?;
        main.update(&model, .{ .select_file = node.id });
        model.document_dirty = true;
        model_mod.syncActiveTabDirtyForTest(&model);
    }
    const active_before = model.active_tab_id;
    const text_before = model.document.text();
    const ninth = ws.findNodeByPath(names[8][0..name_lens[8]]).?;
    main.update(&model, .{ .select_file = ninth.id });
    try testing.expectEqual(active_before, model.active_tab_id);
    try testing.expectEqualStrings(text_before, model.document.text());
    try testing.expect(std.mem.startsWith(u8, model.toast, "All 8 tabs"));

    ws.setTabDirty(ws.tabs[0].id, false);
    const large = ws.findNodeByPath("z-large.txt").?;
    main.update(&model, .{ .select_file = large.id });
    try testing.expectEqual(active_before, model.active_tab_id);
    try testing.expect(std.mem.startsWith(u8, model.toast, "File exceeds"));
}

test "new prefs fields apply persist and restore recent files" {
    std.Io.Dir.cwd().deleteTree(std.testing.io, ".velocity") catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, ".velocity") catch {};
    var model = main.initialModel();
    model.prefs_loaded = true;
    model.prefs.setTheme("light");
    model.prefs.focus_mode = true;
    model.prefs.bottom_panel_open = true;
    model.prefs.bottom_panel_tab = .output;
    model.prefs.disk_poll_interval_ms = 750;
    model.prefs.pushRecentFile("src/main.zig");
    model_mod.ensurePrefsOnBoot(&model);
    try testing.expect(model.focus_mode);
    try testing.expect(model.bottom_panel_open);
    try testing.expectEqual(model_mod.BottomPanelTab.output, model.bottom_panel_tab);
    try testing.expectEqual(@as(u32, 750), model.disk_poll_interval_ms);
    try testing.expectEqualStrings("src/main.zig", model.recent_files[0][0..model.recent_file_lens[0]]);

    model.focus_mode = false;
    model.bottom_panel_tab = .problems;
    model.disk_poll_interval_ms = 1000;
    main.update(&model, .save_prefs);
    var loaded: @import("core/prefs.zig").Prefs = .{};
    loaded.load(std.testing.io);
    try testing.expect(!loaded.focus_mode);
    try testing.expectEqual(@import("core/prefs.zig").BottomPanelTab.problems, loaded.bottom_panel_tab);
    try testing.expectEqual(@as(u32, 1000), loaded.disk_poll_interval_ms);
    try testing.expectEqualStrings("src/main.zig", loaded.recentFile(0));
}

test "manual disk refresh reports active external changes without discarding edits" {
    const root = "zig-out/test-model-disk-poll";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "disk\n" });
    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    model.document.set("unsaved\n");
    model.document_dirty = true;
    model_mod.syncActiveTabDirtyForTest(&model);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "external\n" });

    main.update(&model, .refresh_disk_sync);
    try testing.expect(model.disk_changed);
    try testing.expect(model.document_dirty);
    try testing.expectEqualStrings("unsaved\n", model.document.text());
    try testing.expect(std.mem.startsWith(u8, model.toast, "Active file changed externally"));
    try testing.expect(std.mem.endsWith(u8, model.open_tabs[0].title, " * !"));
}

test "workspace open detects and runs bounded npm task with diagnostics" {
    const root = "zig-out/test-model-task-runner";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root ++ "/src");
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = root ++ "/package.json",
        .data =
        \\{"scripts":{"smoke":"echo 'src/main.ts(1,1): error TS7777: task smoke'"}}
        ,
    });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = root ++ "/src/main.ts",
        .data = "export const smoke = true;\n",
    });

    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    try testing.expectEqual(@as(usize, 1), model.workspace_tasks.len);
    try testing.expectEqualStrings("smoke", model.workspace_tasks[0].name);
    try testing.expectEqual(model.workspace_tasks[0].id, model.selected_task_id);

    main.update(&model, .run_selected_task);
    try testing.expect(std.mem.indexOf(u8, model.terminal_command.text(), "npm run") != null);
    try testing.expectEqual(@as(usize, 1), model.problems.len);
    try testing.expectEqualStrings("TS7777", model.problems[0].kind);
    try testing.expect(model.showBottomProblems());
    try testing.expect(std.mem.indexOf(u8, model.task_status, "code 0") != null);
}

test "workspace replace refuses dirty matching tab then applies after double confirm" {
    const root = "zig-out/test-model-workspace-replace";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = root ++ "/a.txt",
        .data = "alpha alpha\n",
    });

    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    model.search_query.set("alpha");
    model.replace_text.set("beta");
    main.update(&model, .preview_workspace_replace);
    try testing.expectEqual(@as(usize, 1), model.replace_previews.len);
    try testing.expectEqual(@as(u32, 2), model.replace_previews[0].replacements);

    model.document_dirty = true;
    model_mod.syncActiveTabDirtyForTest(&model);
    main.update(&model, .apply_workspace_replace);
    try testing.expect(std.mem.indexOf(u8, model.toast, "unsaved changes") != null);

    model.document_dirty = false;
    model_mod.syncActiveTabDirtyForTest(&model);
    main.update(&model, .apply_workspace_replace);
    try testing.expect(std.mem.startsWith(u8, model.toast, "Apply workspace replace"));
    main.update(&model, .apply_workspace_replace);
    try testing.expect(std.mem.indexOf(u8, model.replace_status, "Applied 2") != null);
    var out: [32]u8 = undefined;
    const disk = try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/a.txt", &out);
    try testing.expectEqualStrings("beta beta\n", disk);
    try testing.expectEqualStrings("beta beta\n", model.document.text());
    try testing.expect(!model.workspace.?.activeFileChanged(std.testing.io));
}

test "workspace replace refuses matching open tab changed on disk" {
    const root = "zig-out/test-model-workspace-replace-stale";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "alpha\n" });
    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    model.search_query.set("alpha");
    model.replace_text.set("beta");
    main.update(&model, .preview_workspace_replace);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "external alpha\n" });
    main.update(&model, .apply_workspace_replace);
    try testing.expect(std.mem.indexOf(u8, model.toast, "changed on disk") != null);
    var out: [32]u8 = undefined;
    try testing.expectEqualStrings(
        "external alpha\n",
        try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/a.txt", &out),
    );
}

test "high value native shortcuts are wired without replacing redo" {
    try testing.expect(main.onCommand("open_folder") != null);
    try testing.expect(main.onCommand("open_settings") != null);
    try testing.expect(main.onCommand("save_all") != null);
    try testing.expect(main.onCommand("workspace_search") != null);
    try testing.expect(main.onCommand("toggle_bottom_panel") != null);
    try testing.expect(main.onCommand("run_selected_task") != null);
    try testing.expect(main.onCommand("redo_edit") != null);
}

test "every native shortcut maps through onCommand" {
    for (main.app_shortcuts, keybinding_registry.defaults) |shortcut, binding| {
        try testing.expectEqualStrings(binding.shortcut_id, shortcut.id);
        try testing.expectEqualStrings(binding.key, shortcut.key);
        try testing.expect(keybinding_registry.isSupportedKey(shortcut.key));
        try testing.expect(main.onCommand(shortcut.id) != null);
    }
}

test "command registry has unique IDs and explicit safe dispatch coverage" {
    for (command_registry.catalog, 0..) |command, index| {
        for (command_registry.catalog[index + 1 ..]) |other| {
            try testing.expect(!std.mem.eql(u8, command.id, other.id));
        }
        switch (command.dispatch) {
            .model => try testing.expect(command.availability != .unavailable),
            .availability_exempt => try testing.expect(
                command.availability == .hidden or command.availability == .unavailable,
            ),
        }
    }
}

test "palette projection hides no-op and labels limited commands" {
    try testing.expectEqual(command_registry.palette.len, model_mod.commands.len);
    for (model_mod.commands) |command| {
        try testing.expect(!std.mem.eql(u8, command.id, "new_agent_task"));
        if (std.mem.eql(u8, command.id, "open_plugins") or
            std.mem.eql(u8, command.id, "check_for_updates"))
        {
            try testing.expectEqual(command_registry.Availability.limited, command.availability);
            try testing.expect(std.mem.indexOf(u8, command.title, "(Limited)") != null);
            try testing.expectEqualStrings("Limited", command.availability_label);
        }
        if (std.mem.eql(u8, command.id, "run_perf")) {
            try testing.expectEqual(command_registry.Availability.available, command.availability);
            try testing.expectEqualStrings("Refresh Performance Metrics", command.title);
        }
    }
}

test "every advertised command shortcut matches its canonical binding" {
    for (command_registry.catalog) |command| {
        if (command.hint.len == 0) continue;
        var matched = false;
        for (keybinding_registry.defaults) |binding| {
            if (std.mem.eql(u8, command.id, binding.canonical_command_id) and
                std.mem.eql(u8, command.hint, binding.hint))
            {
                matched = true;
                break;
            }
        }
        try testing.expect(matched);
        try testing.expect(hasShortcutHint(command.hint));
    }
}

test "bindings are unique, non-orphaned, and aliases are explicit" {
    for (keybinding_registry.defaults, 0..) |binding, index| {
        for (keybinding_registry.defaults[index + 1 ..]) |other| {
            try testing.expect(!std.mem.eql(u8, binding.shortcut_id, other.shortcut_id));
            const same_chord = std.mem.eql(u8, binding.key, other.key) and
                std.meta.eql(binding.modifiers, other.modifiers);
            try testing.expect(!same_chord);
        }
        if (binding.target == .palette) {
            var found = false;
            for (command_registry.catalog) |command| {
                if (std.mem.eql(u8, binding.canonical_command_id, command.id)) {
                    found = true;
                    break;
                }
            }
            try testing.expect(found);
        }
        const canonical = keybinding_registry.canonicalCommandId(binding.shortcut_id);
        try testing.expect(canonical != null);
        try testing.expectEqualStrings(binding.canonical_command_id, canonical.?);
    }
    try testing.expectEqualStrings(
        "run_search",
        keybinding_registry.canonicalCommandId("workspace_search").?,
    );
    const workspace_msg = main.onCommand("workspace_search").?;
    try testing.expect(workspace_msg == .select_activity);
    try testing.expectEqual(model_mod.Activity.search, workspace_msg.select_activity);
}

test "known command feature IDs exist in feature registry" {
    for (command_registry.catalog) |command| {
        const feature_id = command.feature_id orelse continue;
        var found = false;
        for (feature_registry.catalog) |feature| {
            if (std.mem.eql(u8, feature_id, feature.id)) {
                found = true;
                break;
            }
        }
        try testing.expect(found);
    }
}

test "shortcut help is projected from registry" {
    const model = main.initialModel();
    try testing.expectEqual(keybinding_registry.help_items.len, model.shortcut_help_items.len);
    for (model.shortcut_help_items, keybinding_registry.help_items) |actual, expected| {
        try testing.expectEqualStrings(expected.id, actual.id);
        try testing.expectEqualStrings(expected.label, actual.label);
        try testing.expectEqualStrings(expected.hint, actual.hint);
    }
}

test "close persists hot exit and matching workspace restores dirty session" {
    const root = "zig-out/test-model-hot-exit";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "disk\n" });
    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    model.document.set("hot exit edit\n");
    model.document_dirty = true;
    model_mod.syncActiveTabDirtyForTest(&model);
    main.update(&model, .close_window);
    _ = try std.Io.Dir.cwd().statFile(std.testing.io, root ++ "/.velocity/hot-exit.bin", .{});

    var restored = main.initialModel();
    restored.open_path.set(root);
    main.update(&restored, .submit_open_path);
    try testing.expectEqualStrings("Hot-exit session restored", restored.toast);
    try testing.expectEqualStrings("hot exit edit\n", restored.document.text());
    try testing.expect(restored.document_dirty);
}

test "hot exit partial restore reports counts and stale-only session keeps default tab" {
    const root = "zig-out/test-model-hot-exit-partial";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "a\n" });

    const partial_tabs = [_]hot_exit_store.TabInput{
        .{ .path = "a.txt" },
        .{ .path = "missing.txt" },
    };
    try hot_exit_store.persist(std.testing.io, root, .{
        .root = root,
        .active_path = "missing.txt",
        .tabs = &partial_tabs,
    });
    var partial = main.initialModel();
    partial.open_path.set(root);
    main.update(&partial, .submit_open_path);
    try testing.expectEqualStrings("Hot-exit restored 1; skipped 1", partial.toast);
    try testing.expectEqual(@as(usize, 1), partial.open_tabs.len);
    try testing.expectEqualStrings("a.txt", partial.activeTabPath());

    const stale_tabs = [_]hot_exit_store.TabInput{.{ .path = "missing.txt" }};
    try hot_exit_store.persist(std.testing.io, root, .{
        .root = root,
        .active_path = "missing.txt",
        .tabs = &stale_tabs,
    });
    var stale = main.initialModel();
    stale.open_path.set(root);
    main.update(&stale, .submit_open_path);
    try testing.expectEqualStrings("Workspace opened", stale.toast);
    try testing.expectEqual(@as(usize, 1), stale.open_tabs.len);
    try testing.expectEqualStrings("a.txt", stale.activeTabPath());
    try testing.expectEqualStrings("a\n", stale.document.text());
}

test "hot exit refuses dirty unloaded payload and surfaces persistence failure" {
    const root = "zig-out/test-model-hot-exit-unloaded-dirty";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "a\n" });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/b.txt", .data = "b\n" });

    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    const ws = model.workspace.?;
    main.update(&model, .{ .select_file = ws.findNodeByPath("b.txt").?.id });
    ws.tabs[0].dirty = true;
    ws.tab_text_loaded[0] = false;
    model.document_dirty = false;
    main.update(&model, .close_window);

    try testing.expectEqualStrings(
        "Hot-exit persistence failed; dirty tab payload was unavailable",
        model.toast,
    );
    try testing.expect(model.hot_exit_persist_failed);
    try testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().statFile(std.testing.io, root ++ "/.velocity/hot-exit.bin", .{}),
    );
}

test "autosave writes backups refreshes fingerprints and preserves external conflicts" {
    const root = "zig-out/test-model-autosave-integrity";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "a\n" });

    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    model.auto_save = true;
    main.update(&model, .insert_blank_line);
    try testing.expect(!model.document_dirty);
    try testing.expect(!model.workspace.?.activeFileChanged(std.testing.io));
    var out: [64]u8 = undefined;
    try testing.expectEqualStrings(
        "a\n\n",
        try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/a.txt", &out),
    );
    try testing.expectEqualStrings(
        "a\n",
        try std.Io.Dir.cwd().readFile(
            std.testing.io,
            root ++ "/.velocity/backups/a.txt.bak",
            &out,
        ),
    );

    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = root ++ "/a.txt",
        .data = "external\n",
    });
    main.update(&model, .insert_blank_line);
    try testing.expect(model.document_dirty);
    try testing.expect(model.disk_changed);
    try testing.expect(std.mem.startsWith(u8, model.toast, "File changed on disk"));
    try testing.expectEqualStrings(
        "external\n",
        try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/a.txt", &out),
    );
}

test "close all and close other use explicit dirty confirmation flags" {
    const root = "zig-out/test-model-close-confirm-flags";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "a\n" });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/b.txt", .data = "b\n" });

    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    const ws = model.workspace.?;
    const a = ws.findNodeByPath("a.txt").?;
    const b = ws.findNodeByPath("b.txt").?;
    model.document.set("dirty a\n");
    model.document_dirty = true;
    model_mod.syncActiveTabDirtyForTest(&model);
    main.update(&model, .{ .select_file = b.id });

    main.update(&model, .close_other_tabs);
    try testing.expect(model.close_other_confirm_pending);
    try testing.expectEqual(@as(usize, 2), model.open_tabs.len);
    main.update(&model, .close_other_tabs);
    try testing.expect(!model.close_other_confirm_pending);
    try testing.expectEqual(@as(usize, 1), model.open_tabs.len);
    try testing.expectEqual(b.id, model.active_tab_id);

    model.document.set("dirty b\n");
    model.document_dirty = true;
    main.update(&model, .close_all_tabs);
    try testing.expect(model.close_all_confirm_pending);
    try testing.expectEqual(@as(usize, 1), model.open_tabs.len);
    main.update(&model, .close_all_tabs);
    try testing.expect(!model.close_all_confirm_pending);
    try testing.expectEqual(@as(usize, 0), model.open_tabs.len);
    _ = a;
}

test "Git discard refuses an unsaved open tab before confirmation" {
    var model = main.initialModel();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.document.set("unsaved before discard\n");
    model.document_dirty = true;
    main.update(&model, .discard_changes);
    try testing.expectEqualStrings(
        "Discard refused: an open tab has unsaved changes",
        model.toast,
    );
    try testing.expect(model.document_dirty);
}

test "external clean background tab is decorated and reloads on selection" {
    const root = "zig-out/test-model-background-stale-tab";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "a original\n" });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/b.txt", .data = "b original\n" });

    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    const ws = model.workspace.?;
    const a_id = ws.findNodeByPath("a.txt").?.id;
    const b_id = ws.findNodeByPath("b.txt").?.id;
    main.update(&model, .{ .select_file = b_id });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "a external\n" });

    main.update(&model, .refresh_disk_sync);
    var stale_title: []const u8 = "";
    for (model.open_tabs) |tab| {
        if (tab.id == a_id) stale_title = tab.title;
    }
    try testing.expect(std.mem.endsWith(u8, stale_title, " !"));
    try testing.expectEqualStrings("b original\n", model.document.text());

    main.update(&model, .{ .select_tab = a_id });
    try testing.expectEqualStrings("a external\n", model.document.text());
    try testing.expect(!model.disk_changed);
    for (model.open_tabs) |tab| {
        if (tab.id == a_id) try testing.expect(!std.mem.endsWith(u8, tab.title, " !"));
    }
}

test "explorer create rename and delete preserve unrelated dirty tabs" {
    const root = "zig-out/test-model-explorer-session";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "a\n" });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/b.txt", .data = "b\n" });

    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    var ws = model.workspace.?;
    main.update(&model, .{ .select_file = ws.findNodeByPath("b.txt").?.id });
    model.document.set("dirty b\n");
    model.document_dirty = true;
    model_mod.syncActiveTabDirtyForTest(&model);

    model.new_file_path.set("c.txt");
    main.update(&model, .create_new_file);
    try testing.expectEqual(@as(usize, 3), model.open_tabs.len);

    ws = model.workspace.?;
    model.selected_file_id = ws.findNodeByPath("b.txt").?.id;
    model.new_file_path.set("renamed.txt");
    main.update(&model, .rename_selected_file);
    try testing.expectEqualStrings("dirty b\n", model.document.text());
    try testing.expect(model.document_dirty);
    try testing.expectEqualStrings("renamed.txt", Model.activeTabPath(&model));

    ws = model.workspace.?;
    model.selected_file_id = ws.findNodeByPath("c.txt").?.id;
    main.update(&model, .delete_selected_file);
    main.update(&model, .delete_selected_file);
    try testing.expectEqual(@as(usize, 2), model.open_tabs.len);
    try testing.expect(ws.findNodeByPath("c.txt") == null);
    main.update(&model, .{ .select_tab = ws.findNodeByPath("renamed.txt").?.id });
    try testing.expectEqualStrings("dirty b\n", model.document.text());
    try testing.expect(model.document_dirty);

    model.new_file_path.set("empty");
    main.update(&model, .create_folder);
    ws = model.workspace.?;
    model.selected_file_id = ws.findNodeByPath("empty").?.id;
    main.update(&model, .delete_selected_file);
    main.update(&model, .delete_selected_file);
    try testing.expectEqualStrings("Folder deleted", model.toast);
    try testing.expect(ws.findNodeByPath("empty") == null);
}

test "explorer refresh preserves path selection and CRUD prunes stale collapse state" {
    const root = "zig-out/test-model-explorer-collapse";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root ++ "/src");
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root ++ "/empty");
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/src/a.txt", .data = "a\n" });

    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    var ws = model.workspace.?;
    const src = ws.findNodeByPath("src").?;
    main.update(&model, .{ .select_file = src.id });
    main.update(&model, .{ .toggle_explorer_folder = src.id });
    try testing.expect(model.explorer_collapse.contains("src"));
    main.update(&model, .refresh_explorer);
    ws = model.workspace.?;
    try testing.expectEqual(ws.findNodeByPath("src").?.id, model.selected_file_id);
    try testing.expect(model.explorer_collapse.contains("src"));

    const empty = ws.findNodeByPath("empty").?;
    main.update(&model, .{ .toggle_explorer_folder = empty.id });
    try testing.expect(model.explorer_collapse.contains("empty"));
    model.selected_file_id = empty.id;
    main.update(&model, .delete_selected_file);
    main.update(&model, .delete_selected_file);
    try testing.expect(!model.explorer_collapse.contains("empty"));
    try testing.expect(model.explorer_collapse.contains("src"));
}

fn runModelTestGit(cwd: []const u8, argv: []const []const u8) !void {
    const result = try std.process.run(testing.allocator, std.testing.io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
    });
    defer {
        testing.allocator.free(result.stdout);
        testing.allocator.free(result.stderr);
    }
    switch (result.term) {
        .exited => |code| try testing.expectEqual(@as(u8, 0), code),
        else => return error.TestUnexpectedResult,
    }
}

test "model SCM stages literal path and restore reloads clean open tab" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [160]u8 = undefined;
    const root = try std.fmt.bufPrint(&root_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    try runModelTestGit(root, &.{ "git", "init", "-q" });
    try runModelTestGit(root, &.{ "git", "config", "user.email", "model-scm@example.invalid" });
    try runModelTestGit(root, &.{ "git", "config", "user.name", "Model SCM Test" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "tracked.txt", .data = "original\n" });
    try runModelTestGit(root, &.{ "git", "add", "--", "tracked.txt" });
    try runModelTestGit(root, &.{ "git", "commit", "-q", "-m", "initial" });

    var model = main.initialModel();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    const literal_path = "space ;$' file.txt";
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = literal_path, .data = "literal\n" });
    main.update(&model, .refresh_explorer);
    main.update(&model, .refresh_git);
    var literal_id: u32 = 0;
    var untracked_decoration = false;
    for (model.git_entries) |entry| {
        if (std.mem.eql(u8, entry.path, literal_path)) literal_id = entry.id;
    }
    for (model.file_nodes) |node| {
        if (std.mem.eql(u8, node.path, literal_path)) {
            untracked_decoration = std.mem.eql(u8, node.scm_label, "Untracked");
        }
    }
    try testing.expect(literal_id != 0);
    try testing.expect(untracked_decoration);
    main.update(&model, .{ .stage_git_entry = literal_id });
    var staged_literal = false;
    for (model.git_entries) |entry| {
        if (std.mem.eql(u8, entry.path, literal_path)) {
            staged_literal = std.mem.eql(u8, entry.status, "A ");
        }
    }
    try testing.expect(staged_literal);
    for (model.file_nodes) |node| {
        if (std.mem.eql(u8, node.path, literal_path)) {
            try testing.expectEqualStrings("Staged", node.scm_label);
        }
    }

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "tracked.txt", .data = "modified\n" });
    main.update(&model, .refresh_disk_sync);
    try testing.expectEqualStrings("modified\n", model.document.text());
    main.update(&model, .refresh_git);
    var tracked_id: u32 = 0;
    for (model.git_entries) |entry| {
        if (std.mem.eql(u8, entry.path, "tracked.txt")) tracked_id = entry.id;
    }
    try testing.expect(tracked_id != 0);
    for (model.file_nodes) |node| {
        if (std.mem.eql(u8, node.path, "tracked.txt")) {
            try testing.expectEqualStrings("Modified", node.scm_label);
        }
    }
    main.update(&model, .{ .restore_git_entry = tracked_id });
    try testing.expect(std.mem.startsWith(u8, model.toast, "Restore selected file"));
    main.update(&model, .{ .restore_git_entry = tracked_id });
    try testing.expectEqualStrings("restored", model.toast);
    try testing.expectEqualStrings("original\n", model.document.text());
    try testing.expect(!model.document_dirty);
}

test "fixture task discovery preserves npm precedence and labels every source" {
    var model = main.initialModel();
    defer model.deinit();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    try testing.expectEqual(@as(usize, 5), model.workspace_tasks.len);
    try testing.expectEqualStrings("npm", model.workspace_tasks[0].source_label);
    var vscode_seen = false;
    var make_seen = false;
    var task_smoke_count: u32 = 0;
    for (model.workspace_tasks) |task| {
        if (std.mem.eql(u8, task.source_label, "tasks.json")) vscode_seen = true;
        if (std.mem.eql(u8, task.source_label, "Makefile")) make_seen = true;
        if (std.mem.eql(u8, task.name, "task-smoke")) {
            task_smoke_count += 1;
            try testing.expectEqualStrings("npm", task.source_label);
        }
    }
    try testing.expect(vscode_seen);
    try testing.expect(make_seen);
    try testing.expectEqual(@as(u32, 1), task_smoke_count);
}

test "workspace tests pass and mirror bounded labeled output" {
    var model = main.initialModel();
    defer model.deinit();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    main.update(&model, .run_workspace_tests);
    try testing.expectEqual(model_mod.TestStatus.passed, model.test_status);
    try testing.expectEqualStrings("passed", model.test_status_label);
    try testing.expect(model.last_test_task_id != 0);
    var mirrored = false;
    for (model.output_lines) |line| {
        if (std.mem.indexOf(u8, line.text, "velocity-test-smoke-pass") != null) {
            mirrored = true;
            try testing.expectEqualStrings("Test", line.channel_label);
            try testing.expectEqualStrings("npm", line.source_label);
        }
    }
    try testing.expect(mirrored);
    main.update(&model, .rerun_workspace_tests);
    try testing.expectEqual(model_mod.TestStatus.passed, model.test_status);
}

test "workspace test cancellation shares the governed Stop lifecycle" {
    var fx = model_mod.Effects.init(testing.allocator);
    defer fx.deinit();
    fx.executor = .fake;
    var model = main.initialModel();
    defer model.deinit();
    model_mod.updateFx(&model, .{ .open_project = "acme-dashboard" }, &fx);
    model_mod.updateFx(&model, .run_workspace_tests, &fx);
    try testing.expect(model.test_running);
    try testing.expectEqual(model_mod.TestStatus.running, model.test_status);
    try testing.expectEqual(@as(usize, 1), fx.pendingSpawnCount());
    model_mod.updateFx(&model, .stop_terminal_task, &fx);
    model_mod.updateFx(&model, .{ .terminal_exit = .{
        .key = model.terminal_effect_key,
        .code = native_sdk.effect_error_exit_code,
        .reason = .cancelled,
    } }, &fx);
    try testing.expectEqual(model_mod.TestStatus.cancelled, model.test_status);
    try testing.expectEqualStrings("cancelled", model.test_status_label);
}

test "failed workspace test creates one assertion problem and opens Problems" {
    const root = "zig-out/test-model-test-failure";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root ++ "/tests");
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = root ++ "/package.json",
        .data =
        \\{"scripts":{"test":"echo ' ❯ tests/fail.test.ts:2:1'; echo '    at Object.<anonymous> (tests/fail.test.ts:2:1)'; exit 1"}}
        ,
    });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = root ++ "/tests/fail.test.ts",
        .data = "one\ntwo\n",
    });
    var model = main.initialModel();
    defer model.deinit();
    model.open_path.set(root);
    main.update(&model, .submit_open_path);
    main.update(&model, .run_workspace_tests);
    try testing.expectEqual(model_mod.TestStatus.failed, model.test_status);
    try testing.expectEqual(@as(usize, 1), model.problems.len);
    try testing.expectEqualStrings("TEST", model.problems[0].kind);
    try testing.expect(model.showBottomProblems());
}

test "problem severity and source controls expose filtered counts" {
    var model = main.initialModel();
    defer model.deinit();
    main.update(&model, .{ .open_project = "acme-dashboard" });
    model.terminal_command.set("echo 'src/app.tsx(1,1): error TS1: broken'");
    main.update(&model, .run_terminal_command);
    try testing.expectEqual(@as(u32, 1), model.problem_total_count);
    main.update(&model, .{ .set_problem_severity_filter = .warnings });
    try testing.expectEqual(@as(u32, 0), model.problem_filtered_count);
    try testing.expectEqual(@as(usize, 0), model.problems.len);
    main.update(&model, .{ .set_problem_severity_filter = .errors });
    main.update(&model, .{ .set_problem_source_filter = .terminal });
    try testing.expectEqual(@as(u32, 1), model.problem_filtered_count);
    try testing.expectEqualStrings("terminal", model.problems[0].source_label);
}
