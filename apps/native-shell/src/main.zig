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
    .{ .id = "escape", .key = "escape" },
    .{ .id = "toggle_terminal", .key = "`", .modifiers = .{ .control = true } },
};

pub fn onCommand(name: []const u8) ?Msg {
    if (std.mem.eql(u8, name, "command_palette")) return .open_command_palette;
    if (std.mem.eql(u8, name, "escape")) return .close_command_palette;
    if (std.mem.eql(u8, name, "toggle_terminal")) return .toggle_terminal;
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
        .update = update,
        .tokens_fn = tokensFromModel,
        .on_appearance = onAppearance,
        .on_chrome = onChrome,
        .on_command = onCommand,
        .markup = .{ .source = app_markup, .watch_path = "src/app.native", .io = init.io },
    });
    defer app_state.destroy();
    app_state.model = initialModel();

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
    _ = @import("processes/process_governor.zig");
}
