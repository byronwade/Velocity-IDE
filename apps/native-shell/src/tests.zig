const std = @import("std");
const native_sdk = @import("native_sdk");
const main = @import("main.zig");
const model_mod = @import("model/app_model.zig");

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
