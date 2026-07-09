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
