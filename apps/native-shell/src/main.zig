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
const keybinding_registry = @import("core/keybinding_registry.zig");

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
        .gpu_backend = .software,
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

pub const app_shortcuts = keybinding_registry.project(native_sdk.Shortcut);

pub fn onCommand(shortcut_id: []const u8) ?Msg {
    // This alias intentionally opens Search without running the current query.
    if (std.mem.eql(u8, shortcut_id, "workspace_search")) return .{ .select_activity = .search };
    const name = keybinding_registry.canonicalCommandId(shortcut_id) orelse shortcut_id;
    if (std.mem.eql(u8, name, "command_palette")) return .open_command_palette;
    if (std.mem.eql(u8, name, "quick_open")) return .run_quick_open;
    if (std.mem.eql(u8, name, "find_in_file")) return .run_find;
    if (std.mem.eql(u8, name, "goto_line")) return .goto_line;
    if (std.mem.eql(u8, name, "toggle_line_comment")) return .toggle_line_comment;
    if (std.mem.eql(u8, name, "reopen_closed_tab")) return .reopen_closed_tab;
    if (std.mem.eql(u8, name, "toggle_shortcuts_help")) return .toggle_shortcuts_help;
    if (std.mem.eql(u8, name, "undo_edit")) return .undo_edit;
    if (std.mem.eql(u8, name, "redo_edit")) return .redo_edit;
    if (std.mem.eql(u8, name, "delete_last_line")) return .delete_last_line;
    if (std.mem.eql(u8, name, "next_tab")) return .next_tab;
    if (std.mem.eql(u8, name, "prev_tab")) return .prev_tab;
    if (std.mem.eql(u8, name, "toggle_sidebar")) return .toggle_sidebar;
    if (std.mem.eql(u8, name, "new_untitled")) return .new_untitled;
    if (std.mem.eql(u8, name, "close_active_tab")) return .close_active_tab;
    if (std.mem.eql(u8, name, "format_document")) return .format_document;
    if (std.mem.eql(u8, name, "move_line_up")) return .move_line_up;
    if (std.mem.eql(u8, name, "move_line_down")) return .move_line_down;
    if (std.mem.eql(u8, name, "indent_document")) return .indent_document;
    if (std.mem.eql(u8, name, "outdent_document")) return .outdent_document;
    if (std.mem.eql(u8, name, "go_to_symbol")) return .go_to_symbol;
    if (std.mem.eql(u8, name, "go_to_definition")) return .go_to_definition;
    if (std.mem.eql(u8, name, "open_folder")) return .{ .open_project = "acme-dashboard" };
    if (std.mem.eql(u8, name, "open_settings")) return .open_settings;
    if (std.mem.eql(u8, name, "save_all")) return .save_all;
    if (std.mem.eql(u8, name, "toggle_bottom_panel")) return .toggle_bottom_panel;
    if (std.mem.eql(u8, name, "run_selected_task")) return .run_selected_task;
    if (std.mem.eql(u8, name, "toggle_agent")) return .toggle_agent_panel;
    if (std.mem.eql(u8, name, "toggle_word_wrap")) return .toggle_word_wrap;
    if (std.mem.eql(u8, name, "escape")) return .dismiss_overlay;
    if (std.mem.eql(u8, name, "toggle_terminal")) return .toggle_terminal;
    if (std.mem.eql(u8, name, "run_perf")) return .run_perf;
    if (std.mem.eql(u8, name, "save_file")) return .save_file;
    return null;
}

pub fn onChrome(chrome: native_sdk.WindowChrome) ?Msg {
    return .{ .chrome_changed = chrome };
}

pub fn onFrame(model: *const Model, frame: native_sdk.GpuFrame) ?Msg {
    const needs_startup_mark =
        (frame.nonblank and !model.perf_timer.marks.boot_to_first_observed_nonblank_ns.available) or
        (frame.first_frame_latency_ns > 0 and !model.perf_timer.marks.sdk_first_frame_latency_ns.available);
    const needs_palette_mark = model.command_palette_open and model.perf_timer.palette_pending_ns != null;
    const needs_terminal_mark = model.bottom_panel_open and
        model.bottom_panel_tab == .terminal and
        model.perf_timer.terminal_pending_ns != null;
    if (!needs_startup_mark and !needs_palette_mark and !needs_terminal_mark) return null;
    return .{ .perf_frame = .{
        .timestamp_ns = frame.timestamp_ns,
        .first_frame_latency_ns = frame.first_frame_latency_ns,
        .nonblank = frame.nonblank,
    } };
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
    const perf_clock: native_sdk.Clock = .system;
    const boot_ns = perf_clock.monotonicNanoseconds();
    const app_state = try VelocityApp.create(std.heap.page_allocator, .{
        .name = "velocity-ide",
        .scene = shell_scene,
        .canvas_label = canvas_label,
        .update_fx = updateFx,
        .tokens_fn = tokensFromModel,
        .on_appearance = onAppearance,
        .on_chrome = onChrome,
        .on_frame = onFrame,
        .on_command = onCommand,
        .markup = .{ .source = app_markup, .watch_path = "src/app.native", .io = init.io },
    });
    defer app_state.destroy();
    app_state.model = model_mod.initialModelAt(perf_clock, boot_ns);
    defer app_state.model.deinit();
    app_state.model.io = init.io;
    if (init.environ_map.get("VELOCITY_USER_CONFIG")) |path| {
        model_mod.setUserSnippetsPath(&app_state.model, path);
    }
    if (init.environ_map.get("PATH")) |path| {
        model_mod.setEnvPath(&app_state.model, path);
    }
    model_mod.ensurePrefsOnBoot(&app_state.model);

    try runner.runWithOptions(app_state.app(), .{
        .app_name = "velocity-ide",
        .window_title = "Velocity",
        .bundle_id = "dev.velocity.ide",
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
    _ = @import("workspace/explorer_projection.zig");
    _ = @import("workspace/search.zig");
    _ = @import("workspace/find_in_doc.zig");
    _ = @import("workspace/quick_open.zig");
    _ = @import("workspace/navigation_history.zig");
    _ = @import("workspace/replace.zig");
    _ = @import("workspace/edit_transforms.zig");
    _ = @import("workspace/problems.zig");
    _ = @import("workspace/problem_matchers.zig");
    _ = @import("workspace/file_fingerprint.zig");
    _ = @import("workspace/backup_store.zig");
    _ = @import("workspace/hot_exit_store.zig");
    _ = @import("workspace/undo_stack.zig");
    _ = @import("workspace/disk_sync.zig");
    _ = @import("workspace/task_detector.zig");
    _ = @import("workspace/workspace_replace.zig");
    _ = @import("workspace/outline.zig");
    _ = @import("workspace/go_to_def.zig");
    _ = @import("workspace/editor_view.zig");
    _ = @import("bridge/editor_island.zig");
    _ = @import("lsp/jsonrpc.zig");
    _ = @import("lsp/broker.zig");
    _ = @import("lsp/broker_transport.zig");
    _ = @import("lsp/lsp_session.zig");
    _ = @import("terminal/terminal_session.zig");
    _ = @import("terminal/pty_session.zig");
    _ = @import("scm/git_status.zig");
    _ = @import("perf/perf_model.zig");
    _ = @import("perf/startup_timer.zig");
}
