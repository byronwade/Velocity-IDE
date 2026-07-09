//! Velocity IDE application model — explicit TEA state.
//! Workspace folder open reads from disk (bounded scan). No network/plugins/secrets.

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const canvas = native_sdk.canvas;
const theme = @import("../theme/tokens.zig");
const workspace_store = @import("../workspace/workspace_store.zig");
const workspace_search = @import("../workspace/search.zig");
const find_in_doc = @import("../workspace/find_in_doc.zig");
const quick_open = @import("../workspace/quick_open.zig");
const replace_mod = @import("../workspace/replace.zig");
const terminal_session = @import("../terminal/terminal_session.zig");
const process_governor = @import("../processes/process_governor.zig");
const git_status = @import("../scm/git_status.zig");
const prefs_mod = @import("../core/prefs.zig");

pub const header_natural_height: f32 = 44;
pub const max_command_query = 64;
pub const max_agent_prompt = 160;
pub const max_document = workspace_store.max_editor_bytes;
pub const max_open_path = 240;
pub const max_terminal_command = terminal_session.max_command;
pub const max_search_query = workspace_search.max_query;
pub const max_new_file_path = 160;
pub const max_find_query = find_in_doc.max_query;
pub const max_quick_query = quick_open.max_query;
pub const max_goto_line = 12;
pub const max_replace = 64;
pub const SearchHit = workspace_search.SearchHit;
pub const GitEntry = git_status.GitEntry;
pub const DocMatch = find_in_doc.DocMatch;
pub const QuickItem = quick_open.QuickItem;

pub const ViewKind = enum { launch, ide, plugins, settings, perf, features, processes, search, scm, debug, testing };
pub const Activity = enum { explorer, search, scm, agents, terminal, plugins, settings, debug, testing, features, processes };
pub const AgentStatus = enum { running, planning, ready_for_review, failed, completed };

pub const FileNode = workspace_store.FileNode;
pub const Tab = workspace_store.Tab;

pub const AgentTask = struct {
    id: u32,
    title: []const u8,
    status: AgentStatus,
    status_label: []const u8,
    detail: []const u8,
};

pub const PluginEntry = struct {
    id: []const u8,
    name: []const u8,
    publisher: []const u8,
    version: []const u8,
    trust: []const u8,
    permissions_summary: []const u8,
};

pub const RecentProject = struct {
    name: []const u8,
    path: []const u8,
    branch: []const u8,
};

pub const CommandItem = struct {
    id: []const u8,
    title: []const u8,
    hint: []const u8,
};

pub const Msg = union(enum) {
    open_command_palette,
    close_command_palette,
    update_command_query: canvas.TextInputEvent,
    run_command: []const u8,
    select_activity: Activity,
    toggle_terminal,
    toggle_agent_panel,
    select_file: u32,
    open_tab: u32,
    close_tab: u32,
    select_tab: u32,
    open_project: []const u8,
    go_launch,
    create_agent_task,
    update_agent_prompt: canvas.TextInputEvent,
    switch_theme,
    open_plugin_registry,
    open_settings,
    open_feature_matrix,
    open_process_governor,
    run_perf_check_placeholder,
    kill_all_workspace_processes,
    instant_safe_mode,
    edit_document: canvas.TextInputEvent,
    save_file,
    update_open_path: canvas.TextInputEvent,
    submit_open_path,
    update_terminal_command: canvas.TextInputEvent,
    run_terminal_command,
    clear_terminal,
    update_search_query: canvas.TextInputEvent,
    run_search,
    open_search_hit: u32,
    refresh_git,
    open_git_entry: u32,
    clear_find,
    reopen_last_workspace,
    update_new_file_path: canvas.TextInputEvent,
    create_new_file,
    delete_selected_file,
    rename_selected_file,
    update_find_query: canvas.TextInputEvent,
    run_find,
    find_next,
    find_prev,
    update_quick_query: canvas.TextInputEvent,
    run_quick_open,
    open_quick_item: u32,
    close_quick_open,
    save_prefs,
    update_goto_line: canvas.TextInputEvent,
    goto_line,
    close_active_tab,
    update_replace_text: canvas.TextInputEvent,
    replace_once,
    replace_all,
    copy_active_path,
    refresh_recent,
    toggle_auto_save,
    toggle_find_case,
    terminal_line: native_sdk.EffectLine,
    terminal_exit: native_sdk.EffectExit,
    chrome_changed: native_sdk.WindowChrome,
    set_appearance: native_sdk.Appearance,

    pub const view_unbound = .{
        "chrome_changed",
        "set_appearance",
        "open_tab",
        "close_tab",
        "open_plugin_registry",
        "open_settings",
        "open_feature_matrix",
        "open_process_governor",
        "kill_all_workspace_processes",
        "instant_safe_mode",
        "save_file",
        "submit_open_path",
        "run_terminal_command",
        "clear_terminal",
        "run_search",
        "refresh_git",
        "clear_find",
        "reopen_last_workspace",
        "create_new_file",
        "delete_selected_file",
        "rename_selected_file",
        "run_find",
        "find_next",
        "find_prev",
        "run_quick_open",
        "close_quick_open",
        "save_prefs",
        "goto_line",
        "close_active_tab",
        "replace_once",
        "replace_all",
        "copy_active_path",
        "refresh_recent",
        "toggle_auto_save",
        "toggle_find_case",
        "terminal_line",
        "terminal_exit",
    };
};

pub const Effects = native_sdk.Effects(Msg);

pub const Model = struct {
    current_view: ViewKind = .launch,
    selected_activity: Activity = .explorer,
    command_palette_open: bool = false,
    command_query: canvas.TextBuffer(max_command_query) = .{},
    agent_prompt: canvas.TextBuffer(max_agent_prompt) = .{},
    show_terminal: bool = true,
    show_agent_panel: bool = true,
    show_perf_hud: bool = false,
    safe_mode: bool = false,
    runtime_mode_label: []const u8 = "Core",
    features_registered: u32 = 200,
    features_loaded: u32 = 8,
    features_enabled: u32 = 0,
    process_count: u32 = 0,
    process_leaked: u32 = 0,
    terminal_process_count: u32 = 0,
    lsp_process_count: u32 = 0,
    plugin_process_count: u32 = 0,
    terminal_scrollback_lines: u32 = 2000,
    mock_label: []const u8 = "mock",
    workspace_from_disk: bool = false,
    workspace_node_count: u32 = 0,
    workspace_scan_error: []const u8 = "",
    workspace: ?*workspace_store.WorkspaceBuffers = null,
    /// Runtime Io from process.Init; tests fall back to std.testing.io.
    io: ?std.Io = null,
    document: canvas.TextBuffer(max_document) = .{},
    document_dirty: bool = false,
    open_path: canvas.TextBuffer(max_open_path) = .{},
    terminal_command: canvas.TextBuffer(max_terminal_command) = .{},
    terminal: ?*terminal_session.TerminalBuffers = null,
    search_bufs: ?*workspace_search.SearchBuffers = null,
    git_bufs: ?*git_status.GitBuffers = null,
    search_query: canvas.TextBuffer(max_search_query) = .{},
    search_hits: []const SearchHit = &.{},
    git_entries: []const GitEntry = &.{},
    git_summary: []const u8 = "not loaded",
    git_branch: []const u8 = "unknown",
    new_file_path: canvas.TextBuffer(max_new_file_path) = .{},
    find_query: canvas.TextBuffer(max_find_query) = .{},
    find_bufs: ?*find_in_doc.FindBuffers = null,
    find_matches: []const DocMatch = &.{},
    find_status: []const u8 = "idle",
    find_active_label: []const u8 = "",
    find_label_buf: [48]u8 = undefined,
    find_case_sensitive: bool = false,
    auto_save: bool = false,
    breadcrumb: []const u8 = "",
    breadcrumb_buf: [260]u8 = undefined,
    quick_query: canvas.TextBuffer(max_quick_query) = .{},
    quick_bufs: ?*quick_open.QuickOpenBuffers = null,
    quick_items: []const QuickItem = &.{},
    quick_open_visible: bool = false,
    goto_line_input: canvas.TextBuffer(max_goto_line) = .{},
    goto_line_label: []const u8 = "",
    goto_line_buf: [32]u8 = undefined,
    replace_text: canvas.TextBuffer(max_replace) = .{},
    doc_stats: []const u8 = "0 lines · 0 bytes",
    doc_stats_buf: [48]u8 = undefined,
    path_toast: []const u8 = "",
    path_toast_buf: [260]u8 = undefined,
    action_toast_buf: [48]u8 = undefined,
    recent_dynamic: [prefs_mod.max_recent]RecentProject = [_]RecentProject{.{ .name = "", .path = "", .branch = "" }} ** prefs_mod.max_recent,
    recent_name_pool: [prefs_mod.max_recent][64]u8 = undefined,
    recent_path_pool: [prefs_mod.max_recent][prefs_mod.max_path]u8 = undefined,
    recent_path_lens: [prefs_mod.max_recent]usize = [_]usize{0} ** prefs_mod.max_recent,
    recent_name_lens: [prefs_mod.max_recent]usize = [_]usize{0} ** prefs_mod.max_recent,
    prefs: prefs_mod.Prefs = .{},
    prefs_loaded: bool = false,
    terminal_effect_key: u64 = 0,
    terminal_async: bool = false,
    governor: process_governor.Governor = .{},
    toast: []const u8 = "",
    editor_mode_label: []const u8 = "read-only mock",
    theme_preference: theme.ThemePreference = .dark,
    appearance: native_sdk.Appearance = .{},
    chrome_leading: f32 = 0,
    header_height: f32 = header_natural_height,
    active_tab_id: u32 = 1,
    selected_file_id: u32 = 2,
    project_name: []const u8 = "acme-dashboard",
    project_branch: []const u8 = "main",
    project_path: []const u8 = "~/src/acme-dashboard",
    status_language: []const u8 = "TypeScript",
    status_plugins: []const u8 = "Plugins: locked",
    status_agent: []const u8 = "Agent: idle",
    status_memory: []const u8 = "Memory: -",
    status_startup: []const u8 = "Startup: -",
    perf_app_start_ms: u32 = 0,
    perf_first_window_ms: u32 = 0,
    perf_first_paint_ms: u32 = 0,
    perf_palette_ms: u32 = 0,
    perf_terminal_ms: u32 = 0,
    perf_rss_mb: u32 = 0,
    perf_plugins_loaded: u32 = 0,
    next_task_id: u32 = 5,

    // Constant payloads for markup on-press bindings (literals are not allowed).
    activity_explorer: Activity = .explorer,
    activity_search: Activity = .search,
    activity_scm: Activity = .scm,
    activity_agents: Activity = .agents,
    activity_terminal: Activity = .terminal,
    activity_plugins: Activity = .plugins,
    activity_settings: Activity = .settings,
    activity_debug: Activity = .debug,
    activity_testing: Activity = .testing,
    activity_features: Activity = .features,
    activity_processes: Activity = .processes,
    project_acme: []const u8 = "acme-dashboard",
    project_scratch: []const u8 = "scratch",

    // Static mock collections exposed for markup `for each=...`
    file_nodes: []const FileNode = &file_tree,
    open_tabs: []const Tab = &tabs,
    tasks: []const AgentTask = &agent_tasks,
    plugins: []const PluginEntry = &plugin_registry,
    recent: []const RecentProject = &recent_projects,
    command_items: []const CommandItem = &commands,
    term_lines: []const []const u8 = &terminal_lines,

    // Fields/fns used by update/theme/tests but not directly bound in markup.
    pub const view_unbound = .{
        "current_view",
        "selected_activity",
        "theme_preference",
        "next_task_id",
        "command_query",
        "agent_prompt",
        "appearance",
        "safe_mode",
        "mock_label",
        "perf_first_window_ms",
        "isIde",
        "isPerf",
        "activeTabTitle",
        "activeTabPath",
        "features_enabled",
        "showPlaceholderPanel",
        "workspace",
        "workspace_from_disk",
        "workspace_scan_error",
        "io",
        "document",
        "document_dirty",
        "open_path",
        "terminal_command",
        "terminal",
        "search_bufs",
        "git_bufs",
        "search_query",
        "new_file_path",
        "find_query",
        "find_bufs",
        "find_label_buf",
        "find_status",
        "find_matches",
        "find_case_sensitive",
        "auto_save",
        "breadcrumb",
        "breadcrumb_buf",
        "quick_query",
        "quick_bufs",
        "goto_line_input",
        "goto_line_buf",
        "goto_line_label",
        "replace_text",
        "doc_stats",
        "doc_stats_buf",
        "path_toast",
        "path_toast_buf",
        "action_toast_buf",
        "pathToast",
        "recent_dynamic",
        "recent_name_pool",
        "recent_path_pool",
        "recent_path_lens",
        "recent_name_lens",
        "prefs",
        "prefs_loaded",
        "terminal_effect_key",
        "terminal_async",
        "governor",
        "editorBody",
    };

    pub fn commandQuery(model: *const Model) []const u8 {
        return model.command_query.text();
    }

    pub fn agentPrompt(model: *const Model) []const u8 {
        return model.agent_prompt.text();
    }

    pub fn isLaunch(model: *const Model) bool {
        return model.current_view == .launch;
    }

    pub fn showShell(model: *const Model) bool {
        return model.current_view != .launch;
    }

    pub fn isIde(model: *const Model) bool {
        return model.current_view == .ide;
    }

    pub fn isPlugins(model: *const Model) bool {
        return model.current_view == .plugins;
    }

    pub fn isSettings(model: *const Model) bool {
        return model.current_view == .settings;
    }

    pub fn isPerf(model: *const Model) bool {
        return model.current_view == .perf;
    }

    pub fn explorerSelected(model: *const Model) bool {
        return model.selected_activity == .explorer;
    }

    pub fn searchSelected(model: *const Model) bool {
        return model.selected_activity == .search;
    }

    pub fn scmSelected(model: *const Model) bool {
        return model.selected_activity == .scm;
    }

    pub fn agentsSelected(model: *const Model) bool {
        return model.selected_activity == .agents;
    }

    pub fn terminalSelected(model: *const Model) bool {
        return model.selected_activity == .terminal;
    }

    pub fn pluginsSelected(model: *const Model) bool {
        return model.selected_activity == .plugins;
    }

    pub fn settingsSelected(model: *const Model) bool {
        return model.selected_activity == .settings;
    }

    pub fn debugSelected(model: *const Model) bool {
        return model.selected_activity == .debug;
    }

    pub fn testingSelected(model: *const Model) bool {
        return model.selected_activity == .testing;
    }

    pub fn featuresSelected(model: *const Model) bool {
        return model.selected_activity == .features;
    }

    pub fn processesSelected(model: *const Model) bool {
        return model.selected_activity == .processes;
    }

    pub fn isFeatures(model: *const Model) bool {
        return model.current_view == .features;
    }

    pub fn isProcesses(model: *const Model) bool {
        return model.current_view == .processes;
    }

    pub fn isSearch(model: *const Model) bool {
        return model.current_view == .search or model.selected_activity == .search;
    }

    pub fn isScm(model: *const Model) bool {
        return model.current_view == .scm or model.selected_activity == .scm;
    }

    pub fn isDebug(model: *const Model) bool {
        return model.current_view == .debug;
    }

    pub fn isTesting(model: *const Model) bool {
        return model.current_view == .testing;
    }

    pub fn showPlaceholderPanel(model: *const Model) bool {
        return model.current_view == .search or model.current_view == .scm or model.current_view == .debug or model.current_view == .testing or model.current_view == .features or model.current_view == .processes;
    }

    pub fn featureMatrixSummary(model: *const Model) []const u8 {
        _ = model;
        return "Registered 200 / Loaded 8 (mock) / Startup-critical only at boot";
    }

    pub fn activeTabTitle(model: *const Model) []const u8 {
        if (model.workspace_from_disk) {
            if (model.workspace) |ws| {
                for (ws.tabsSlice()) |tab| {
                    if (tab.id == model.active_tab_id) return tab.title;
                }
            }
        }
        for (tabs) |tab| {
            if (tab.id == model.active_tab_id) return tab.title;
        }
        return "Untitled";
    }

    pub fn activeTabPath(model: *const Model) []const u8 {
        if (model.workspace_from_disk) {
            if (model.workspace) |ws| {
                const p = ws.editorPath();
                if (p.len > 0) return p;
                for (ws.tabsSlice()) |tab| {
                    if (tab.id == model.active_tab_id) return tab.path;
                }
            }
        }
        for (tabs) |tab| {
            if (tab.id == model.active_tab_id) return tab.path;
        }
        return "";
    }

    pub fn editorBody(model: *const Model) []const u8 {
        if (model.workspace_from_disk) {
            const text = model.document.text();
            if (text.len > 0 or model.document_dirty) return text;
            if (model.workspace) |ws| {
                const body = ws.editorText();
                if (body.len > 0 or ws.editor_path_len > 0) return body;
            }
        }
        return editor_placeholder;
    }

    pub fn documentText(model: *const Model) []const u8 {
        return model.document.text();
    }

    pub fn openPathText(model: *const Model) []const u8 {
        return model.open_path.text();
    }

    pub fn terminalCommandText(model: *const Model) []const u8 {
        return model.terminal_command.text();
    }

    pub fn searchQueryText(model: *const Model) []const u8 {
        return model.search_query.text();
    }

    pub fn newFilePathText(model: *const Model) []const u8 {
        return model.new_file_path.text();
    }

    pub fn findQueryText(model: *const Model) []const u8 {
        return model.find_query.text();
    }

    pub fn replaceText(model: *const Model) []const u8 {
        return model.replace_text.text();
    }

    pub fn documentStats(model: *const Model) []const u8 {
        return model.doc_stats;
    }

    pub fn pathToast(model: *const Model) []const u8 {
        return model.path_toast;
    }

    pub fn breadcrumbText(model: *const Model) []const u8 {
        return model.breadcrumb;
    }

    pub fn autoSaveLabel(model: *const Model) []const u8 {
        return if (model.auto_save) "Auto Save: on" else "Auto Save: off";
    }

    pub fn findCaseLabel(model: *const Model) []const u8 {
        return if (model.find_case_sensitive) "Aa: on" else "Aa: off";
    }

    pub fn terminalPanelLabel(model: *const Model) []const u8 {
        return if (model.show_terminal) "Terminal: shown" else "Terminal: hidden";
    }

    pub fn agentPanelLabel(model: *const Model) []const u8 {
        return if (model.show_agent_panel) "Agent: shown" else "Agent: hidden";
    }

    pub fn quickQueryText(model: *const Model) []const u8 {
        return model.quick_query.text();
    }

    pub fn gotoLineText(model: *const Model) []const u8 {
        return model.goto_line_input.text();
    }

    pub fn searchStatus(model: *const Model) []const u8 {
        if (model.search_bufs) |s| return s.status;
        return "idle";
    }

    pub fn dirtyLabel(model: *const Model) []const u8 {
        return if (model.document_dirty) "dirty" else "clean";
    }

    pub fn terminalStatus(model: *const Model) []const u8 {
        if (model.terminal) |t| return t.status;
        return "idle";
    }

    pub fn workspaceStatus(model: *const Model) []const u8 {
        if (model.workspace_scan_error.len > 0) return model.workspace_scan_error;
        if (model.workspace_from_disk) return "disk";
        return "mock";
    }

    pub fn processGovernorSummary(model: *const Model) []const u8 {
        _ = model;
        return "Pipe terminal via governor / no PTY yet";
    }

    pub fn themeLabel(model: *const Model) []const u8 {
        return switch (model.theme_preference) {
            .dark => "Dark",
            .light => "Light",
            .high_contrast => "High Contrast",
        };
    }

    pub fn showLeftPanel(model: *const Model) bool {
        return model.current_view == .ide and model.selected_activity == .explorer;
    }

    pub fn showIdeChrome(model: *const Model) bool {
        return model.current_view == .ide or model.current_view == .perf;
    }

    pub fn perfSummary(model: *const Model) []const u8 {
        _ = model;
        return "MOCK perf: startup 312ms / paint 184ms / palette 21ms / terminal panel 18ms / RSS 48MB / featuresLoaded 8 / processes 0";
    }
};

pub const recent_projects = [_]RecentProject{
    .{ .name = "acme-dashboard", .path = "fixtures/acme-dashboard", .branch = "main" },
    .{ .name = "velocity-ide", .path = "~/src/velocity-ide", .branch = "feat/shell" },
    .{ .name = "payments-api", .path = "~/src/payments-api", .branch = "develop" },
};

pub const file_tree = [_]FileNode{
    .{ .id = 1, .name = "src", .path = "src", .depth = 0, .is_dir = true },
    .{ .id = 2, .name = "app.tsx", .path = "src/app.tsx", .depth = 1, .is_dir = false },
    .{ .id = 3, .name = "components", .path = "src/components", .depth = 1, .is_dir = true },
    .{ .id = 4, .name = "Chart.tsx", .path = "src/components/Chart.tsx", .depth = 2, .is_dir = false },
    .{ .id = 5, .name = "server", .path = "src/server", .depth = 1, .is_dir = true },
    .{ .id = 6, .name = "auth.ts", .path = "src/server/auth.ts", .depth = 2, .is_dir = false },
    .{ .id = 11, .name = "lib", .path = "src/lib", .depth = 1, .is_dir = true },
    .{ .id = 12, .name = "db.ts", .path = "src/lib/db.ts", .depth = 2, .is_dir = false },
    .{ .id = 7, .name = "package.json", .path = "package.json", .depth = 0, .is_dir = false },
    .{ .id = 8, .name = "README.md", .path = "README.md", .depth = 0, .is_dir = false },
    .{ .id = 9, .name = "tests", .path = "tests", .depth = 0, .is_dir = true },
    .{ .id = 10, .name = "app.test.ts", .path = "tests/app.test.ts", .depth = 1, .is_dir = false },
};

pub const tabs = [_]Tab{
    .{ .id = 1, .title = "app.tsx", .path = "src/app.tsx", .language = "TypeScript React" },
    .{ .id = 2, .title = "auth.ts", .path = "src/server/auth.ts", .language = "TypeScript" },
    .{ .id = 3, .title = "Chart.tsx", .path = "src/components/Chart.tsx", .language = "TypeScript React", .dirty = true },
};

pub const agent_tasks = [_]AgentTask{
    .{ .id = 1, .title = "Build Landing Page", .status = .running, .status_label = "running", .detail = "Generating hero + CTA sections" },
    .{ .id = 2, .title = "Analyze Tab vs Agent Usage", .status = .planning, .status_label = "planning", .detail = "Collecting interaction signals" },
    .{ .id = 3, .title = "Fix CI Failures", .status = .ready_for_review, .status_label = "ready for review", .detail = "3 failing tests patched" },
    .{ .id = 4, .title = "Refactor Auth Flow", .status = .completed, .status_label = "completed", .detail = "Session tokens unified" },
};

pub const terminal_lines = [_][]const u8{
    "$ npm run dev",
    "",
    "  Next.js 15.1.0",
    "  - Local:        http://localhost:3000",
    "  - Ready in 428ms",
    "",
    "Compiled / in 86ms",
};

pub const plugin_registry = [_]PluginEntry{
    .{ .id = "velocity.core-files", .name = "Core Files", .publisher = "velocity", .version = "0.1.0", .trust = "trusted-core", .permissions_summary = "filesystem.read" },
    .{ .id = "velocity.theme-pack", .name = "Theme Pack", .publisher = "velocity", .version = "0.1.0", .trust = "trusted-core", .permissions_summary = "none" },
    .{ .id = "community.fmt", .name = "Format On Save", .publisher = "community", .version = "0.0.0", .trust = "unsigned", .permissions_summary = "filesystem.write (denied)" },
};

pub const commands = [_]CommandItem{
    .{ .id = "open_folder", .title = "Open Folder", .hint = "Cmd+O" },
    .{ .id = "save_file", .title = "Save File", .hint = "Cmd+S" },
    .{ .id = "create_new_file", .title = "New File", .hint = "" },
    .{ .id = "delete_selected_file", .title = "Delete Selected File", .hint = "" },
    .{ .id = "rename_selected_file", .title = "Rename Selected File", .hint = "" },
    .{ .id = "quick_open", .title = "Quick Open File", .hint = "Cmd+P" },
    .{ .id = "find_in_file", .title = "Find in File", .hint = "Cmd+F" },
    .{ .id = "replace_once", .title = "Replace Once", .hint = "" },
    .{ .id = "replace_all", .title = "Replace All", .hint = "" },
    .{ .id = "copy_active_path", .title = "Copy Active Path", .hint = "" },
    .{ .id = "toggle_auto_save", .title = "Toggle Auto Save", .hint = "" },
    .{ .id = "toggle_find_case", .title = "Toggle Find Case Sensitivity", .hint = "" },
    .{ .id = "goto_line", .title = "Go to Line", .hint = "Cmd+G" },
    .{ .id = "close_active_tab", .title = "Close Active Tab", .hint = "" },
    .{ .id = "toggle_terminal", .title = "Toggle Terminal", .hint = "Ctrl+`" },
    .{ .id = "run_terminal", .title = "Run Terminal Command", .hint = "" },
    .{ .id = "run_search", .title = "Search Workspace", .hint = "" },
    .{ .id = "refresh_git", .title = "Refresh Git Status", .hint = "" },
    .{ .id = "reopen_last_workspace", .title = "Reopen Last Workspace", .hint = "" },
    .{ .id = "clear_find", .title = "Clear Find", .hint = "" },
    .{ .id = "toggle_agent", .title = "Toggle Agent Panel", .hint = "Cmd+." },
    .{ .id = "open_plugins", .title = "Open Plugin Registry", .hint = "" },
    .{ .id = "open_settings", .title = "Open Settings", .hint = "Cmd+," },
    .{ .id = "run_perf", .title = "Run Performance Check", .hint = "" },
    .{ .id = "open_feature_matrix", .title = "Open Feature Toggle Matrix", .hint = "" },
    .{ .id = "open_process_governor", .title = "Open Process Governor", .hint = "" },
    .{ .id = "kill_all_workspace_processes", .title = "Kill All Workspace Processes", .hint = "" },
    .{ .id = "instant_safe_mode", .title = "Instant Safe Mode", .hint = "" },
    .{ .id = "switch_theme", .title = "Switch Theme", .hint = "" },
    .{ .id = "new_agent_task", .title = "New Agent Task", .hint = "" },
    .{ .id = "go_launch", .title = "Back to Launch Screen", .hint = "" },
};

pub const editor_placeholder =
    \\import { Chart } from "./components/Chart";
    \\
    \\export default function App() {
    \\  return (
    \\    <main className="page">
    \\      <h1>Acme Dashboard</h1>
    \\      <Chart metric="revenue" />
    \\    </main>
    \\  );
    \\}
;

pub fn initialModel() Model {
    return .{};
}

/// Sync update used by unit tests (no effects channel).
pub fn update(model: *Model, msg: Msg) void {
    updateInner(model, msg, null);
}

/// Runtime update with Native SDK effects (async terminal spawn).
pub fn updateFx(model: *Model, msg: Msg, fx: *Effects) void {
    updateInner(model, msg, fx);
}

fn updateInner(model: *Model, msg: Msg, fx: ?*Effects) void {
    switch (msg) {
        .open_command_palette => {
            model.command_palette_open = true;
            model.command_query.clear();
        },
        .close_command_palette => {
            model.command_palette_open = false;
            model.command_query.clear();
            model.quick_open_visible = false;
        },
        .update_command_query => |edit| model.command_query.apply(edit),
        .run_command => |id| {
            model.command_palette_open = false;
            model.command_query.clear();
            if (std.mem.eql(u8, id, "toggle_terminal")) {
                model.show_terminal = !model.show_terminal;
                persistPrefs(model);
            } else if (std.mem.eql(u8, id, "toggle_agent")) {
                model.show_agent_panel = !model.show_agent_panel;
                persistPrefs(model);
            } else if (std.mem.eql(u8, id, "open_plugins")) {
                model.current_view = .plugins;
                model.selected_activity = .plugins;
            } else if (std.mem.eql(u8, id, "open_settings")) {
                model.current_view = .settings;
                model.selected_activity = .settings;
            } else if (std.mem.eql(u8, id, "run_perf")) {
                applyPerfPlaceholder(model);
                model.show_perf_hud = true;
                model.current_view = .perf;
            } else if (std.mem.eql(u8, id, "switch_theme")) {
                cycleTheme(model);
                persistPrefs(model);
            } else if (std.mem.eql(u8, id, "new_agent_task")) {
                createTask(model);
            } else if (std.mem.eql(u8, id, "go_launch")) {
                model.current_view = .launch;
            } else if (std.mem.eql(u8, id, "open_folder")) {
                openFixtureWorkspace(model, "acme-dashboard");
            } else if (std.mem.eql(u8, id, "save_file")) {
                saveActiveDocument(model);
            } else if (std.mem.eql(u8, id, "create_new_file")) {
                createNewFile(model);
            } else if (std.mem.eql(u8, id, "delete_selected_file")) {
                deleteSelectedFile(model);
            } else if (std.mem.eql(u8, id, "rename_selected_file")) {
                renameSelectedFile(model);
            } else if (std.mem.eql(u8, id, "quick_open")) {
                showQuickOpen(model);
            } else if (std.mem.eql(u8, id, "find_in_file")) {
                runFindInDocument(model);
            } else if (std.mem.eql(u8, id, "replace_once")) {
                replaceOnceInDocument(model);
            } else if (std.mem.eql(u8, id, "replace_all")) {
                replaceAllInDocument(model);
            } else if (std.mem.eql(u8, id, "copy_active_path")) {
                copyActivePath(model);
            } else if (std.mem.eql(u8, id, "toggle_auto_save")) {
                toggleAutoSave(model);
            } else if (std.mem.eql(u8, id, "toggle_find_case")) {
                toggleFindCase(model);
            } else if (std.mem.eql(u8, id, "goto_line")) {
                runGotoLine(model);
            } else if (std.mem.eql(u8, id, "close_active_tab")) {
                closeActiveTab(model);
            } else if (std.mem.eql(u8, id, "run_terminal")) {
                runTerminalFromModel(model, fx);
            } else if (std.mem.eql(u8, id, "run_search")) {
                model.current_view = .search;
                model.selected_activity = .search;
                runWorkspaceSearch(model);
            } else if (std.mem.eql(u8, id, "refresh_git")) {
                model.current_view = .scm;
                model.selected_activity = .scm;
                refreshGitStatus(model);
            } else if (std.mem.eql(u8, id, "reopen_last_workspace")) {
                reopenLastWorkspace(model);
            } else if (std.mem.eql(u8, id, "clear_find")) {
                clearFind(model);
            } else if (std.mem.eql(u8, id, "open_feature_matrix")) {
                model.current_view = .features;
                model.selected_activity = .features;
            } else if (std.mem.eql(u8, id, "open_process_governor")) {
                model.current_view = .processes;
                model.selected_activity = .processes;
            } else if (std.mem.eql(u8, id, "kill_all_workspace_processes")) {
                model.process_count = 0;
                model.terminal_process_count = 0;
                model.lsp_process_count = 0;
                model.plugin_process_count = 0;
                model.process_leaked = 0;
            } else if (std.mem.eql(u8, id, "instant_safe_mode")) {
                model.safe_mode = true;
                model.runtime_mode_label = "Safe";
                model.show_agent_panel = false;
                model.features_loaded = 3;
            }
        },
        .select_activity => |activity| {
            model.selected_activity = activity;
            switch (activity) {
                .plugins => model.current_view = .plugins,
                .settings => model.current_view = .settings,
                .search => {
                    model.current_view = .search;
                    if (model.workspace_from_disk and model.search_hits.len == 0 and model.search_query.text().len > 0) {
                        runWorkspaceSearch(model);
                    }
                },
                .scm => {
                    model.current_view = .scm;
                    refreshGitStatus(model);
                },
                .debug => model.current_view = .debug,
                .testing => model.current_view = .testing,
                .features => model.current_view = .features,
                .processes => model.current_view = .processes,
                .terminal => {
                    model.current_view = .ide;
                    model.show_terminal = true;
                },
                .agents => {
                    model.current_view = .ide;
                    model.show_agent_panel = true;
                },
                else => model.current_view = .ide,
            }
        },
        .toggle_terminal => {
            model.show_terminal = !model.show_terminal;
            persistPrefs(model);
        },
        .toggle_agent_panel => {
            model.show_agent_panel = !model.show_agent_panel;
            persistPrefs(model);
        },
        .select_file => |id| {
            model.selected_file_id = id;
            model.current_view = .ide;
            model.selected_activity = .explorer;
            if (model.workspace_from_disk) {
                if (model.workspace) |ws| {
                    ws.openFileById(modelIo(model), id) catch {};
                    model.active_tab_id = id;
                    model.open_tabs = ws.tabsSlice();
                    if (ws.findNode(id)) |node| {
                        if (!node.is_dir) {
                            model.status_language = workspace_store.scannerLanguage(node.path);
                        }
                    }
                    syncDocumentFromWorkspace(model);
                    return;
                }
            }
            for (tabs) |tab| {
                if (std.mem.eql(u8, tab.path, pathForFile(id))) {
                    model.active_tab_id = tab.id;
                    break;
                }
            }
        },
        .open_tab => |id| {
            model.active_tab_id = id;
            model.current_view = .ide;
        },
        .close_tab => |id| closeTabById(model, id),
        .close_active_tab => closeActiveTab(model),
        .select_tab => |id| {
            model.active_tab_id = id;
            if (model.workspace_from_disk) {
                if (model.workspace) |ws| {
                    ws.openFileById(modelIo(model), id) catch {};
                    model.open_tabs = ws.tabsSlice();
                    syncDocumentFromWorkspace(model);
                }
            }
        },
        .open_project => |name| {
            if (std.mem.eql(u8, name, "scratch")) {
                model.project_name = "scratch";
                model.project_path = "(scratch)";
                model.workspace_from_disk = false;
                model.file_nodes = &file_tree;
                model.open_tabs = &tabs;
                model.document.set(editor_placeholder);
                model.document_dirty = false;
                model.editor_mode_label = "scratch";
                model.current_view = .ide;
                model.selected_activity = .explorer;
            } else {
                openFixtureWorkspace(model, name);
            }
        },
        .go_launch => {
            model.current_view = .launch;
            syncRecentFromPrefs(model);
        },
        .create_agent_task => createTask(model),
        .update_agent_prompt => |edit| model.agent_prompt.apply(edit),
        .switch_theme => {
            cycleTheme(model);
            persistPrefs(model);
        },
        .open_plugin_registry => {
            model.current_view = .plugins;
            model.selected_activity = .plugins;
        },
        .open_settings => {
            model.current_view = .settings;
            model.selected_activity = .settings;
        },
        .run_perf_check_placeholder => {
            applyPerfPlaceholder(model);
            model.show_perf_hud = true;
            model.current_view = .perf;
        },
        .open_feature_matrix => {
            model.current_view = .features;
            model.selected_activity = .features;
        },
        .open_process_governor => {
            model.current_view = .processes;
            model.selected_activity = .processes;
        },
        .kill_all_workspace_processes => {
            model.governor.killFeature("feature.terminal");
            model.process_count = model.governor.aliveCount();
            model.terminal_process_count = 0;
            model.lsp_process_count = 0;
            model.plugin_process_count = 0;
            model.process_leaked = model.governor.leak_count;
            model.toast = "Killed workspace processes";
        },
        .instant_safe_mode => {
            model.safe_mode = true;
            model.runtime_mode_label = "Safe";
            model.show_agent_panel = false;
            model.features_loaded = 3;
        },
        .edit_document => |edit| {
            model.document.apply(edit);
            model.document_dirty = true;
            model.toast = "";
            refreshDocStats(model);
            if (model.auto_save and model.workspace_from_disk) {
                saveActiveDocument(model);
            }
        },
        .save_file => saveActiveDocument(model),
        .update_open_path => |edit| model.open_path.apply(edit),
        .submit_open_path => {
            const path = model.open_path.text();
            if (path.len == 0) {
                model.toast = "Enter a folder path";
            } else {
                openWorkspacePath(model, path);
            }
        },
        .update_terminal_command => |edit| model.terminal_command.apply(edit),
        .run_terminal_command => runTerminalFromModel(model, fx),
        .clear_terminal => {
            if (model.terminal) |t| t.clear();
            model.term_lines = &.{};
            model.toast = "Terminal cleared";
        },
        .update_search_query => |edit| model.search_query.apply(edit),
        .run_search => runWorkspaceSearch(model),
        .open_search_hit => |id| openSearchHit(model, id),
        .refresh_git => refreshGitStatus(model),
        .open_git_entry => |id| openGitEntry(model, id),
        .clear_find => clearFind(model),
        .reopen_last_workspace => reopenLastWorkspace(model),
        .update_new_file_path => |edit| model.new_file_path.apply(edit),
        .create_new_file => createNewFile(model),
        .delete_selected_file => deleteSelectedFile(model),
        .rename_selected_file => renameSelectedFile(model),
        .update_find_query => |edit| model.find_query.apply(edit),
        .run_find => runFindInDocument(model),
        .find_next => findNavigate(model, true),
        .find_prev => findNavigate(model, false),
        .update_replace_text => |edit| model.replace_text.apply(edit),
        .replace_once => replaceOnceInDocument(model),
        .replace_all => replaceAllInDocument(model),
        .copy_active_path => copyActivePath(model),
        .refresh_recent => syncRecentFromPrefs(model),
        .toggle_auto_save => toggleAutoSave(model),
        .toggle_find_case => toggleFindCase(model),
        .update_quick_query => |edit| {
            model.quick_query.apply(edit);
            filterQuickOpen(model);
        },
        .run_quick_open => showQuickOpen(model),
        .open_quick_item => |id| openQuickItem(model, id),
        .close_quick_open => {
            model.quick_open_visible = false;
            model.toast = "";
        },
        .save_prefs => persistPrefs(model),
        .update_goto_line => |edit| model.goto_line_input.apply(edit),
        .goto_line => runGotoLine(model),
        .terminal_line => |line| {
            if (ensureTerminalBuffers(model)) |term| {
                term.pushLine(line.line);
                model.term_lines = term.linesSlice();
                term.status = "running";
            } else |_| {}
        },
        .terminal_exit => |exit| {
            if (ensureTerminalBuffers(model)) |term| {
                term.running = false;
                term.last_exit = exit.code;
                term.status = if (exit.reason == .exited and exit.code == 0) "ok" else "exit";
                var exit_buf: [48]u8 = undefined;
                const exit_msg = std.fmt.bufPrint(&exit_buf, "[exit {d} / {s}]", .{ exit.code, @tagName(exit.reason) }) catch "[exit]";
                term.pushLine(exit_msg);
                model.term_lines = term.linesSlice();
            } else |_| {}
            model.governor.killFeature("feature.terminal");
            model.terminal_process_count = 0;
            model.process_count = model.governor.aliveCount();
            model.terminal_async = false;
            model.toast = if (exit.reason == .exited and exit.code == 0) "Command ok" else "Command exited";
        },
        .chrome_changed => |chrome| {
            model.chrome_leading = chrome.insets.left;
            model.header_height = @max(header_natural_height, chrome.insets.top);
        },
        .set_appearance => |appearance| model.appearance = appearance,
    }
}


fn modelIo(model: *const Model) std.Io {
    if (model.io) |io| return io;
    // Tests may omit model.io; release builds always set it from process.Init.
    if (comptime builtin.is_test) return std.testing.io;
    @panic("model.io not set");
}

fn ensureWorkspaceBuffers(model: *Model) !*workspace_store.WorkspaceBuffers {
    if (model.workspace) |ws| return ws;
    const ws = try std.heap.page_allocator.create(workspace_store.WorkspaceBuffers);
    ws.* = .{};
    model.workspace = ws;
    return ws;
}

fn ensureTerminalBuffers(model: *Model) !*terminal_session.TerminalBuffers {
    if (model.terminal) |t| return t;
    const t = try std.heap.page_allocator.create(terminal_session.TerminalBuffers);
    t.* = .{};
    model.terminal = t;
    return t;
}

fn ensureSearchBuffers(model: *Model) !*workspace_search.SearchBuffers {
    if (model.search_bufs) |s| return s;
    const s = try std.heap.page_allocator.create(workspace_search.SearchBuffers);
    s.* = .{};
    model.search_bufs = s;
    return s;
}

fn ensureGitBuffers(model: *Model) !*git_status.GitBuffers {
    if (model.git_bufs) |g| return g;
    const g = try std.heap.page_allocator.create(git_status.GitBuffers);
    g.* = .{};
    model.git_bufs = g;
    return g;
}

fn syncDocumentFromWorkspace(model: *Model) void {
    if (model.workspace) |ws| {
        model.document.set(ws.editorText());
        model.document_dirty = false;
        model.editor_mode_label = "editable";
        model.toast = "";
        refreshDocStats(model);
        refreshBreadcrumb(model);
    }
}

pub fn refreshDocStats(model: *Model) void {
    const text = model.document.text();
    var lines: u32 = if (text.len == 0) 0 else 1;
    for (text) |c| {
        if (c == '\n') lines += 1;
    }
    if (text.len == 0) lines = 0;
    const label = std.fmt.bufPrint(&model.doc_stats_buf, "{d} lines · {d} bytes", .{ lines, text.len }) catch "stats";
    model.doc_stats = label;
}

pub fn refreshBreadcrumb(model: *Model) void {
    const path = Model.activeTabPath(model);
    if (path.len == 0) {
        model.breadcrumb = model.project_name;
        return;
    }
    const n = @min(path.len, model.breadcrumb_buf.len);
    @memcpy(model.breadcrumb_buf[0..n], path[0..n]);
    // Soften separators for display: keep as-is (path is already relative)
    model.breadcrumb = model.breadcrumb_buf[0..n];
}

fn basenameOf(path: []const u8) []const u8 {
    if (path.len == 0) return path;
    var i = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') {
            return path[i + 1 ..];
        }
    }
    return path;
}

fn syncRecentFromPrefs(model: *Model) void {
    ensurePrefsLoaded(model);
    const count = @min(model.prefs.recent_count, prefs_mod.max_recent);
    if (count == 0) {
        model.recent = &recent_projects;
        return;
    }
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const path = model.prefs.recentPath(i);
        const pn = @min(path.len, model.recent_path_pool[i].len);
        @memcpy(model.recent_path_pool[i][0..pn], path[0..pn]);
        model.recent_path_lens[i] = pn;
        const path_slice = model.recent_path_pool[i][0..pn];

        const base = basenameOf(path_slice);
        const nn = @min(base.len, model.recent_name_pool[i].len);
        if (nn == 0) {
            const fallback = "project";
            @memcpy(model.recent_name_pool[i][0..fallback.len], fallback);
            model.recent_name_lens[i] = fallback.len;
        } else {
            @memcpy(model.recent_name_pool[i][0..nn], base[0..nn]);
            model.recent_name_lens[i] = nn;
        }
        model.recent_dynamic[i] = .{
            .name = model.recent_name_pool[i][0..model.recent_name_lens[i]],
            .path = path_slice,
            .branch = "—",
        };
    }
    model.recent = model.recent_dynamic[0..count];
}

fn replaceOnceInDocument(model: *Model) void {
    const find = model.find_query.text();
    const repl = model.replace_text.text();
    if (find.len == 0) {
        model.toast = "Enter find text";
        return;
    }
    var out: [replace_mod.max_out]u8 = undefined;
    const result = replace_mod.replaceOnce(model.document.text(), find, repl, &out) orelse {
        model.toast = "No match to replace";
        return;
    };
    model.document.set(out[0..result.out_len]);
    model.document_dirty = true;
    refreshDocStats(model);
    runFindInDocument(model);
    model.toast = "Replaced 1";
}

fn replaceAllInDocument(model: *Model) void {
    const find = model.find_query.text();
    const repl = model.replace_text.text();
    if (find.len == 0) {
        model.toast = "Enter find text";
        return;
    }
    var out: [replace_mod.max_out]u8 = undefined;
    const result = replace_mod.replaceAll(model.document.text(), find, repl, &out) orelse {
        model.toast = "No matches to replace";
        return;
    };
    model.document.set(out[0..result.out_len]);
    model.document_dirty = true;
    refreshDocStats(model);
    runFindInDocument(model);
    const msg = std.fmt.bufPrint(&model.action_toast_buf, "Replaced {d}", .{result.count}) catch "Replaced";
    model.toast = msg;
}

fn copyActivePath(model: *Model) void {
    const path = Model.activeTabPath(model);
    if (path.len == 0) {
        model.toast = "No active path";
        model.path_toast = "";
        return;
    }
    const n = @min(path.len, model.path_toast_buf.len);
    @memcpy(model.path_toast_buf[0..n], path[0..n]);
    model.path_toast = model.path_toast_buf[0..n];
    model.toast = model.path_toast;
}

fn applyWorkspaceMeta(model: *Model, ws: *workspace_store.WorkspaceBuffers, meta: workspace_store.Workspace) void {
    model.workspace_from_disk = meta.from_disk;
    model.workspace_node_count = meta.node_count;
    model.workspace_scan_error = meta.scan_error;
    model.project_name = ws.projectName();
    model.project_path = ws.rootPath();
    model.project_branch = meta.branch;
    model.file_nodes = ws.fileNodesSlice();
    model.open_tabs = ws.tabsSlice();
    if (ws.tab_count > 0) {
        model.active_tab_id = ws.tabs[0].id;
        model.selected_file_id = ws.tabs[0].id;
        model.status_language = ws.tabs[0].language;
    }
    syncDocumentFromWorkspace(model);
    model.current_view = .ide;
    model.selected_activity = .explorer;
    model.features_loaded = @max(model.features_loaded, 9);
    model.open_path.set(ws.rootPath());
    ensurePrefsLoaded(model);
    model.prefs.setLastPath(ws.rootPath());
    model.prefs.show_terminal = model.show_terminal;
    model.prefs.show_agent = model.show_agent_panel;
    persistPrefs(model);
    syncRecentFromPrefs(model);
}

fn openWorkspacePath(model: *Model, path: []const u8) void {
    const ws = ensureWorkspaceBuffers(model) catch {
        model.workspace_scan_error = "Allocator failed";
        model.toast = "Allocator failed";
        model.current_view = .ide;
        return;
    };
    const meta = ws.openPath(modelIo(model), path) catch {
        model.workspace_scan_error = "Open failed";
        model.toast = "Could not open folder";
        model.current_view = .ide;
        model.selected_activity = .explorer;
        return;
    };
    applyWorkspaceMeta(model, ws, meta);
    if (meta.scan_error.len > 0) {
        model.toast = meta.scan_error;
    } else {
        model.toast = "Workspace opened";
    }
}

fn openFixtureWorkspace(model: *Model, key: []const u8) void {
    const path = workspace_store.fixturePathForKey(key) orelse {
        // Treat unknown keys as literal relative paths (MVP path open).
        openWorkspacePath(model, key);
        return;
    };
    openWorkspacePath(model, path);
}

fn saveActiveDocument(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Nothing to save (mock workspace)";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    ws.saveActiveFile(modelIo(model), model.document.text()) catch {
        model.toast = "Save failed";
        return;
    };
    model.document_dirty = false;
    model.toast = "Saved";
}

fn runTerminalFromModel(model: *Model, fx: ?*Effects) void {
    const cmd = model.terminal_command.text();
    if (cmd.len == 0) {
        model.toast = "Enter a command";
        return;
    }
    const term = ensureTerminalBuffers(model) catch {
        model.toast = "Terminal alloc failed";
        return;
    };
    const cwd = if (model.workspace_from_disk) model.project_path else "";
    _ = model.governor.spawn("feature.terminal", cmd) catch {};
    model.process_count = model.governor.aliveCount();
    model.terminal_process_count = 1;
    model.show_terminal = true;

    if (fx) |effects| {
        // Async path: wrap with cd when workspace is open (fx.spawn has no cwd).
        term.pushPrompt(cmd);
        term.running = true;
        term.status = "running";
        model.term_lines = term.linesSlice();
        model.terminal_effect_key +%= 1;
        if (model.terminal_effect_key == 0) model.terminal_effect_key = 1;
        model.terminal_async = true;

        var script_buf: [512]u8 = undefined;
        const script = if (cwd.len > 0) blk: {
            // Quote cwd lightly for sh -c; fixture paths are simple.
            break :blk std.fmt.bufPrint(&script_buf, "cd {s} && {s}", .{ cwd, cmd }) catch cmd;
        } else cmd;

        // Keep script alive for the spawn call (copied by effects).
        var script_owned: [512]u8 = undefined;
        const slen = @min(script.len, script_owned.len);
        @memcpy(script_owned[0..slen], script[0..slen]);

        effects.spawn(.{
            .key = model.terminal_effect_key,
            .argv = &.{ "/bin/sh", "-c", script_owned[0..slen] },
            .on_line = Effects.lineMsg(.terminal_line),
            .on_exit = Effects.exitMsg(.terminal_exit),
        });
        model.toast = "Running...";
        return;
    }

    // Sync fallback for unit tests (no effects channel).
    term.runCommand(modelIo(model), cwd, cmd);
    model.term_lines = term.linesSlice();
    model.governor.killFeature("feature.terminal");
    model.terminal_process_count = 0;
    model.process_count = model.governor.aliveCount();
    model.toast = if (term.last_exit == 0) "Command ok" else "Command exited";
}

fn runWorkspaceSearch(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace to search";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    const bufs = ensureSearchBuffers(model) catch {
        model.toast = "Search alloc failed";
        return;
    };
    _ = model.governor.spawn("feature.search", "workspace-search") catch {};
    bufs.search(modelIo(model), ws, model.search_query.text());
    model.search_hits = bufs.hitsSlice();
    model.governor.killFeature("feature.search");
    model.process_count = model.governor.aliveCount();
    model.toast = bufs.status;
    model.current_view = .search;
    model.selected_activity = .search;
}

fn openSearchHit(model: *Model, hit_id: u32) void {
    if (model.search_bufs) |bufs| {
        for (bufs.hitsSlice()) |hit| {
            if (hit.id == hit_id) {
                if (model.workspace) |ws| {
                    if (ws.findNodeByPath(hit.path)) |node| {
                        model.selected_file_id = node.id;
                        model.current_view = .ide;
                        model.selected_activity = .explorer;
                        ws.openFileById(modelIo(model), node.id) catch {};
                        model.active_tab_id = node.id;
                        model.open_tabs = ws.tabsSlice();
                        if (!node.is_dir) {
                            model.status_language = workspace_store.scannerLanguage(node.path);
                        }
                        syncDocumentFromWorkspace(model);
                        model.toast = "Opened search hit";
                        return;
                    }
                }
            }
        }
    }
    model.toast = "Hit not found";
}

fn openGitEntry(model: *Model, entry_id: u32) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace first";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    if (model.git_bufs) |bufs| {
        for (bufs.entriesSlice()) |entry| {
            if (entry.id == entry_id) {
                if (ws.findNodeByPath(entry.path)) |node| {
                    if (node.is_dir) {
                        model.toast = "Directory entry";
                        return;
                    }
                    model.selected_file_id = node.id;
                    model.current_view = .ide;
                    model.selected_activity = .explorer;
                    ws.openFileById(modelIo(model), node.id) catch {
                        model.toast = "Open failed";
                        return;
                    };
                    model.active_tab_id = node.id;
                    model.open_tabs = ws.tabsSlice();
                    model.status_language = workspace_store.scannerLanguage(node.path);
                    syncDocumentFromWorkspace(model);
                    model.toast = "Opened from SCM";
                    return;
                }
                model.toast = "File not in scan (untracked/outside?)";
                return;
            }
        }
    }
    model.toast = "Git entry not found";
}

fn clearFind(model: *Model) void {
    model.find_query.clear();
    model.replace_text.clear();
    model.find_matches = &.{};
    model.find_active_label = "";
    model.find_status = "idle";
    if (model.find_bufs) |f| f.clear();
    model.toast = "Find cleared";
}

fn reopenLastWorkspace(model: *Model) void {
    ensurePrefsLoaded(model);
    const path = model.prefs.lastPathSlice();
    if (path.len == 0) {
        model.toast = "No last workspace";
        return;
    }
    openWorkspacePath(model, path);
}

fn createNewFile(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace first";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    const rel = model.new_file_path.text();
    if (rel.len == 0) {
        model.toast = "Enter a relative path";
        return;
    }
    const id = ws.createFile(modelIo(model), rel, "") catch {
        model.toast = "Create file failed";
        return;
    };
    model.file_nodes = ws.fileNodesSlice();
    model.open_tabs = ws.tabsSlice();
    model.workspace_node_count = ws.file_node_count;
    model.selected_file_id = id;
    model.active_tab_id = id;
    model.status_language = workspace_store.scannerLanguage(rel);
    syncDocumentFromWorkspace(model);
    model.current_view = .ide;
    model.selected_activity = .explorer;
    model.toast = "File created";
    model.new_file_path.clear();
}

fn deleteSelectedFile(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace first";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    const id = model.selected_file_id;
    if (ws.findNode(id)) |node| {
        if (node.is_dir) {
            model.toast = "Cannot delete directories yet";
            return;
        }
    } else {
        model.toast = "No file selected";
        return;
    }
    ws.deleteFileById(modelIo(model), id) catch {
        model.toast = "Delete failed";
        return;
    };
    model.file_nodes = ws.fileNodesSlice();
    model.open_tabs = ws.tabsSlice();
    model.workspace_node_count = ws.file_node_count;
    if (ws.tab_count > 0) {
        model.active_tab_id = ws.tabs[0].id;
        model.selected_file_id = ws.tabs[0].id;
        model.status_language = ws.tabs[0].language;
        syncDocumentFromWorkspace(model);
    } else {
        model.document.clear();
        model.document_dirty = false;
        model.selected_file_id = 0;
        model.active_tab_id = 0;
    }
    model.toast = "File deleted";
}

fn renameSelectedFile(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace first";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    const new_rel = model.new_file_path.text();
    if (new_rel.len == 0) {
        model.toast = "Enter new path in New field";
        return;
    }
    const id = ws.renameFileById(modelIo(model), model.selected_file_id, new_rel) catch {
        model.toast = "Rename failed";
        return;
    };
    model.file_nodes = ws.fileNodesSlice();
    model.open_tabs = ws.tabsSlice();
    model.workspace_node_count = ws.file_node_count;
    model.selected_file_id = id;
    model.active_tab_id = id;
    model.status_language = workspace_store.scannerLanguage(new_rel);
    syncDocumentFromWorkspace(model);
    model.toast = "File renamed";
    model.new_file_path.clear();
}

fn ensureFindBuffers(model: *Model) !*find_in_doc.FindBuffers {
    if (model.find_bufs) |f| return f;
    const f = try std.heap.page_allocator.create(find_in_doc.FindBuffers);
    f.* = .{};
    model.find_bufs = f;
    return f;
}

fn ensureQuickBuffers(model: *Model) !*quick_open.QuickOpenBuffers {
    if (model.quick_bufs) |q| return q;
    const q = try std.heap.page_allocator.create(quick_open.QuickOpenBuffers);
    q.* = .{};
    model.quick_bufs = q;
    return q;
}

fn updateFindLabel(model: *Model) void {
    if (model.find_bufs) |f| {
        if (f.match_count == 0) {
            model.find_active_label = "0/0";
            return;
        }
        const label = std.fmt.bufPrint(&model.find_label_buf, "{d}/{d} L{d}", .{
            f.active_index + 1,
            f.match_count,
            if (f.activeMatch()) |m| m.line else 0,
        }) catch "find";
        model.find_active_label = label;
    } else {
        model.find_active_label = "";
    }
}

fn runFindInDocument(model: *Model) void {
    const bufs = ensureFindBuffers(model) catch {
        model.toast = "Find alloc failed";
        return;
    };
    bufs.findWithOptions(model.document.text(), model.find_query.text(), model.find_case_sensitive);
    model.find_matches = bufs.matchesSlice();
    model.find_status = bufs.status;
    updateFindLabel(model);
    if (bufs.match_count == 0) {
        model.toast = bufs.status;
    } else {
        const msg = std.fmt.bufPrint(&model.action_toast_buf, "{d} matches", .{bufs.match_count}) catch "matches";
        model.toast = msg;
    }
}

fn toggleAutoSave(model: *Model) void {
    model.auto_save = !model.auto_save;
    persistPrefs(model);
    model.toast = if (model.auto_save) "Auto Save on" else "Auto Save off";
}

fn toggleFindCase(model: *Model) void {
    model.find_case_sensitive = !model.find_case_sensitive;
    persistPrefs(model);
    if (model.find_query.text().len > 0) {
        runFindInDocument(model);
    } else {
        model.toast = if (model.find_case_sensitive) "Find: case sensitive" else "Find: ignore case";
    }
}

fn findNavigate(model: *Model, forward: bool) void {
    const bufs = model.find_bufs orelse {
        runFindInDocument(model);
        return;
    };
    if (bufs.match_count == 0) {
        runFindInDocument(model);
        return;
    }
    if (forward) bufs.next() else bufs.prev();
    updateFindLabel(model);
    model.toast = model.find_active_label;
}

fn showQuickOpen(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace first";
        return;
    }
    model.quick_open_visible = true;
    model.command_palette_open = false;
    filterQuickOpen(model);
}

fn filterQuickOpen(model: *Model) void {
    const ws = model.workspace orelse return;
    const bufs = ensureQuickBuffers(model) catch return;
    bufs.filter(ws, model.quick_query.text());
    model.quick_items = bufs.itemsSlice();
}

fn openQuickItem(model: *Model, item_id: u32) void {
    if (model.quick_bufs) |bufs| {
        for (bufs.itemsSlice()) |item| {
            if (item.id == item_id) {
                model.quick_open_visible = false;
                // Reuse select_file path
                model.selected_file_id = item.file_id;
                model.current_view = .ide;
                model.selected_activity = .explorer;
                if (model.workspace) |ws| {
                    ws.openFileById(modelIo(model), item.file_id) catch {};
                    model.active_tab_id = item.file_id;
                    model.open_tabs = ws.tabsSlice();
                    if (ws.findNode(item.file_id)) |node| {
                        if (!node.is_dir) model.status_language = workspace_store.scannerLanguage(node.path);
                    }
                    syncDocumentFromWorkspace(model);
                }
                model.toast = "Opened";
                return;
            }
        }
    }
    model.toast = "File not found";
}

fn closeActiveTab(model: *Model) void {
    closeTabById(model, model.active_tab_id);
}

fn closeTabById(model: *Model, id: u32) void {
    if (model.document_dirty and model.active_tab_id == id) {
        if (std.mem.startsWith(u8, model.toast, "Unsaved changes")) {
            model.document_dirty = false;
            model.toast = "Discarded unsaved changes";
        } else {
            model.toast = "Unsaved changes — Save, or Close again to discard";
            return;
        }
    }
    if (model.workspace_from_disk) {
        if (model.workspace) |ws| {
            ws.closeTab(id);
            model.open_tabs = ws.tabsSlice();
            if (ws.tab_count > 0) {
                model.active_tab_id = ws.tabs[ws.tab_count - 1].id;
                model.selected_file_id = model.active_tab_id;
                ws.openFileById(modelIo(model), model.active_tab_id) catch {};
                syncDocumentFromWorkspace(model);
            } else {
                model.document.clear();
                model.active_tab_id = 0;
            }
            model.toast = "Tab closed";
            return;
        }
    }
    model.toast = "Tab closed (mock)";
}

fn runGotoLine(model: *Model) void {
    const text = model.goto_line_input.text();
    if (text.len == 0) {
        model.toast = "Enter a line number";
        return;
    }
    var line_no: u32 = 0;
    for (text) |c| {
        if (c < '0' or c > '9') {
            model.toast = "Invalid line number";
            return;
        }
        line_no = line_no * 10 + (c - '0');
        if (line_no > 1_000_000) break;
    }
    if (line_no == 0) {
        model.toast = "Line must be >= 1";
        return;
    }
    var total: u32 = 1;
    for (model.document.text()) |c| {
        if (c == '\n') total += 1;
    }
    const target = @min(line_no, total);
    const label = std.fmt.bufPrint(&model.goto_line_buf, "Line {d}/{d}", .{ target, total }) catch "line";
    model.goto_line_label = label;
    model.toast = model.goto_line_label;
}

fn ensurePrefsLoaded(model: *Model) void {
    if (model.prefs_loaded) return;
    model.prefs.load(modelIo(model));
    model.prefs_loaded = true;
}

fn applyPrefsToModel(model: *Model) void {
    ensurePrefsLoaded(model);
    if (std.mem.eql(u8, model.prefs.themeSlice(), "light")) model.theme_preference = .light;
    if (std.mem.eql(u8, model.prefs.themeSlice(), "high_contrast")) model.theme_preference = .high_contrast;
    if (std.mem.eql(u8, model.prefs.themeSlice(), "dark")) model.theme_preference = .dark;
    model.show_terminal = model.prefs.show_terminal;
    model.show_agent_panel = model.prefs.show_agent;
    model.auto_save = model.prefs.auto_save;
    model.find_case_sensitive = model.prefs.find_case_sensitive;
    if (model.prefs.last_path_len > 0 and model.open_path.text().len == 0) {
        model.open_path.set(model.prefs.lastPathSlice());
    }
    syncRecentFromPrefs(model);
}

/// Called once from main after io is attached.
pub fn ensurePrefsOnBoot(model: *Model) void {
    applyPrefsToModel(model);
    refreshDocStats(model);
    refreshBreadcrumb(model);
}

fn persistPrefs(model: *Model) void {
    ensurePrefsLoaded(model);
    model.prefs.setTheme(switch (model.theme_preference) {
        .dark => "dark",
        .light => "light",
        .high_contrast => "high_contrast",
    });
    model.prefs.show_terminal = model.show_terminal;
    model.prefs.show_agent = model.show_agent_panel;
    model.prefs.auto_save = model.auto_save;
    model.prefs.find_case_sensitive = model.find_case_sensitive;
    model.prefs.save(modelIo(model));
}

fn refreshGitStatus(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.git_summary = "no workspace";
        model.toast = "Open a workspace for git";
        return;
    }
    const bufs = ensureGitBuffers(model) catch {
        model.toast = "Git alloc failed";
        return;
    };
    _ = model.governor.spawn("feature.scm", "git status") catch {};
    bufs.refresh(modelIo(model), model.project_path);
    model.git_entries = bufs.entriesSlice();
    model.git_summary = bufs.summary;
    model.git_branch = bufs.branch();
    if (bufs.branch_len > 0) model.project_branch = bufs.branch();
    model.governor.killFeature("feature.scm");
    model.process_count = model.governor.aliveCount();
    model.toast = bufs.summary;
}

fn pathForFile(id: u32) []const u8 {
    for (file_tree) |node| {
        if (node.id == id) return node.path;
    }
    return "";
}

fn cycleTheme(model: *Model) void {
    model.theme_preference = switch (model.theme_preference) {
        .dark => .light,
        .light => .high_contrast,
        .high_contrast => .dark,
    };
}

fn createTask(model: *Model) void {
    _ = model;
    // Mock: bump status text only — fixed array size for milestone 1.
    // Real task append lands when agent runtime exists.
}

fn applyPerfPlaceholder(model: *Model) void {
    // Labeled mock values for HUD scaffolding — not measured.
    model.perf_app_start_ms = 312;
    model.perf_first_window_ms = 280;
    model.perf_first_paint_ms = 184;
    model.perf_palette_ms = 21;
    model.perf_terminal_ms = 18;
    model.perf_rss_mb = 48;
    model.perf_plugins_loaded = 0;
    model.features_registered = 200;
    model.features_loaded = 8;
    model.process_count = 0;
    model.terminal_process_count = 0;
    model.lsp_process_count = 0;
    model.plugin_process_count = 0;
    model.process_leaked = 0;
    model.status_memory = "Memory: 48 MB (mock)";
    model.status_startup = "Startup: 312 ms (mock)";
    model.status_agent = "Agent: idle";
}

pub fn statusFor(task: AgentTask) []const u8 {
    return switch (task.status) {
        .running => "running",
        .planning => "planning",
        .ready_for_review => "ready for review",
        .failed => "failed",
        .completed => "completed",
    };
}
