//! Velocity IDE — Native SDK shell.
//! Model / Msg / update live in model/app_model.zig; the view is app.native.
//! No network, no plugins, no secrets. Mock IDE UI for product direction.

const std = @import("std");
const runner = @import("runner");
const native_sdk = @import("native_sdk");

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;

const model_mod = @import("model/app_model.zig");
const theme = @import("theme/tokens.zig");

pub const Model = model_mod.Model;
pub const Msg = model_mod.Msg;
pub const update = model_mod.update;
pub const updateFx = model_mod.updateFx;

const canvas_label = "main-canvas";
const window_width: f32 = 1280;
const window_height: f32 = 800;
const window_min_width: f32 = 960;
const window_min_height: f32 = 640;

const app_permissions = [_][]const u8{ native_sdk.security.permission_command, native_sdk.security.permission_view };
const shell_views = [_]native_sdk.ShellView{
    .{
        .label = canvas_label,
        .kind = .gpu_surface,
        .fill = true,
        .role = "Velocity IDE canvas",
        .accessibility_label = "Velocity IDE",
        .gpu_backend = .metal,
        .gpu_pixel_format = .bgra8_unorm,
        .gpu_present_mode = .timer,
        .gpu_alpha_mode = .@"opaque",
        .gpu_color_space = .srgb,
        .gpu_vsync = true,
    },
};
const shell_windows = [_]native_sdk.ShellWindow{.{
    .label = "main",
    .title = "Velocity",
    .width = window_width,
    .height = window_height,
    .min_width = window_min_width,
    .min_height = window_min_height,
    .restore_state = false,
    .titlebar = .hidden_inset_tall,
    .views = &shell_views,
}};
const shell_scene: native_sdk.ShellConfig = .{ .windows = &shell_windows };

pub const app_shortcuts = [_]native_sdk.Shortcut{
    .{ .id = "command_palette", .key = "k", .modifiers = .{ .primary = true } },
    .{ .id = "quick_open", .key = "p", .modifiers = .{ .primary = true } },
    .{ .id = "find_in_file", .key = "f", .modifiers = .{ .primary = true } },
    .{ .id = "goto_line", .key = "g", .modifiers = .{ .primary = true } },
    .{ .id = "toggle_comment", .key = "/", .modifiers = .{ .primary = true } },
    .{ .id = "reopen_closed_tab", .key = "t", .modifiers = .{ .primary = true, .shift = true } },
    .{ .id = "shortcuts_help", .key = "/", .modifiers = .{ .primary = true, .shift = true } },
    .{ .id = "undo_edit", .key = "z", .modifiers = .{ .primary = true } },
    .{ .id = "delete_last_line", .key = "k", .modifiers = .{ .primary = true, .shift = true } },
    .{ .id = "next_tab", .key = "tab", .modifiers = .{ .control = true } },
    .{ .id = "prev_tab", .key = "tab", .modifiers = .{ .control = true, .shift = true } },
    .{ .id = "toggle_sidebar", .key = "b", .modifiers = .{ .primary = true } },
    .{ .id = "new_untitled", .key = "n", .modifiers = .{ .primary = true } },
    .{ .id = "close_active_tab", .key = "w", .modifiers = .{ .primary = true } },
    .{ .id = "escape", .key = "escape" },
    .{ .id = "toggle_terminal", .key = "`", .modifiers = .{ .control = true } },
    .{ .id = "save_file", .key = "s", .modifiers = .{ .primary = true } },
};

pub fn onCommand(name: []const u8) ?Msg {
    if (std.mem.eql(u8, name, "command_palette")) return .open_command_palette;
    if (std.mem.eql(u8, name, "quick_open")) return .run_quick_open;
    if (std.mem.eql(u8, name, "find_in_file")) return .run_find;
    if (std.mem.eql(u8, name, "goto_line")) return .goto_line;
    if (std.mem.eql(u8, name, "toggle_comment")) return .toggle_line_comment;
    if (std.mem.eql(u8, name, "reopen_closed_tab")) return .reopen_closed_tab;
    if (std.mem.eql(u8, name, "shortcuts_help")) return .toggle_shortcuts_help;
    if (std.mem.eql(u8, name, "undo_edit")) return .undo_edit;
    if (std.mem.eql(u8, name, "delete_last_line")) return .delete_last_line;
    if (std.mem.eql(u8, name, "next_tab")) return .next_tab;
    if (std.mem.eql(u8, name, "prev_tab")) return .prev_tab;
    if (std.mem.eql(u8, name, "toggle_sidebar")) return .toggle_sidebar;
    if (std.mem.eql(u8, name, "new_untitled")) return .new_untitled;
    if (std.mem.eql(u8, name, "close_active_tab")) return .close_active_tab;
    if (std.mem.eql(u8, name, "escape")) return .dismiss_overlay;
    if (std.mem.eql(u8, name, "toggle_terminal")) return .toggle_terminal;
    if (std.mem.eql(u8, name, "save_file")) return .save_file;
    return null;
}

pub fn onChrome(chrome: native_sdk.WindowChrome) ?Msg {
    return .{ .chrome_changed = chrome };
}

pub fn onAppearance(appearance: native_sdk.Appearance) ?Msg {
    return .{ .set_appearance = appearance };
}

pub fn tokensFromModel(model: *const Model) canvas.DesignTokens {
    return theme.tokens(
        model.theme_preference,
        model.appearance.high_contrast,
        model.appearance.reduce_motion,
    );
}

pub const AppUi = canvas.Ui(Msg);
pub const app_markup = @embedFile("app.native");

const VelocityApp = native_sdk.UiApp(Model, Msg);

pub fn initialModel() Model {
    return model_mod.initialModel();
}

pub fn main(init: std.process.Init) !void {
    const app_state = try VelocityApp.create(std.heap.page_allocator, .{
        .name = "velocity-ide",
        .scene = shell_scene,
        .canvas_label = canvas_label,
        .update_fx = updateFx,
        .tokens_fn = tokensFromModel,
        .on_appearance = onAppearance,
        .on_chrome = onChrome,
        .on_command = onCommand,
        .markup = .{ .source = app_markup, .watch_path = "src/app.native", .io = init.io },
    });
    defer app_state.destroy();
    app_state.model = initialModel();
    app_state.model.io = init.io;
    model_mod.ensurePrefsOnBoot(&app_state.model);

    try runner.runWithOptions(app_state.app(), .{
        .app_name = "velocity-ide",
        .window_title = "Velocity",
        .bundle_id = "dev.velocity.ide",
        .icon_path = "assets/icon.png",
        .default_frame = geometry.RectF.init(0, 0, window_width, window_height),
        .restore_state = false,
        .js_window_api = false,
        .shortcuts = &app_shortcuts,
        .security = .{
            .permissions = &app_permissions,
            .navigation = .{ .allowed_origins = &.{ "zero://inline", "zero://app" } },
        },
    }, init);
}

test {
    _ = @import("tests.zig");
    _ = @import("core/feature_registry.zig");
    _ = @import("core/prefs.zig");
    _ = @import("processes/process_governor.zig");
    _ = @import("workspace/scanner.zig");
    _ = @import("workspace/workspace_store.zig");
    _ = @import("workspace/search.zig");
    _ = @import("workspace/find_in_doc.zig");
    _ = @import("workspace/quick_open.zig");
    _ = @import("workspace/replace.zig");
    _ = @import("workspace/edit_transforms.zig");
    _ = @import("workspace/problems.zig");
    _ = @import("terminal/terminal_session.zig");
    _ = @import("scm/git_status.zig");
}
