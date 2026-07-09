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
const edit_transforms = @import("../workspace/edit_transforms.zig");
const problems_mod = @import("../workspace/problems.zig");
const problem_matchers = @import("../workspace/problem_matchers.zig");
const scanner_mod = @import("../workspace/scanner.zig");
const outline_mod = @import("../workspace/outline.zig");
const go_to_def_mod = @import("../workspace/go_to_def.zig");
const editor_view = @import("../workspace/editor_view.zig");
const terminal_session = @import("../terminal/terminal_session.zig");
const process_governor = @import("../processes/process_governor.zig");
const git_status = @import("../scm/git_status.zig");
const prefs_mod = @import("../core/prefs.zig");
const undo_stack = @import("../workspace/undo_stack.zig");
const disk_sync = @import("../workspace/disk_sync.zig");
const hot_exit_store = @import("../workspace/hot_exit_store.zig");
const task_detector = @import("../workspace/task_detector.zig");
const workspace_replace = @import("../workspace/workspace_replace.zig");

pub const header_natural_height: f32 = 36;
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
pub const max_replace = workspace_replace.max_replacement_len;
pub const max_commit_message = 120;
pub const SearchHit = workspace_search.SearchHit;
pub const GitEntry = git_status.GitEntry;
pub const DocMatch = find_in_doc.DocMatch;
pub const QuickItem = quick_open.QuickItem;
pub const Problem = problems_mod.Problem;
pub const OutlineSymbol = outline_mod.Symbol;
pub const DefHit = go_to_def_mod.DefHit;
pub const PeekLine = editor_view.PeekLine;
pub const WorkspaceTask = task_detector.Task;
pub const ReplacePreview = workspace_replace.FilePreview;

pub const BreadcrumbSeg = struct {
    id: u32 = 0,
    label: []const u8 = "",
    path: []const u8 = "",
};

pub const OutputLine = struct {
    id: u32 = 0,
    text: []const u8 = "",
};

pub const ClosedTab = struct {
    path: []const u8 = "",
    title: []const u8 = "",
};

pub const ViewKind = enum { launch, ide, plugins, settings, perf, features, processes, search, scm, debug, testing, problems };
pub const Activity = enum { explorer, search, scm, agents, terminal, plugins, settings, debug, testing, features, processes, problems, outline };
pub const BottomPanelTab = enum { terminal, output, problems };
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
    dismiss_overlay,
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
    overwrite_file,
    submit_open_path,
    update_terminal_command: canvas.TextInputEvent,
    run_terminal_command,
    stop_terminal_task,
    clear_terminal,
    update_search_query: canvas.TextInputEvent,
    run_search,
    open_search_hit: u32,
    preview_workspace_replace,
    apply_workspace_replace,
    refresh_git,
    open_git_entry: u32,
    select_git_entry: u32,
    stage_git_entry: u32,
    unstage_git_entry: u32,
    restore_git_entry: u32,
    clear_find,
    reopen_last_workspace,
    update_new_file_path: canvas.TextInputEvent,
    create_new_file,
    delete_selected_file,
    rename_selected_file,
    reveal_in_explorer,
    update_explorer_filter: canvas.TextInputEvent,
    update_find_query: canvas.TextInputEvent,
    run_find,
    find_next,
    find_prev,
    update_quick_query: canvas.TextInputEvent,
    run_quick_open,
    open_quick_item: u32,
    close_quick_open,
    save_prefs,
    goto_line,
    close_active_tab,
    save_all,
    close_other_tabs,
    close_all_tabs,
    pin_active_tab,
    toggle_focus_mode,
    toggle_shortcuts_help,
    transform_upper,
    transform_lower,
    transform_sort_lines,
    transform_reverse_lines,
    transform_title,
    collapse_blank_lines,
    copy_all_tab_paths,
    new_untitled,
    toggle_trim_trailing,
    toggle_final_newline,
    delete_last_line,
    join_lines,
    move_line_up,
    move_line_down,
    undo_edit,
    redo_edit,
    revert_file,
    copy_absolute_path,
    next_tab,
    prev_tab,
    remove_blank_lines,
    insert_blank_line,
    copy_filename,
    show_word_count,
    cycle_indent_size,
    convert_tabs_to_spaces,
    convert_spaces_to_tabs,
    transform_sort_unique,
    convert_to_lf,
    convert_to_crlf,
    toggle_find_whole_word,
    duplicate_selected_file,
    toggle_search_case,
    toggle_sidebar,
    insert_timestamp,
    update_replace_text: canvas.TextInputEvent,
    replace_once,
    replace_all,
    copy_active_path,
    refresh_recent,
    toggle_auto_save,
    toggle_find_case,
    duplicate_line,
    terminal_history_older,
    terminal_history_newer,
    refresh_tasks,
    select_task: u32,
    run_selected_task,
    toggle_line_comment,
    indent_document,
    outdent_document,
    reopen_closed_tab,
    scan_problems,
    parse_terminal_diagnostics,
    open_problem: u32,
    preview_git_diff: u32,
    update_commit_message: canvas.TextInputEvent,
    stage_all,
    unstage_all,
    discard_changes,
    commit_changes,
    trim_blank_lines,
    refresh_explorer,
    refresh_disk_sync,
    disk_poll_timer: native_sdk.EffectTimer,
    close_saved_tabs,
    compare_with_saved,
    copy_git_branch,
    clear_recent_projects,
    insert_uuid,
    format_document,
    hard_wrap,
    copy_document,
    go_to_symbol,
    create_folder,
    show_file_size,
    toggle_word_wrap,
    clear_toast,
    toast_timer: native_sdk.EffectTimer,
    dismiss_update_banner,
    check_for_updates,
    minimize_window,
    close_window,
    toggle_notifications_panel,
    update_settings_query: canvas.TextInputEvent,
    open_outline,
    select_outline_symbol: u32,
    go_to_definition,
    open_def_hit: u32,
    select_breadcrumb: u32,
    select_bottom_tab: BottomPanelTab,
    toggle_bottom_panel,
    clear_output,
    open_symbol_palette,
    close_symbol_palette,
    update_symbol_query: canvas.TextInputEvent,
    open_symbol_item: u32,
    terminal_line: native_sdk.EffectLine,
    terminal_exit: native_sdk.EffectExit,
    chrome_changed: native_sdk.WindowChrome,
    set_appearance: native_sdk.Appearance,

    pub const view_unbound = .{
        "chrome_changed",
        "set_appearance",
        "toast_timer",
        "minimize_window",
        "close_window",
        "open_outline",
        "open_symbol_palette",
        "open_def_hit",
        "open_tab",
        "close_tab",
        "open_settings",
        "submit_open_path",
        "delete_selected_file",
        "rename_selected_file",
        "reveal_in_explorer",
        "close_quick_open",
        "goto_line",
        "save_all",
        "close_other_tabs",
        "close_all_tabs",
        "pin_active_tab",
        "transform_upper",
        "transform_lower",
        "transform_sort_lines",
        "transform_reverse_lines",
        "transform_title",
        "collapse_blank_lines",
        "copy_all_tab_paths",
        "new_untitled",
        "delete_last_line",
        "join_lines",
        "move_line_up",
        "move_line_down",
        "undo_edit",
        "redo_edit",
        "copy_absolute_path",
        "next_tab",
        "prev_tab",
        "remove_blank_lines",
        "insert_blank_line",
        "copy_filename",
        "show_word_count",
        "convert_tabs_to_spaces",
        "convert_spaces_to_tabs",
        "transform_sort_unique",
        "convert_to_lf",
        "convert_to_crlf",
        "toggle_find_whole_word",
        "duplicate_selected_file",
        "insert_timestamp",
        "copy_active_path",
        "refresh_recent",
        "duplicate_line",
        "dismiss_overlay",
        "toggle_line_comment",
        "indent_document",
        "outdent_document",
        "reopen_closed_tab",
        "preview_git_diff",
        "discard_changes",
        "trim_blank_lines",
        "refresh_disk_sync",
        "disk_poll_timer",
        "close_saved_tabs",
        "copy_git_branch",
        "clear_recent_projects",
        "insert_uuid",
        "format_document",
        "hard_wrap",
        "copy_document",
        "create_folder",
        "show_file_size",
        "close_command_palette",
        "terminal_line",
        "terminal_exit",
    };
};

pub const app_version = "0.1.0";
pub const toast_timer_key: u64 = 0x746f617374_01;
pub const disk_poll_timer_key: u64 = 0x6469736b_706f6c6c;
pub const terminal_process_effect_key: u64 = 0x7465726d_696e616c;
pub const toast_auto_clear_ms: u64 = 3200;
pub const max_notification_history: usize = 8;
pub const max_notification_text: usize = 96;
pub const max_toast_text: usize = 520;
pub const max_settings_query = 48;

pub const NotificationItem = struct {
    id: u32 = 0,
    text: []const u8 = "",
};

pub const Effects = native_sdk.Effects(Msg);

pub const Model = struct {
    current_view: ViewKind = .launch,
    selected_activity: Activity = .explorer,
    command_palette_open: bool = false,
    command_query: canvas.TextBuffer(max_command_query) = .{},
    agent_prompt: canvas.TextBuffer(max_agent_prompt) = .{},
    show_terminal: bool = false,
    show_agent_panel: bool = false,
    show_find_panel: bool = false,
    editor_focus_line: u32 = 0,
    editor_focus_label: []const u8 = "",
    editor_focus_buf: [32]u8 = undefined,
    peek_lines: []const PeekLine = &.{},
    peek_storage: [editor_view.max_peek_lines]PeekLine = [_]PeekLine{.{}} ** editor_view.max_peek_lines,
    peek_pool: [editor_view.max_peek_bytes]u8 = undefined,
    peek_lens: [editor_view.max_peek_lines]usize = [_]usize{0} ** editor_view.max_peek_lines,
    peek_count: u32 = 0,
    outline_bufs: ?*outline_mod.OutlineBuffers = null,
    outline_symbols: []const OutlineSymbol = &.{},
    outline_status: []const u8 = "idle",
    symbol_palette_open: bool = false,
    symbol_query: canvas.TextBuffer(64) = .{},
    def_bufs: ?*go_to_def_mod.GoToDefBuffers = null,
    def_hits: []const DefHit = &.{},
    def_status: []const u8 = "idle",
    breadcrumb_segs: []const BreadcrumbSeg = &.{},
    breadcrumb_seg_storage: [12]BreadcrumbSeg = [_]BreadcrumbSeg{.{}} ** 12,
    breadcrumb_label_pool: [12][48]u8 = undefined,
    breadcrumb_path_pool: [12][240]u8 = undefined,
    breadcrumb_seg_count: u32 = 0,
    bottom_panel_open: bool = false,
    bottom_panel_tab: BottomPanelTab = .terminal,
    output_lines: []const OutputLine = &.{},
    output_storage: [48]OutputLine = [_]OutputLine{.{}} ** 48,
    output_pool: [48][120]u8 = undefined,
    output_lens: [48]usize = [_]usize{0} ** 48,
    output_count: u32 = 0,
    output_next_id: u32 = 1,
    recent_files: [8][240]u8 = undefined,
    recent_file_lens: [8]usize = [_]usize{0} ** 8,
    recent_file_count: u32 = 0,
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
    mock_label: []const u8 = "mock",
    workspace_from_disk: bool = false,
    workspace_node_count: u32 = 0,
    workspace_file_count: u32 = 0,
    workspace_scan_error: []const u8 = "",
    workspace_files_label: []const u8 = "",
    workspace_files_buf: [48]u8 = undefined,
    workspace: ?*workspace_store.WorkspaceBuffers = null,
    /// Runtime Io from process.Init; tests fall back to std.testing.io.
    io: ?std.Io = null,
    document: canvas.TextBuffer(max_document) = .{},
    document_dirty: bool = false,
    disk_changed: bool = false,
    /// Model-global bounded history, reset when the active document changes.
    undo_history: ?*undo_stack.UndoStack = null,
    disk_checker: disk_sync.Checker = .{},
    disk_poll_interval_ms: u32 = prefs_mod.default_disk_poll_interval_ms,
    disk_poll_armed: bool = false,
    disk_poll_rejected: bool = false,
    open_path: canvas.TextBuffer(max_open_path) = .{},
    terminal_command: canvas.TextBuffer(max_terminal_command) = .{},
    terminal: ?*terminal_session.TerminalBuffers = null,
    search_bufs: ?*workspace_search.SearchBuffers = null,
    git_bufs: ?*git_status.GitBuffers = null,
    task_bufs: ?*task_detector.TaskDetector = null,
    workspace_replace_bufs: ?*workspace_replace.WorkspaceReplace = null,
    search_query: canvas.TextBuffer(max_search_query) = .{},
    search_hits: []const SearchHit = &.{},
    workspace_tasks: []const WorkspaceTask = &.{},
    replace_previews: []const ReplacePreview = &.{},
    selected_task_id: u32 = 0,
    selected_git_entry_id: u32 = 0,
    task_running: bool = false,
    task_status: []const u8 = "No tasks detected",
    replace_status: []const u8 = "Preview changes before applying",
    task_status_buf: [96]u8 = undefined,
    replace_status_buf: [128]u8 = undefined,
    git_entries: []const GitEntry = &.{},
    git_summary: []const u8 = "not loaded",
    git_branch: []const u8 = "unknown",
    new_file_path: canvas.TextBuffer(max_new_file_path) = .{},
    explorer_filter: canvas.TextBuffer(64) = .{},
    explorer_filtered: [workspace_store.max_nodes]FileNode = [_]FileNode{.{}} ** workspace_store.max_nodes,
    explorer_filtered_count: u32 = 0,
    problem_bufs: ?*problems_mod.ProblemBuffers = null,
    matcher_bufs: ?*problem_matchers.MatcherBuffers = null,
    problems: []const Problem = &.{},
    problems_status: []const u8 = "idle",
    git_diff_text: []const u8 = "",
    git_diff_status: []const u8 = "—",
    closed_tabs: [8]ClosedTab = [_]ClosedTab{.{}} ** 8,
    closed_tab_count: u32 = 0,
    closed_path_pool: [8][240]u8 = undefined,
    closed_path_lens: [8]usize = [_]usize{0} ** 8,
    closed_title_pool: [8][64]u8 = undefined,
    closed_title_lens: [8]usize = [_]usize{0} ** 8,
    command_filtered: [64]CommandItem = [_]CommandItem{.{ .id = "", .title = "", .hint = "" }} ** 64,
    command_filtered_count: u32 = 0,
    find_query: canvas.TextBuffer(max_find_query) = .{},
    find_bufs: ?*find_in_doc.FindBuffers = null,
    find_matches: []const DocMatch = &.{},
    find_status: []const u8 = "idle",
    find_active_label: []const u8 = "",
    find_label_buf: [48]u8 = undefined,
    find_case_sensitive: bool = false,
    find_whole_word: bool = false,
    search_case_sensitive: bool = false,
    show_sidebar: bool = true,
    word_wrap: bool = false,
    auto_save: bool = false,
    trim_trailing_ws: bool = false,
    insert_final_newline: bool = true,
    indent_size: u8 = 2,
    focus_mode: bool = false,
    shortcuts_help_visible: bool = false,
    pinned_tab_id: u32 = 0,
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
    git_commit_message: canvas.TextBuffer(max_commit_message) = .{},
    doc_stats: []const u8 = "0 lines · 0 words · 0 bytes · LF · ASCII",
    doc_stats_buf: [96]u8 = undefined,
    path_toast: []const u8 = "",
    path_toast_buf: [520]u8 = undefined,
    action_toast_buf: [48]u8 = undefined,
    recent_dynamic: [prefs_mod.max_recent]RecentProject = [_]RecentProject{.{ .name = "", .path = "", .branch = "" }} ** prefs_mod.max_recent,
    recent_name_pool: [prefs_mod.max_recent][64]u8 = undefined,
    recent_path_pool: [prefs_mod.max_recent][prefs_mod.max_path]u8 = undefined,
    recent_path_lens: [prefs_mod.max_recent]usize = [_]usize{0} ** prefs_mod.max_recent,
    recent_name_lens: [prefs_mod.max_recent]usize = [_]usize{0} ** prefs_mod.max_recent,
    untitled_seq: u32 = 1,
    prefs: prefs_mod.Prefs = .{},
    prefs_loaded: bool = false,
    terminal_effect_key: u64 = terminal_process_effect_key,
    terminal_async: bool = false,
    terminal_stopping: bool = false,
    terminal_process_id: u32 = 0,
    governor: process_governor.Governor = .{},
    toast: []const u8 = "",
    toast_buf: [max_toast_text]u8 = undefined,
    toast_len: usize = 0,
    toast_visible: bool = false,
    toast_sticky: bool = false,
    toast_seq: u32 = 0,
    notification_history: [max_notification_history]NotificationItem = [_]NotificationItem{.{}} ** max_notification_history,
    notification_text_pool: [max_notification_history][max_notification_text]u8 = undefined,
    notification_text_lens: [max_notification_history]usize = [_]usize{0} ** max_notification_history,
    notification_count: u32 = 0,
    notification_next_id: u32 = 1,
    notifications: []const NotificationItem = &.{},
    notifications_panel_open: bool = false,
    update_banner: []const u8 = "",
    update_banner_buf: [120]u8 = undefined,
    update_banner_visible: bool = false,
    update_checked: bool = false,
    settings_query: canvas.TextBuffer(max_settings_query) = .{},
    app_version_label: []const u8 = "Velocity " ++ app_version,
    editor_mode_label: []const u8 = "read-only mock",
    theme_preference: theme.ThemePreference = .dark,
    appearance: native_sdk.Appearance = .{},
    chrome_leading: f32 = 0,
    chrome_trailing: f32 = 0,
    header_height: f32 = header_natural_height,
    window_fullscreen: bool = false,
    chrome_seen_insets: bool = false,
    active_tab_id: u32 = 1,
    selected_file_id: u32 = 2,
    project_name: []const u8 = "acme-dashboard",
    project_branch: []const u8 = "main",
    project_path: []const u8 = "~/src/acme-dashboard",
    status_language: []const u8 = "TypeScript",
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
    activity_settings: Activity = .settings,
    activity_problems: Activity = .problems,
    activity_outline: Activity = .outline,
    bottom_tab_terminal: BottomPanelTab = .terminal,
    bottom_tab_output: BottomPanelTab = .output,
    bottom_tab_problems: BottomPanelTab = .problems,
    project_acme: []const u8 = "acme-dashboard",

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
        "editor_focus_label",
        "runtime_mode_label",
        "features_registered",
        "features_loaded",
        "process_leaked",
        "lsp_process_count",
        "plugin_process_count",
        "git_branch",
        "editor_mode_label",
        "project_path",
        "status_agent",
        "perf_app_start_ms",
        "perf_first_window_ms",
        "perf_first_paint_ms",
        "perf_palette_ms",
        "perf_terminal_ms",
        "perf_rss_mb",
        "perf_plugins_loaded",
        "isIde",
        "isPerf",
        "activeTabTitle",
        "activeTabPath",
        "features_enabled",
        "showPlaceholderPanel",
        "workspace",
        "workspace_from_disk",
        "workspace_scan_error",
        "workspace_node_count",
        "workspace_file_count",
        "workspace_files_label",
        "workspace_files_buf",
        "status_memory",
        "status_startup",
        "io",
        "document",
        "document_dirty",
        "disk_changed",
        "undo_history",
        "disk_checker",
        "disk_poll_interval_ms",
        "disk_poll_armed",
        "disk_poll_rejected",
        "open_path",
        "terminal_command",
        "terminal",
        "search_bufs",
        "git_bufs",
        "task_bufs",
        "workspace_replace_bufs",
        "search_query",
        "task_running",
        "task_status",
        "replace_status",
        "task_status_buf",
        "replace_status_buf",
        "new_file_path",
        "explorer_filter",
        "explorer_filtered",
        "explorer_filtered_count",
        "problem_bufs",
        "matcher_bufs",
        "problems_status",
        "git_diff_text",
        "closed_tabs",
        "closed_tab_count",
        "closed_path_pool",
        "closed_path_lens",
        "closed_title_pool",
        "closed_title_lens",
        "reopenClosedLabel",
        "command_filtered",
        "command_filtered_count",
        "find_query",
        "find_bufs",
        "find_label_buf",
        "find_status",
        "find_matches",
        "find_case_sensitive",
        "find_whole_word",
        "search_case_sensitive",
        "show_sidebar",
        "word_wrap",
        "auto_save",
        "trim_trailing_ws",
        "insert_final_newline",
        "indent_size",
        "focus_mode",
        "pinned_tab_id",
        "show_terminal",
        "show_agent_panel",
        "show_find_panel",
        "breadcrumb",
        "breadcrumb_buf",
        "quick_query",
        "quick_bufs",
        "goto_line_input",
        "goto_line_buf",
        "goto_line_label",
        "replace_text",
        "git_commit_message",
        "doc_stats",
        "doc_stats_buf",
        "path_toast",
        "path_toast_buf",
        "action_toast_buf",
        "pathToast",
        "toast_buf",
        "toast_len",
        "toast_visible",
        "toast_sticky",
        "toast_seq",
        "notification_history",
        "notification_text_pool",
        "notification_text_lens",
        "notification_count",
        "notification_next_id",
        "notifications_panel_open",
        "update_banner",
        "update_banner_buf",
        "update_banner_visible",
        "update_checked",
        "settings_query",
        "window_fullscreen",
        "chrome_seen_insets",
        "recent_dynamic",
        "recent_name_pool",
        "recent_path_pool",
        "recent_path_lens",
        "recent_name_lens",
        "untitled_seq",
        "prefs",
        "prefs_loaded",
        "terminal_effect_key",
        "terminal_async",
        "terminal_stopping",
        "terminal_process_id",
        "governor",
        "editorBody",
        "editor_focus_line",
        "editor_focus_buf",
        "peek_storage",
        "peek_pool",
        "peek_lens",
        "peek_count",
        "outline_bufs",
        "outline_status",
        "symbol_query",
        "def_bufs",
        "def_status",
        "def_hits",
        "breadcrumb_seg_storage",
        "breadcrumb_label_pool",
        "breadcrumb_path_pool",
        "breadcrumb_seg_count",
        "bottom_panel_open",
        "bottom_panel_tab",
        "output_storage",
        "output_pool",
        "output_lens",
        "output_next_id",
        "recent_files",
        "recent_file_lens",
        "recent_file_count",
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
        return model.show_agent_panel;
    }

    pub fn terminalSelected(model: *const Model) bool {
        return model.bottom_panel_open and model.bottom_panel_tab == .terminal;
    }

    pub fn settingsSelected(model: *const Model) bool {
        return model.selected_activity == .settings;
    }

    pub fn problemsSelected(model: *const Model) bool {
        return model.selected_activity == .problems;
    }

    pub fn outlineSelected(model: *const Model) bool {
        return model.selected_activity == .outline and model.showLeftPanel();
    }

    pub fn showSidebarOutline(model: *const Model) bool {
        return model.showLeftPanel() and model.selected_activity == .outline;
    }

    pub fn showBottomPanel(model: *const Model) bool {
        return model.bottom_panel_open and !model.focus_mode and model.showIdeChrome();
    }

    pub fn showBottomTerminal(model: *const Model) bool {
        return model.showBottomPanel() and model.bottom_panel_tab == .terminal;
    }

    pub fn showBottomOutput(model: *const Model) bool {
        return model.showBottomPanel() and model.bottom_panel_tab == .output;
    }

    pub fn showBottomProblems(model: *const Model) bool {
        return model.showBottomPanel() and model.bottom_panel_tab == .problems;
    }

    pub fn hasPeek(model: *const Model) bool {
        return model.peek_count > 0 and model.editor_focus_line > 0;
    }

    pub fn editorFocusLabel(model: *const Model) []const u8 {
        return model.editor_focus_label;
    }

    pub fn outlineStatus(model: *const Model) []const u8 {
        return model.outline_status;
    }

    pub fn symbolQueryText(model: *const Model) []const u8 {
        return model.symbol_query.text();
    }

    pub fn isFeatures(model: *const Model) bool {
        return model.current_view == .features;
    }

    pub fn isProcesses(model: *const Model) bool {
        return model.current_view == .processes;
    }

    pub fn isSearch(model: *const Model) bool {
        return model.selected_activity == .search and model.showLeftPanel();
    }

    pub fn isScm(model: *const Model) bool {
        return model.selected_activity == .scm and model.showLeftPanel();
    }

    pub fn isDebug(model: *const Model) bool {
        return model.current_view == .debug;
    }

    pub fn isTesting(model: *const Model) bool {
        return model.current_view == .testing;
    }

    pub fn showSidebarExplorer(model: *const Model) bool {
        return model.showLeftPanel() and model.selected_activity == .explorer;
    }

    pub fn showFindPanel(model: *const Model) bool {
        return model.show_find_panel and model.showIdeChrome();
    }

    pub fn showPlaceholderPanel(model: *const Model) bool {
        return model.current_view == .debug or model.current_view == .testing or model.current_view == .features or model.current_view == .processes;
    }

    pub fn gitDiffText(model: *const Model) []const u8 {
        return model.git_diff_text;
    }

    pub fn problemsStatus(model: *const Model) []const u8 {
        return model.problems_status;
    }

    pub fn reopenClosedLabel(model: *const Model) []const u8 {
        if (model.closed_tab_count == 0) return "Reopen Closed";
        return "Reopen Closed";
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

    pub fn terminalCommandText(model: *const Model) []const u8 {
        return model.terminal_command.text();
    }

    pub fn searchQueryText(model: *const Model) []const u8 {
        return model.search_query.text();
    }

    pub fn newFilePathText(model: *const Model) []const u8 {
        return model.new_file_path.text();
    }

    pub fn explorerFilterText(model: *const Model) []const u8 {
        return model.explorer_filter.text();
    }

    pub fn findQueryText(model: *const Model) []const u8 {
        return model.find_query.text();
    }

    pub fn replaceText(model: *const Model) []const u8 {
        return model.replace_text.text();
    }

    pub fn taskStatus(model: *const Model) []const u8 {
        return model.task_status;
    }

    pub fn replaceStatus(model: *const Model) []const u8 {
        return model.replace_status;
    }

    pub fn commitMessageText(model: *const Model) []const u8 {
        return model.git_commit_message.text();
    }

    pub fn documentStats(model: *const Model) []const u8 {
        return model.doc_stats;
    }

    pub fn pathToast(model: *const Model) []const u8 {
        return model.path_toast;
    }

    pub fn hasToast(model: *const Model) bool {
        return model.toast_visible and model.toast.len > 0;
    }

    pub fn hasUpdateBanner(model: *const Model) bool {
        return model.update_banner_visible and model.update_banner.len > 0;
    }

    pub fn updateBannerText(model: *const Model) []const u8 {
        return model.update_banner;
    }

    pub fn settingsQueryText(model: *const Model) []const u8 {
        return model.settings_query.text();
    }

    pub fn showSettingsAppearance(model: *const Model) bool {
        return settingsSectionVisible(model, "appearance theme dark light contrast");
    }

    pub fn showSettingsEditor(model: *const Model) bool {
        return settingsSectionVisible(model, "editor find indent trim newline wrap format");
    }

    pub fn showSettingsWorkspace(model: *const Model) bool {
        return settingsSectionVisible(model, "workspace sidebar terminal agent panel auto save");
    }

    pub fn showSettingsAccessibility(model: *const Model) bool {
        return settingsSectionVisible(model, "accessibility high contrast reduce motion keyboard shortcuts notifications");
    }

    pub fn showSettingsFeatures(model: *const Model) bool {
        return settingsSectionVisible(model, "features process governor performance matrix");
    }

    pub fn showSettingsAbout(model: *const Model) bool {
        return settingsSectionVisible(model, "about version update telemetry notifications");
    }

    pub fn showSettingsNoResults(model: *const Model) bool {
        return !model.showSettingsAppearance() and
            !model.showSettingsEditor() and
            !model.showSettingsWorkspace() and
            !model.showSettingsAccessibility() and
            !model.showSettingsFeatures() and
            !model.showSettingsAbout();
    }

    pub fn systemHighContrastLabel(model: *const Model) []const u8 {
        return if (model.appearance.high_contrast) "System high contrast: enabled" else "System high contrast: disabled";
    }

    pub fn systemReduceMotionLabel(model: *const Model) []const u8 {
        return if (model.appearance.reduce_motion) "System reduce motion: enabled" else "System reduce motion: disabled";
    }

    pub fn notificationsOpen(model: *const Model) bool {
        return model.notifications_panel_open;
    }

    pub fn windowStatusLabel(model: *const Model) []const u8 {
        return if (model.window_fullscreen) "Fullscreen" else "Windowed";
    }

    pub fn autoSaveLabel(model: *const Model) []const u8 {
        return if (model.auto_save) "Automatic file saving: enabled" else "Automatic file saving: disabled";
    }

    pub fn trimTrailingLabel(model: *const Model) []const u8 {
        return if (model.trim_trailing_ws) "Trim trailing whitespace: enabled" else "Trim trailing whitespace: disabled";
    }

    pub fn finalNewlineLabel(model: *const Model) []const u8 {
        return if (model.insert_final_newline) "Insert final newline: enabled" else "Insert final newline: disabled";
    }

    pub fn indentSizeLabel(model: *const Model) []const u8 {
        return if (model.indent_size == 4) "Editor indentation: 4 spaces" else "Editor indentation: 2 spaces";
    }

    pub fn focusModeLabel(model: *const Model) []const u8 {
        return if (model.focus_mode) "Focus mode: enabled" else "Focus mode: disabled";
    }

    pub fn showAgentChrome(model: *const Model) bool {
        return model.show_agent_panel and !model.focus_mode and model.showIdeChrome();
    }

    pub fn findCaseLabel(model: *const Model) []const u8 {
        return if (model.find_case_sensitive) "Case-sensitive find: enabled" else "Case-sensitive find: disabled";
    }

    pub fn searchCaseLabel(model: *const Model) []const u8 {
        return if (model.search_case_sensitive) "Search Aa: on" else "Search Aa: off";
    }

    pub fn sidebarLabel(model: *const Model) []const u8 {
        return if (model.show_sidebar) "Workspace sidebar: shown" else "Workspace sidebar: hidden";
    }

    pub fn wordWrapLabel(model: *const Model) []const u8 {
        return if (model.word_wrap) "Editor word wrap: enabled" else "Editor word wrap: disabled";
    }

    pub fn terminalPanelLabel(model: *const Model) []const u8 {
        return if (model.bottom_panel_open and model.bottom_panel_tab == .terminal) "Integrated terminal panel: shown" else "Integrated terminal panel: hidden";
    }

    pub fn agentPanelLabel(model: *const Model) []const u8 {
        return if (model.show_agent_panel) "AI agent panel: shown" else "AI agent panel: hidden";
    }

    pub fn quickQueryText(model: *const Model) []const u8 {
        return model.quick_query.text();
    }

    pub fn searchStatus(model: *const Model) []const u8 {
        if (model.search_bufs) |s| return s.status;
        return "idle";
    }

    pub fn dirtyLabel(model: *const Model) []const u8 {
        return if (model.document_dirty) "dirty" else "clean";
    }

    pub fn showDiskConflict(model: *const Model) bool {
        return model.disk_changed and model.showIdeChrome();
    }

    pub fn terminalStatus(model: *const Model) []const u8 {
        if (model.terminal) |t| return t.status;
        return "idle";
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
        if (!model.show_sidebar or model.focus_mode) return false;
        if (model.current_view != .ide and model.current_view != .perf) return false;
        return switch (model.selected_activity) {
            .explorer, .search, .scm, .outline => true,
            else => false,
        };
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
    workspace_store.decorateFileNode(.{ .id = 1, .name = "src", .path = "src", .depth = 0, .is_dir = true }),
    workspace_store.decorateFileNode(.{ .id = 2, .name = "app.tsx", .path = "src/app.tsx", .depth = 1, .is_dir = false }),
    workspace_store.decorateFileNode(.{ .id = 3, .name = "components", .path = "src/components", .depth = 1, .is_dir = true }),
    workspace_store.decorateFileNode(.{ .id = 4, .name = "Chart.tsx", .path = "src/components/Chart.tsx", .depth = 2, .is_dir = false }),
    workspace_store.decorateFileNode(.{ .id = 5, .name = "server", .path = "src/server", .depth = 1, .is_dir = true }),
    workspace_store.decorateFileNode(.{ .id = 6, .name = "auth.ts", .path = "src/server/auth.ts", .depth = 2, .is_dir = false }),
    workspace_store.decorateFileNode(.{ .id = 11, .name = "lib", .path = "src/lib", .depth = 1, .is_dir = true }),
    workspace_store.decorateFileNode(.{ .id = 12, .name = "db.ts", .path = "src/lib/db.ts", .depth = 2, .is_dir = false }),
    workspace_store.decorateFileNode(.{ .id = 7, .name = "package.json", .path = "package.json", .depth = 0, .is_dir = false }),
    workspace_store.decorateFileNode(.{ .id = 8, .name = "README.md", .path = "README.md", .depth = 0, .is_dir = false }),
    workspace_store.decorateFileNode(.{ .id = 9, .name = "tests", .path = "tests", .depth = 0, .is_dir = true }),
    workspace_store.decorateFileNode(.{ .id = 10, .name = "app.test.ts", .path = "tests/app.test.ts", .depth = 1, .is_dir = false }),
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
    .{ .id = "overwrite_file", .title = "Overwrite File Changed on Disk", .hint = "" },
    .{ .id = "save_all", .title = "Save All Dirty Tabs", .hint = "Cmd+Shift+S" },
    .{ .id = "create_new_file", .title = "New File", .hint = "" },
    .{ .id = "delete_selected_file", .title = "Delete Selected File", .hint = "" },
    .{ .id = "rename_selected_file", .title = "Rename Selected File", .hint = "" },
    .{ .id = "reveal_in_explorer", .title = "Reveal Active File in Explorer", .hint = "" },
    .{ .id = "quick_open", .title = "Quick Open File", .hint = "Cmd+P" },
    .{ .id = "find_in_file", .title = "Find in File", .hint = "Cmd+F" },
    .{ .id = "replace_once", .title = "Replace Once", .hint = "" },
    .{ .id = "replace_all", .title = "Replace All", .hint = "" },
    .{ .id = "copy_active_path", .title = "Copy Active Path", .hint = "" },
    .{ .id = "toggle_auto_save", .title = "Toggle Auto Save", .hint = "" },
    .{ .id = "toggle_find_case", .title = "Toggle Find Case Sensitivity", .hint = "" },
    .{ .id = "goto_line", .title = "Go to Line", .hint = "Cmd+G" },
    .{ .id = "close_active_tab", .title = "Close Active Tab", .hint = "Cmd+W" },
    .{ .id = "close_other_tabs", .title = "Close Other Tabs", .hint = "" },
    .{ .id = "close_all_tabs", .title = "Close All Tabs", .hint = "" },
    .{ .id = "pin_active_tab", .title = "Pin / Unpin Active Tab", .hint = "" },
    .{ .id = "toggle_focus_mode", .title = "Toggle Focus Mode", .hint = "" },
    .{ .id = "toggle_shortcuts_help", .title = "Keyboard Shortcuts Help", .hint = "Cmd+Shift+/" },
    .{ .id = "transform_upper", .title = "Transform: Upper Case", .hint = "" },
    .{ .id = "transform_lower", .title = "Transform: Lower Case", .hint = "" },
    .{ .id = "transform_title", .title = "Transform: Title Case", .hint = "" },
    .{ .id = "transform_sort_lines", .title = "Transform: Sort Lines", .hint = "" },
    .{ .id = "transform_reverse_lines", .title = "Transform: Reverse Lines", .hint = "" },
    .{ .id = "collapse_blank_lines", .title = "Collapse Blank Lines", .hint = "" },
    .{ .id = "copy_all_tab_paths", .title = "Copy All Open Tab Paths", .hint = "" },
    .{ .id = "new_untitled", .title = "New Untitled File", .hint = "Cmd+N" },
    .{ .id = "delete_last_line", .title = "Delete Last Line", .hint = "Cmd+Shift+K" },
    .{ .id = "join_lines", .title = "Join Lines", .hint = "" },
    .{ .id = "move_line_up", .title = "Move Last Line Up", .hint = "Alt+Up" },
    .{ .id = "move_line_down", .title = "Move Last Line Down", .hint = "Alt+Down" },
    .{ .id = "undo_edit", .title = "Undo Last Edit", .hint = "Cmd+Z" },
    .{ .id = "redo_edit", .title = "Redo Last Edit", .hint = "Cmd+Shift+Z" },
    .{ .id = "revert_file", .title = "Revert File from Disk", .hint = "" },
    .{ .id = "copy_absolute_path", .title = "Copy Absolute Path", .hint = "" },
    .{ .id = "next_tab", .title = "Next Tab", .hint = "Ctrl+Tab" },
    .{ .id = "prev_tab", .title = "Previous Tab", .hint = "Ctrl+Shift+Tab" },
    .{ .id = "remove_blank_lines", .title = "Remove Blank Lines", .hint = "" },
    .{ .id = "insert_blank_line", .title = "Insert Blank Line at End", .hint = "" },
    .{ .id = "copy_filename", .title = "Copy File Name", .hint = "" },
    .{ .id = "show_word_count", .title = "Show Word Count", .hint = "" },
    .{ .id = "cycle_indent_size", .title = "Cycle Indent Size (2/4)", .hint = "" },
    .{ .id = "convert_tabs_to_spaces", .title = "Convert Tabs to Spaces", .hint = "" },
    .{ .id = "convert_spaces_to_tabs", .title = "Convert Spaces to Tabs", .hint = "" },
    .{ .id = "transform_sort_unique", .title = "Transform: Sort Unique Lines", .hint = "" },
    .{ .id = "convert_to_lf", .title = "Convert Line Endings to LF", .hint = "" },
    .{ .id = "convert_to_crlf", .title = "Convert Line Endings to CRLF", .hint = "" },
    .{ .id = "toggle_find_whole_word", .title = "Toggle Find Whole Word", .hint = "" },
    .{ .id = "duplicate_selected_file", .title = "Duplicate Selected File", .hint = "" },
    .{ .id = "toggle_search_case", .title = "Toggle Search Case Sensitivity", .hint = "" },
    .{ .id = "toggle_sidebar", .title = "Toggle Sidebar", .hint = "Cmd+B" },
    .{ .id = "insert_timestamp", .title = "Insert Timestamp", .hint = "" },
    .{ .id = "toggle_trim_trailing", .title = "Toggle Trim Trailing Whitespace", .hint = "" },
    .{ .id = "toggle_final_newline", .title = "Toggle Insert Final Newline", .hint = "" },
    .{ .id = "toggle_terminal", .title = "Toggle Terminal", .hint = "Ctrl+`" },
    .{ .id = "run_terminal", .title = "Run Terminal Command", .hint = "" },
    .{ .id = "stop_terminal_task", .title = "Stop Terminal/Task", .hint = "" },
    .{ .id = "run_selected_task", .title = "Run Selected Workspace Task", .hint = "Cmd+Shift+B" },
    .{ .id = "refresh_tasks", .title = "Refresh Workspace Tasks", .hint = "" },
    .{ .id = "run_search", .title = "Search Workspace", .hint = "Cmd+Shift+F" },
    .{ .id = "preview_workspace_replace", .title = "Preview Workspace Replace", .hint = "" },
    .{ .id = "apply_workspace_replace", .title = "Apply Workspace Replace", .hint = "" },
    .{ .id = "refresh_git", .title = "Refresh Git Status", .hint = "" },
    .{ .id = "stage_git_entry", .title = "Git: Stage Selected File", .hint = "" },
    .{ .id = "unstage_git_entry", .title = "Git: Unstage Selected File", .hint = "" },
    .{ .id = "restore_git_entry", .title = "Git: Restore Selected File", .hint = "" },
    .{ .id = "stage_all", .title = "Git: Stage All", .hint = "" },
    .{ .id = "unstage_all", .title = "Git: Unstage All", .hint = "" },
    .{ .id = "discard_changes", .title = "Git: Discard Working Tree", .hint = "" },
    .{ .id = "commit_changes", .title = "Git: Commit", .hint = "" },
    .{ .id = "trim_blank_lines", .title = "Trim Leading/Trailing Blank Lines", .hint = "" },
    .{ .id = "refresh_explorer", .title = "Refresh Explorer", .hint = "" },
    .{ .id = "refresh_disk_sync", .title = "Refresh Files from Disk", .hint = "" },
    .{ .id = "close_saved_tabs", .title = "Close Saved Tabs", .hint = "" },
    .{ .id = "compare_with_saved", .title = "Compare with Saved", .hint = "" },
    .{ .id = "copy_git_branch", .title = "Copy Git Branch", .hint = "" },
    .{ .id = "clear_recent_projects", .title = "Clear Recent Projects", .hint = "" },
    .{ .id = "insert_uuid", .title = "Insert UUID", .hint = "" },
    .{ .id = "format_document", .title = "Format Document", .hint = "Shift+Alt+F" },
    .{ .id = "hard_wrap", .title = "Hard Wrap at 80", .hint = "" },
    .{ .id = "copy_document", .title = "Copy Document", .hint = "" },
    .{ .id = "go_to_symbol", .title = "Go to Symbol in File", .hint = "Cmd+Shift+O" },
    .{ .id = "go_to_definition", .title = "Go to Definition", .hint = "Cmd+Shift+D" },
    .{ .id = "open_outline", .title = "Open Outline", .hint = "" },
    .{ .id = "toggle_bottom_panel", .title = "Toggle Bottom Panel", .hint = "Cmd+J" },
    .{ .id = "clear_output", .title = "Clear Output", .hint = "" },
    .{ .id = "create_folder", .title = "New Folder", .hint = "" },
    .{ .id = "show_file_size", .title = "Show File Size", .hint = "" },
    .{ .id = "toggle_word_wrap", .title = "Toggle Word Wrap", .hint = "Alt+Z" },
    .{ .id = "check_for_updates", .title = "Check for Updates", .hint = "" },
    .{ .id = "toggle_notifications_panel", .title = "Toggle Notifications", .hint = "" },
    .{ .id = "minimize_window", .title = "Minimize Window", .hint = "" },
    .{ .id = "close_window", .title = "Close Window", .hint = "" },
    .{ .id = "reopen_last_workspace", .title = "Reopen Last Workspace", .hint = "" },
    .{ .id = "clear_find", .title = "Clear Find", .hint = "" },
    .{ .id = "duplicate_line", .title = "Duplicate Last Line", .hint = "" },
    .{ .id = "toggle_line_comment", .title = "Toggle Line Comment", .hint = "Cmd+/" },
    .{ .id = "indent_document", .title = "Indent Document", .hint = "Cmd+]" },
    .{ .id = "outdent_document", .title = "Outdent Document", .hint = "Cmd+[" },
    .{ .id = "reopen_closed_tab", .title = "Reopen Closed Tab", .hint = "Cmd+Shift+T" },
    .{ .id = "scan_problems", .title = "Scan TODO/FIXME Problems", .hint = "" },
    .{ .id = "parse_terminal_diagnostics", .title = "Parse Terminal Diagnostics", .hint = "" },
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
    normalizeToastState(model);
}

fn messageChangesWorkspace(msg: Msg) bool {
    return switch (msg) {
        .open_project, .submit_open_path, .reopen_last_workspace, .go_launch, .close_window => true,
        .run_command => |id| std.mem.eql(u8, id, "open_folder") or
            std.mem.eql(u8, id, "reopen_last_workspace") or
            std.mem.eql(u8, id, "go_launch") or
            std.mem.eql(u8, id, "close_window"),
        else => false,
    };
}

fn messageClosesWindow(msg: Msg) bool {
    return switch (msg) {
        .close_window => true,
        .run_command => |id| std.mem.eql(u8, id, "close_window"),
        else => false,
    };
}

fn clearActiveCommand(model: *Model, status: process_governor.ProcessStatus, exit_code: i32) void {
    model.governor.closeEffect(model.terminal_effect_key, status, exit_code);
    model.process_count = model.governor.aliveCount();
    model.terminal_process_count = 0;
    model.terminal_process_id = 0;
    model.terminal_async = false;
    model.terminal_stopping = false;
    if (model.terminal) |term| {
        term.running = false;
        term.last_exit = exit_code;
        term.status = @tagName(status);
    }
    if (model.task_running) {
        model.task_running = false;
        model.task_status = switch (status) {
            .cancelled, .killed => "Task cancelled",
            .rejected => "Task rejected",
            .spawn_failed => "Task spawn failed",
            .signaled => "Task terminated by signal",
            .exited => std.fmt.bufPrint(
                &model.task_status_buf,
                "Task exited with code {d}",
                .{exit_code},
            ) catch "Task exited",
            .running => "Task running",
        };
    }
}

fn cancelOwnedEffects(model: *Model, fx: *Effects) void {
    fx.cancelTimer(disk_poll_timer_key);
    model.disk_poll_armed = false;
    model.disk_poll_rejected = false;
    if (model.terminal_async) {
        fx.cancel(model.terminal_effect_key);
        clearActiveCommand(model, .cancelled, native_sdk.effect_error_exit_code);
    }
    model.governor.killAll();
    model.process_count = 0;
    model.terminal_process_count = 0;
    model.terminal_process_id = 0;
    model.terminal_async = false;
    model.terminal_stopping = false;
    model.task_running = false;
    if (model.terminal) |term| term.running = false;
}

fn reconcileDiskPoll(model: *Model, fx: *Effects) void {
    if (!model.workspace_from_disk) {
        if (model.disk_poll_armed) fx.cancelTimer(disk_poll_timer_key);
        model.disk_poll_armed = false;
        return;
    }
    if (model.disk_poll_armed or model.disk_poll_rejected) return;
    model.disk_poll_armed = true;
    fx.startTimer(.{
        .key = disk_poll_timer_key,
        .interval_ms = model.disk_poll_interval_ms,
        .mode = .repeating,
        .on_fire = Effects.timerMsg(.disk_poll_timer),
    });
}

/// Runtime update with Native SDK effects (async terminal spawn).
pub fn updateFx(model: *Model, msg: Msg, fx: *Effects) void {
    var prev_buf: [max_toast_text]u8 = undefined;
    const prev_n = @min(model.toast.len, prev_buf.len);
    if (prev_n > 0) @memcpy(prev_buf[0..prev_n], model.toast[0..prev_n]);
    const prev_toast = prev_buf[0..prev_n];

    const changes_workspace = messageChangesWorkspace(msg);
    if (changes_workspace) cancelOwnedEffects(model, fx);
    updateInner(model, msg, fx);
    normalizeToastState(model);

    if (!std.mem.eql(u8, model.toast, prev_toast)) {
        armToastClearTimer(model, fx);
    }
    handleWindowActions(model, msg, fx);
    if (!messageClosesWindow(msg) and model.current_view != .launch) {
        reconcileDiskPoll(model, fx);
    }
}

fn settingsSectionVisible(model: *const Model, keywords: []const u8) bool {
    const q = model.settings_query.text();
    if (q.len == 0) return true;
    return std.ascii.indexOfIgnoreCase(keywords, q) != null;
}

fn isStickyToast(text: []const u8) bool {
    if (text.len == 0) return false;
    if (std.mem.indexOf(u8, text, "Confirm again") != null) return true;
    if (std.mem.indexOf(u8, text, "again to confirm") != null) return true;
    if (std.mem.indexOf(u8, text, "Close again") != null) return true;
    if (std.mem.startsWith(u8, text, "Delete ")) return true;
    if (std.mem.startsWith(u8, text, "Close all")) return true;
    if (std.mem.startsWith(u8, text, "Close other tabs")) return true;
    if (std.mem.startsWith(u8, text, "Unsaved")) return true;
    if (std.mem.startsWith(u8, text, "Discard")) return true;
    if (std.mem.startsWith(u8, text, "Apply workspace replace")) return true;
    if (std.mem.startsWith(u8, text, "Restore ")) return true;
    if (std.mem.startsWith(u8, text, "File changed on disk")) return true;
    if (std.mem.startsWith(u8, text, "Overwrite changed file")) return true;
    if (std.mem.startsWith(u8, text, "Clear recent")) return true;
    return false;
}

fn normalizeToastState(model: *Model) void {
    const text = model.toast;
    if (text.len == 0) {
        model.toast_len = 0;
        model.toast = "";
        model.toast_visible = false;
        model.toast_sticky = false;
        return;
    }
    // Already owned by toast_buf with identical content — refresh flags only.
    if (model.toast_len == text.len and std.mem.eql(u8, model.toast_buf[0..model.toast_len], text)) {
        model.toast = model.toast_buf[0..model.toast_len];
        model.toast_visible = true;
        model.toast_sticky = isStickyToast(model.toast);
        return;
    }
    const n = @min(text.len, model.toast_buf.len);
    @memcpy(model.toast_buf[0..n], text[0..n]);
    model.toast_len = n;
    model.toast = model.toast_buf[0..n];
    model.toast_visible = true;
    model.toast_sticky = isStickyToast(model.toast);
    model.toast_seq +%= 1;
    pushNotificationHistory(model, model.toast);
}

fn pushNotificationHistory(model: *Model, text: []const u8) void {
    if (text.len == 0) return;
    // Shift older entries down; newest at index 0.
    var i: usize = max_notification_history;
    while (i > 1) : (i -= 1) {
        const dst = i - 1;
        const src = i - 2;
        if (src >= model.notification_count) continue;
        const len = model.notification_text_lens[src];
        @memcpy(model.notification_text_pool[dst][0..len], model.notification_text_pool[src][0..len]);
        model.notification_text_lens[dst] = len;
        model.notification_history[dst] = .{
            .id = model.notification_history[src].id,
            .text = model.notification_text_pool[dst][0..len],
        };
    }
    const n = @min(text.len, max_notification_text);
    @memcpy(model.notification_text_pool[0][0..n], text[0..n]);
    model.notification_text_lens[0] = n;
    model.notification_history[0] = .{
        .id = model.notification_next_id,
        .text = model.notification_text_pool[0][0..n],
    };
    model.notification_next_id +%= 1;
    if (model.notification_count < max_notification_history) model.notification_count += 1;
    model.notifications = model.notification_history[0..model.notification_count];
}

fn armToastClearTimer(model: *Model, fx: *Effects) void {
    fx.cancelTimer(toast_timer_key);
    if (!model.toast_visible or model.toast_sticky or model.toast.len == 0) return;
    fx.startTimer(.{
        .key = toast_timer_key,
        .interval_ms = toast_auto_clear_ms,
        .mode = .one_shot,
        .on_fire = Effects.timerMsg(.toast_timer),
    });
}

fn handleWindowActions(model: *Model, msg: Msg, fx: *Effects) void {
    _ = model;
    switch (msg) {
        .minimize_window => fx.minimizeWindow("main"),
        .close_window => fx.closeWindow("main"),
        .run_command => |id| {
            if (std.mem.eql(u8, id, "minimize_window")) fx.minimizeWindow("main");
            if (std.mem.eql(u8, id, "close_window")) fx.closeWindow("main");
        },
        else => {},
    }
}

fn clearToastNow(model: *Model) void {
    model.toast = "";
    model.toast_len = 0;
    model.toast_visible = false;
    model.toast_sticky = false;
}

fn setUpdateBanner(model: *Model, text: []const u8) void {
    const n = @min(text.len, model.update_banner_buf.len);
    @memcpy(model.update_banner_buf[0..n], text[0..n]);
    model.update_banner = model.update_banner_buf[0..n];
    model.update_banner_visible = n > 0;
}

fn runUpdateCheck(model: *Model) void {
    model.update_checked = true;
    const msg = std.fmt.bufPrint(
        &model.update_banner_buf,
        "Velocity {s} — update check (dev): you're up to date",
        .{app_version},
    ) catch "Velocity — you're up to date";
    const n = @min(msg.len, model.update_banner_buf.len);
    model.update_banner = model.update_banner_buf[0..n];
    model.update_banner_visible = true;
    model.toast = model.update_banner;
}

fn updateInner(model: *Model, msg: Msg, fx: ?*Effects) void {
    switch (msg) {
        .open_command_palette => {
            model.command_palette_open = true;
            model.command_query.clear();
            filterCommandPalette(model);
        },
        .close_command_palette => {
            model.command_palette_open = false;
            model.command_query.clear();
            model.quick_open_visible = false;
            model.command_items = &commands;
        },
        .dismiss_overlay => dismissOverlay(model),
        .update_command_query => |edit| {
            model.command_query.apply(edit);
            filterCommandPalette(model);
        },
        .run_command => |id| {
            model.command_palette_open = false;
            model.command_query.clear();
            model.command_items = &commands;
            if (std.mem.eql(u8, id, "toggle_terminal")) {
                toggleTerminalPanel(model);
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
            } else if (std.mem.eql(u8, id, "overwrite_file")) {
                overwriteActiveDocument(model);
            } else if (std.mem.eql(u8, id, "save_all")) {
                saveAllDirtyTabs(model);
            } else if (std.mem.eql(u8, id, "create_new_file")) {
                createNewFile(model);
            } else if (std.mem.eql(u8, id, "delete_selected_file")) {
                deleteSelectedFile(model);
            } else if (std.mem.eql(u8, id, "rename_selected_file")) {
                renameSelectedFile(model);
            } else if (std.mem.eql(u8, id, "reveal_in_explorer")) {
                revealInExplorer(model);
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
            } else if (std.mem.eql(u8, id, "close_other_tabs")) {
                closeOtherTabs(model);
            } else if (std.mem.eql(u8, id, "close_all_tabs")) {
                closeAllTabs(model);
            } else if (std.mem.eql(u8, id, "pin_active_tab")) {
                pinActiveTab(model);
            } else if (std.mem.eql(u8, id, "toggle_focus_mode")) {
                toggleFocusMode(model);
            } else if (std.mem.eql(u8, id, "toggle_shortcuts_help")) {
                model.shortcuts_help_visible = !model.shortcuts_help_visible;
            } else if (std.mem.eql(u8, id, "transform_upper")) {
                runTextTransform(model, .upper);
            } else if (std.mem.eql(u8, id, "transform_lower")) {
                runTextTransform(model, .lower);
            } else if (std.mem.eql(u8, id, "transform_title")) {
                runTextTransform(model, .title);
            } else if (std.mem.eql(u8, id, "transform_sort_lines")) {
                runTextTransform(model, .sort);
            } else if (std.mem.eql(u8, id, "transform_reverse_lines")) {
                runTextTransform(model, .reverse);
            } else if (std.mem.eql(u8, id, "collapse_blank_lines")) {
                collapseBlankLines(model);
            } else if (std.mem.eql(u8, id, "copy_all_tab_paths")) {
                copyAllTabPaths(model);
            } else if (std.mem.eql(u8, id, "new_untitled")) {
                newUntitledBuffer(model);
            } else if (std.mem.eql(u8, id, "delete_last_line")) {
                deleteLastLine(model);
            } else if (std.mem.eql(u8, id, "join_lines")) {
                joinDocumentLines(model);
            } else if (std.mem.eql(u8, id, "move_line_up")) {
                moveDocumentLine(model, true);
            } else if (std.mem.eql(u8, id, "move_line_down")) {
                moveDocumentLine(model, false);
            } else if (std.mem.eql(u8, id, "undo_edit")) {
                undoLastEdit(model);
            } else if (std.mem.eql(u8, id, "redo_edit")) {
                redoLastEdit(model);
            } else if (std.mem.eql(u8, id, "revert_file")) {
                revertActiveFile(model);
            } else if (std.mem.eql(u8, id, "copy_absolute_path")) {
                copyAbsolutePath(model);
            } else if (std.mem.eql(u8, id, "next_tab")) {
                cycleTab(model, true);
            } else if (std.mem.eql(u8, id, "prev_tab")) {
                cycleTab(model, false);
            } else if (std.mem.eql(u8, id, "remove_blank_lines")) {
                removeBlankLines(model);
            } else if (std.mem.eql(u8, id, "insert_blank_line")) {
                insertBlankLine(model);
            } else if (std.mem.eql(u8, id, "copy_filename")) {
                copyFileName(model);
            } else if (std.mem.eql(u8, id, "show_word_count")) {
                showWordCount(model);
            } else if (std.mem.eql(u8, id, "cycle_indent_size")) {
                cycleIndentSize(model);
            } else if (std.mem.eql(u8, id, "convert_tabs_to_spaces")) {
                convertIndent(model, true);
            } else if (std.mem.eql(u8, id, "convert_spaces_to_tabs")) {
                convertIndent(model, false);
            } else if (std.mem.eql(u8, id, "transform_sort_unique")) {
                runTextTransform(model, .sort_unique);
            } else if (std.mem.eql(u8, id, "convert_to_lf")) {
                convertLineEndings(model, true);
            } else if (std.mem.eql(u8, id, "convert_to_crlf")) {
                convertLineEndings(model, false);
            } else if (std.mem.eql(u8, id, "toggle_find_whole_word")) {
                toggleFindWholeWord(model);
            } else if (std.mem.eql(u8, id, "duplicate_selected_file")) {
                duplicateSelectedFile(model);
            } else if (std.mem.eql(u8, id, "toggle_search_case")) {
                toggleSearchCase(model);
            } else if (std.mem.eql(u8, id, "toggle_sidebar")) {
                toggleSidebar(model);
            } else if (std.mem.eql(u8, id, "insert_timestamp")) {
                insertTimestamp(model);
            } else if (std.mem.eql(u8, id, "toggle_trim_trailing")) {
                toggleTrimTrailing(model);
            } else if (std.mem.eql(u8, id, "toggle_final_newline")) {
                toggleFinalNewline(model);
            } else if (std.mem.eql(u8, id, "run_terminal")) {
                runTerminalFromModel(model, fx);
            } else if (std.mem.eql(u8, id, "stop_terminal_task")) {
                stopTerminalTask(model, fx);
            } else if (std.mem.eql(u8, id, "run_selected_task")) {
                runSelectedTask(model, fx);
            } else if (std.mem.eql(u8, id, "refresh_tasks")) {
                refreshTasks(model);
            } else if (std.mem.eql(u8, id, "run_search")) {
                model.current_view = .ide;
                model.selected_activity = .search;
                model.show_sidebar = true;
                runWorkspaceSearch(model);
            } else if (std.mem.eql(u8, id, "preview_workspace_replace")) {
                previewWorkspaceReplace(model);
            } else if (std.mem.eql(u8, id, "apply_workspace_replace")) {
                applyWorkspaceReplace(model);
            } else if (std.mem.eql(u8, id, "refresh_git")) {
                model.current_view = .ide;
                model.selected_activity = .scm;
                model.show_sidebar = true;
                refreshGitStatus(model);
            } else if (std.mem.eql(u8, id, "stage_all")) {
                stageAllChanges(model);
            } else if (std.mem.eql(u8, id, "unstage_all")) {
                unstageAllChanges(model);
            } else if (std.mem.eql(u8, id, "stage_git_entry")) {
                stageGitEntry(model, model.selected_git_entry_id);
            } else if (std.mem.eql(u8, id, "unstage_git_entry")) {
                unstageGitEntry(model, model.selected_git_entry_id);
            } else if (std.mem.eql(u8, id, "restore_git_entry")) {
                restoreGitEntry(model, model.selected_git_entry_id);
            } else if (std.mem.eql(u8, id, "discard_changes")) {
                discardWorkingTreeChanges(model);
            } else if (std.mem.eql(u8, id, "commit_changes")) {
                commitChanges(model);
            } else if (std.mem.eql(u8, id, "trim_blank_lines")) {
                trimBlankLines(model);
            } else if (std.mem.eql(u8, id, "refresh_explorer")) {
                refreshExplorer(model);
            } else if (std.mem.eql(u8, id, "refresh_disk_sync")) {
                refreshDiskSync(model, true);
            } else if (std.mem.eql(u8, id, "close_saved_tabs")) {
                closeSavedTabs(model);
            } else if (std.mem.eql(u8, id, "compare_with_saved")) {
                compareWithSaved(model);
            } else if (std.mem.eql(u8, id, "copy_git_branch")) {
                copyGitBranch(model);
            } else if (std.mem.eql(u8, id, "clear_recent_projects")) {
                clearRecentProjects(model);
            } else if (std.mem.eql(u8, id, "insert_uuid")) {
                insertUuid(model);
            } else if (std.mem.eql(u8, id, "format_document")) {
                formatDocument(model);
            } else if (std.mem.eql(u8, id, "hard_wrap")) {
                hardWrapDocument(model);
            } else if (std.mem.eql(u8, id, "copy_document")) {
                copyDocument(model);
            } else if (std.mem.eql(u8, id, "go_to_symbol")) {
                goToSymbol(model);
            } else if (std.mem.eql(u8, id, "go_to_definition")) {
                runGoToDefinition(model);
            } else if (std.mem.eql(u8, id, "open_outline")) {
                model.selected_activity = .outline;
                model.current_view = .ide;
                model.show_sidebar = true;
                refreshOutline(model);
            } else if (std.mem.eql(u8, id, "toggle_bottom_panel")) {
                model.bottom_panel_open = !model.bottom_panel_open;
                if (!model.bottom_panel_open) model.show_terminal = false;
                persistPrefs(model);
            } else if (std.mem.eql(u8, id, "clear_output")) {
                model.output_count = 0;
                model.output_lines = &.{};
                model.toast = "Output cleared";
            } else if (std.mem.eql(u8, id, "create_folder")) {
                createFolder(model);
            } else if (std.mem.eql(u8, id, "show_file_size")) {
                showFileSize(model);
            } else if (std.mem.eql(u8, id, "toggle_word_wrap")) {
                toggleWordWrap(model);
            } else if (std.mem.eql(u8, id, "check_for_updates")) {
                runUpdateCheck(model);
            } else if (std.mem.eql(u8, id, "toggle_notifications_panel")) {
                model.notifications_panel_open = !model.notifications_panel_open;
            } else if (std.mem.eql(u8, id, "minimize_window")) {
                // Handled in updateFx via handleWindowActions when fx is present.
            } else if (std.mem.eql(u8, id, "close_window")) {
                persistHotExit(model);
            } else if (std.mem.eql(u8, id, "reopen_last_workspace")) {
                reopenLastWorkspace(model);
            } else if (std.mem.eql(u8, id, "clear_find")) {
                clearFind(model);
            } else if (std.mem.eql(u8, id, "duplicate_line")) {
                duplicateDocumentTail(model);
            } else if (std.mem.eql(u8, id, "toggle_line_comment")) {
                toggleLineComment(model);
            } else if (std.mem.eql(u8, id, "indent_document")) {
                indentDocument(model, true);
            } else if (std.mem.eql(u8, id, "outdent_document")) {
                indentDocument(model, false);
            } else if (std.mem.eql(u8, id, "reopen_closed_tab")) {
                reopenClosedTab(model);
            } else if (std.mem.eql(u8, id, "scan_problems")) {
                scanProblems(model);
            } else if (std.mem.eql(u8, id, "parse_terminal_diagnostics")) {
                parseTerminalDiagnostics(model, true);
            } else if (std.mem.eql(u8, id, "open_feature_matrix")) {
                model.current_view = .features;
                model.selected_activity = .features;
            } else if (std.mem.eql(u8, id, "open_process_governor")) {
                model.current_view = .processes;
                model.selected_activity = .processes;
            } else if (std.mem.eql(u8, id, "kill_all_workspace_processes")) {
                if (fx) |effects| cancelOwnedEffects(model, effects);
                model.governor.killAll();
                model.process_count = model.governor.aliveCount();
                model.terminal_process_count = 0;
                model.lsp_process_count = 0;
                model.plugin_process_count = 0;
                model.process_leaked = 0;
                model.task_running = false;
                model.task_status = "Task idle";
            } else if (std.mem.eql(u8, id, "instant_safe_mode")) {
                model.safe_mode = true;
                model.runtime_mode_label = "Safe";
                model.show_agent_panel = false;
                model.features_loaded = 3;
            }
        },
        .select_activity => |activity| {
            switch (activity) {
                .plugins => {
                    model.selected_activity = activity;
                    model.current_view = .plugins;
                },
                .settings => {
                    model.selected_activity = activity;
                    model.current_view = .settings;
                },
                .search => {
                    model.selected_activity = .search;
                    model.current_view = .ide;
                    model.show_sidebar = true;
                    if (model.workspace_from_disk and model.search_hits.len == 0 and model.search_query.text().len > 0) {
                        runWorkspaceSearch(model);
                    }
                },
                .scm => {
                    model.selected_activity = .scm;
                    model.current_view = .ide;
                    model.show_sidebar = true;
                    refreshGitStatus(model);
                },
                .debug => {
                    model.selected_activity = activity;
                    model.current_view = .debug;
                },
                .testing => {
                    model.selected_activity = activity;
                    model.current_view = .testing;
                },
                .features => {
                    model.selected_activity = activity;
                    model.current_view = .features;
                },
                .processes => {
                    model.selected_activity = activity;
                    model.current_view = .processes;
                },
                .problems => {
                    model.selected_activity = .problems;
                    model.current_view = .ide;
                    openBottomPanel(model, .problems);
                },
                .outline => {
                    model.selected_activity = .outline;
                    model.current_view = .ide;
                    model.show_sidebar = true;
                    refreshOutline(model);
                },
                .terminal => {
                    model.current_view = .ide;
                    toggleTerminalPanel(model);
                },
                .agents => {
                    model.current_view = .ide;
                    model.show_agent_panel = !model.show_agent_panel;
                    persistPrefs(model);
                },
                .explorer => {
                    model.selected_activity = .explorer;
                    model.current_view = .ide;
                    model.show_sidebar = true;
                },
            }
        },
        .toggle_terminal => toggleTerminalPanel(model),
        .toggle_agent_panel => {
            model.show_agent_panel = !model.show_agent_panel;
            persistPrefs(model);
        },
        .select_file => |id| {
            model.current_view = .ide;
            model.selected_activity = .explorer;
            if (model.workspace_from_disk) {
                if (model.workspace) |ws| {
                    if (ws.findNode(id)) |node| {
                        if (node.is_dir) {
                            model.selected_file_id = id;
                            model.toast = "Folder selected";
                            return;
                        }
                    }
                    if (!openWorkspaceFile(model, ws, id)) return;
                    model.selected_file_id = id;
                    model.active_tab_id = id;
                    model.open_tabs = ws.tabsSlice();
                    if (ws.findNode(id)) |node| {
                        model.status_language = workspace_store.scannerLanguage(node.path);
                        pushRecentFile(model, node.path);
                    }
                    syncDocumentFromWorkspace(model);
                    return;
                }
            }
            for (file_tree) |node| {
                if (node.id == id) {
                    if (node.is_dir) {
                        model.selected_file_id = id;
                        model.toast = "Folder selected";
                        return;
                    }
                    break;
                }
            }
            model.selected_file_id = id;
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
        .close_other_tabs => closeOtherTabs(model),
        .close_all_tabs => closeAllTabs(model),
        .pin_active_tab => pinActiveTab(model),
        .toggle_focus_mode => toggleFocusMode(model),
        .toggle_shortcuts_help => model.shortcuts_help_visible = !model.shortcuts_help_visible,
        .transform_upper => runTextTransform(model, .upper),
        .transform_lower => runTextTransform(model, .lower),
        .transform_sort_lines => runTextTransform(model, .sort),
        .transform_reverse_lines => runTextTransform(model, .reverse),
        .transform_title => runTextTransform(model, .title),
        .collapse_blank_lines => collapseBlankLines(model),
        .trim_blank_lines => trimBlankLines(model),
        .copy_all_tab_paths => copyAllTabPaths(model),
        .new_untitled => newUntitledBuffer(model),
        .toggle_trim_trailing => toggleTrimTrailing(model),
        .toggle_final_newline => toggleFinalNewline(model),
        .delete_last_line => deleteLastLine(model),
        .join_lines => joinDocumentLines(model),
        .move_line_up => moveDocumentLine(model, true),
        .move_line_down => moveDocumentLine(model, false),
        .undo_edit => undoLastEdit(model),
        .redo_edit => redoLastEdit(model),
        .revert_file => revertActiveFile(model),
        .copy_absolute_path => copyAbsolutePath(model),
        .next_tab => cycleTab(model, true),
        .prev_tab => cycleTab(model, false),
        .remove_blank_lines => removeBlankLines(model),
        .insert_blank_line => insertBlankLine(model),
        .copy_filename => copyFileName(model),
        .show_word_count => showWordCount(model),
        .cycle_indent_size => cycleIndentSize(model),
        .convert_tabs_to_spaces => convertIndent(model, true),
        .convert_spaces_to_tabs => convertIndent(model, false),
        .transform_sort_unique => runTextTransform(model, .sort_unique),
        .convert_to_lf => convertLineEndings(model, true),
        .convert_to_crlf => convertLineEndings(model, false),
        .toggle_find_whole_word => toggleFindWholeWord(model),
        .duplicate_selected_file => duplicateSelectedFile(model),
        .toggle_search_case => toggleSearchCase(model),
        .toggle_sidebar => toggleSidebar(model),
        .insert_timestamp => insertTimestamp(model),
        .select_tab => |id| {
            model.active_tab_id = id;
            if (model.workspace_from_disk) {
                if (model.workspace) |ws| {
                    if (!openWorkspaceFile(model, ws, id)) return;
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
            if (fx) |effects| cancelOwnedEffects(model, effects);
            model.governor.killAll();
            model.process_count = model.governor.aliveCount();
            model.terminal_process_count = 0;
            model.lsp_process_count = 0;
            model.plugin_process_count = 0;
            model.process_leaked = model.governor.leak_count;
            model.task_running = false;
            model.task_status = "Task idle";
            model.toast = "Killed workspace processes";
        },
        .instant_safe_mode => {
            model.safe_mode = true;
            model.runtime_mode_label = "Safe";
            model.show_agent_panel = false;
            model.features_loaded = 3;
        },
        .edit_document => |edit| {
            refreshDiskSync(model, false);
            pushUndoSnapshot(model);
            model.document.apply(edit);
            recordUndoResult(model);
            model.document_dirty = true;
            model.toast = "";
            refreshDocStats(model);
            syncActiveTabDirty(model);
            if (model.auto_save and model.workspace_from_disk) {
                saveActiveDocument(model);
            }
        },
        .save_file => saveActiveDocument(model),
        .overwrite_file => overwriteActiveDocument(model),
        .save_all => saveAllDirtyTabs(model),
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
        .stop_terminal_task => stopTerminalTask(model, fx),
        .clear_terminal => {
            if (model.terminal) |t| t.clear();
            model.term_lines = &.{};
            model.toast = "Terminal cleared";
        },
        .update_search_query => |edit| {
            model.search_query.apply(edit);
            invalidateWorkspaceReplace(model);
        },
        .run_search => runWorkspaceSearch(model),
        .open_search_hit => |id| openSearchHit(model, id),
        .preview_workspace_replace => previewWorkspaceReplace(model),
        .apply_workspace_replace => applyWorkspaceReplace(model),
        .refresh_git => refreshGitStatus(model),
        .update_commit_message => |edit| model.git_commit_message.apply(edit),
        .stage_all => stageAllChanges(model),
        .unstage_all => unstageAllChanges(model),
        .discard_changes => discardWorkingTreeChanges(model),
        .commit_changes => commitChanges(model),
        .refresh_explorer => refreshExplorer(model),
        .refresh_disk_sync => refreshDiskSync(model, true),
        .disk_poll_timer => |timer| {
            if (timer.key != disk_poll_timer_key) return;
            switch (timer.outcome) {
                .fired => {
                    if (model.disk_poll_armed and model.workspace_from_disk) {
                        refreshDiskSync(model, false);
                    }
                },
                .rejected => {
                    model.disk_poll_armed = false;
                    model.disk_poll_rejected = true;
                    model.toast = "Automatic disk polling unavailable; use Refresh Files from Disk";
                },
            }
        },
        .close_saved_tabs => closeSavedTabs(model),
        .compare_with_saved => compareWithSaved(model),
        .copy_git_branch => copyGitBranch(model),
        .clear_recent_projects => clearRecentProjects(model),
        .insert_uuid => insertUuid(model),
        .format_document => formatDocument(model),
        .hard_wrap => hardWrapDocument(model),
        .copy_document => copyDocument(model),
        .go_to_symbol => goToSymbol(model),
        .create_folder => createFolder(model),
        .show_file_size => showFileSize(model),
        .toggle_word_wrap => toggleWordWrap(model),
        .open_outline => {
            model.selected_activity = .outline;
            model.current_view = .ide;
            model.show_sidebar = true;
            refreshOutline(model);
        },
        .select_outline_symbol => |id| {
            if (model.outline_bufs) |bufs| {
                for (bufs.symbolsSlice()) |sym| {
                    if (sym.id == id) {
                        jumpToDocumentLine(model, sym.line);
                        return;
                    }
                }
            }
            model.toast = "Symbol not found";
        },
        .go_to_definition => runGoToDefinition(model),
        .open_def_hit => |id| openDefHit(model, id),
        .select_breadcrumb => |id| selectBreadcrumbSeg(model, id),
        .select_bottom_tab => |tab| {
            openBottomPanel(model, tab);
            persistPrefs(model);
        },
        .toggle_bottom_panel => {
            model.bottom_panel_open = !model.bottom_panel_open;
            model.show_terminal = model.bottom_panel_open and model.bottom_panel_tab == .terminal;
            persistPrefs(model);
        },
        .clear_output => {
            model.output_count = 0;
            model.output_lines = &.{};
            model.toast = "Output cleared";
        },
        .open_symbol_palette => {
            refreshOutline(model);
            model.symbol_palette_open = true;
            model.symbol_query.clear();
        },
        .close_symbol_palette => {
            model.symbol_palette_open = false;
            model.symbol_query.clear();
        },
        .update_symbol_query => |edit| {
            model.symbol_query.apply(edit);
            filterOutlineSymbols(model);
        },
        .open_symbol_item => |id| {
            if (model.outline_bufs) |bufs| {
                for (bufs.symbolsSlice()) |sym| {
                    if (sym.id == id) {
                        model.symbol_palette_open = false;
                        jumpToDocumentLine(model, sym.line);
                        return;
                    }
                }
            }
            model.toast = "Symbol not found";
        },
        .open_git_entry => |id| openGitEntry(model, id),
        .select_git_entry => |id| selectGitEntry(model, id),
        .stage_git_entry => |id| stageGitEntry(model, id),
        .unstage_git_entry => |id| unstageGitEntry(model, id),
        .restore_git_entry => |id| restoreGitEntry(model, id),
        .clear_find => clearFind(model),
        .reopen_last_workspace => reopenLastWorkspace(model),
        .update_new_file_path => |edit| model.new_file_path.apply(edit),
        .create_new_file => createNewFile(model),
        .delete_selected_file => deleteSelectedFile(model),
        .rename_selected_file => renameSelectedFile(model),
        .reveal_in_explorer => revealInExplorer(model),
        .update_explorer_filter => |edit| {
            model.explorer_filter.apply(edit);
            applyExplorerFilter(model);
        },
        .update_find_query => |edit| model.find_query.apply(edit),
        .run_find => runFindInDocument(model),
        .find_next => findNavigate(model, true),
        .find_prev => findNavigate(model, false),
        .update_replace_text => |edit| {
            model.replace_text.apply(edit);
            invalidateWorkspaceReplace(model);
        },
        .replace_once => replaceOnceInDocument(model),
        .replace_all => replaceAllInDocument(model),
        .copy_active_path => copyActivePath(model),
        .refresh_recent => syncRecentFromPrefs(model),
        .toggle_auto_save => toggleAutoSave(model),
        .toggle_find_case => toggleFindCase(model),
        .duplicate_line => duplicateDocumentTail(model),
        .toggle_line_comment => toggleLineComment(model),
        .indent_document => indentDocument(model, true),
        .outdent_document => indentDocument(model, false),
        .reopen_closed_tab => reopenClosedTab(model),
        .scan_problems => scanProblems(model),
        .parse_terminal_diagnostics => parseTerminalDiagnostics(model, true),
        .open_problem => |id| openProblem(model, id),
        .preview_git_diff => |id| previewGitDiff(model, id),
        .terminal_history_older => terminalHistory(model, true),
        .terminal_history_newer => terminalHistory(model, false),
        .refresh_tasks => refreshTasks(model),
        .select_task => |id| selectTask(model, id),
        .run_selected_task => runSelectedTask(model, fx),
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
        .goto_line => runGotoLine(model),
        .terminal_line => |line| {
            if (!model.terminal_async or line.key != model.terminal_effect_key) return;
            if (ensureTerminalBuffers(model)) |term| {
                term.pushLine(line.line);
                model.term_lines = term.linesSlice();
                term.status = "running";
            } else |_| {}
        },
        .terminal_exit => |exit| {
            if (!model.terminal_async or exit.key != model.terminal_effect_key) return;
            if (ensureTerminalBuffers(model)) |term| {
                term.running = false;
                term.last_exit = exit.code;
                term.status = switch (exit.reason) {
                    .exited => if (exit.code == 0) "ok" else "exited",
                    .cancelled => "cancelled",
                    .rejected => "rejected",
                    .signaled => "signaled",
                    .spawn_failed => "spawn_failed",
                };
                var exit_buf: [48]u8 = undefined;
                const exit_msg = std.fmt.bufPrint(&exit_buf, "[exit {d} / {s}]", .{ exit.code, @tagName(exit.reason) }) catch "[exit]";
                term.pushLine(exit_msg);
                model.term_lines = term.linesSlice();
            } else |_| {}
            clearActiveCommand(model, switch (exit.reason) {
                .exited => .exited,
                .cancelled => .cancelled,
                .rejected => .rejected,
                .signaled => .signaled,
                .spawn_failed => .spawn_failed,
            }, exit.code);
            parseTerminalDiagnostics(model, false);
            if (model.problems.len == 0) {
                model.toast = switch (exit.reason) {
                    .exited => if (exit.code == 0) "Command ok" else "Command exited",
                    .cancelled => "Command cancelled",
                    .rejected => "Command rejected by Effects; try again after the active command exits",
                    .signaled => "Command terminated by signal",
                    .spawn_failed => "Command could not be started",
                };
            }
        },
        .chrome_changed => |chrome| {
            model.chrome_leading = chrome.insets.left;
            model.chrome_trailing = chrome.insets.right;
            model.header_height = @max(header_natural_height, chrome.insets.top);
            const has_insets = chrome.insets.left > 0 or chrome.insets.right > 0 or chrome.insets.top > 0;
            if (has_insets) model.chrome_seen_insets = true;
            if (model.chrome_seen_insets) {
                const was_fs = model.window_fullscreen;
                model.window_fullscreen = !has_insets;
                if (model.window_fullscreen and !was_fs) {
                    model.toast = "Entered fullscreen";
                } else if (!model.window_fullscreen and was_fs) {
                    model.toast = "Exited fullscreen";
                }
            }
        },
        .set_appearance => |appearance| model.appearance = appearance,
        .clear_toast => clearToastNow(model),
        .toast_timer => clearToastNow(model),
        .dismiss_update_banner => {
            model.update_banner_visible = false;
            model.update_banner = "";
        },
        .check_for_updates => runUpdateCheck(model),
        .minimize_window => {},
        .close_window => persistHotExit(model),
        .toggle_notifications_panel => {
            model.notifications_panel_open = !model.notifications_panel_open;
        },
        .update_settings_query => |edit| model.settings_query.apply(edit),
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

fn openWorkspaceFile(model: *Model, ws: *workspace_store.WorkspaceBuffers, id: u32) bool {
    const node = ws.findNode(id) orelse {
        model.toast = "File is no longer in the workspace";
        return false;
    };
    if (node.is_dir) return true;

    var loaded = false;
    for (ws.tabsSlice(), 0..) |tab, index| {
        if (tab.id == id) {
            loaded = ws.tab_text_loaded[index];
            break;
        }
    }
    if (!loaded) {
        var probe: [workspace_store.max_editor_bytes]u8 = undefined;
        _ = scanner_mod.readTextFile(modelIo(model), ws.rootPath(), node.path, &probe) catch |err| {
            model.toast = switch (err) {
                error.FileTooLarge => "File exceeds the 16 KiB editor limit; active tab was not changed",
                error.BinaryFile => "Binary file is not editable; active tab was not changed",
                else => "Unable to read file; active tab was not changed",
            };
            return false;
        };
    }
    if (model.disk_checker.isStale(id) and !ws.tabIsDirty(id)) {
        ws.reloadFileById(modelIo(model), id) catch |err| {
            model.toast = switch (err) {
                error.FileTooLarge => "File exceeds the 16 KiB editor limit; active tab was not changed",
                else => "Unable to reload changed file; active tab was not changed",
            };
            return false;
        };
        model.disk_checker.clearStale(id);
        ws.setTabStale(id, false);
        return true;
    }
    ws.openFileById(modelIo(model), id) catch |err| {
        model.toast = switch (err) {
            error.AllTabsDirty => "All 8 tabs have unsaved changes; save or close one before opening another",
            error.FileTooLarge => "File exceeds the 16 KiB editor limit; active tab was not changed",
            else => "Unable to open file; active tab was not changed",
        };
        return false;
    };
    return true;
}

fn refreshDiskSync(model: *Model, manual: bool) void {
    const ws = model.workspace orelse {
        if (manual) model.toast = "Open a workspace first";
        return;
    };
    const batch = model.disk_checker.check(
        modelIo(model),
        ws,
        if (manual) workspace_store.max_open_tabs else 1,
    );
    model.disk_changed = model.active_tab_id != 0 and model.disk_checker.isStale(model.active_tab_id);
    if (batch.event_count > 0) {
        var active_changed = false;
        for (batch.eventSlice()) |event| {
            ws.setTabStale(event.tab_id, true);
            if (!ws.tabIsDirty(event.tab_id)) {
                _ = ws.invalidateCleanTabById(event.tab_id);
                if (event.tab_id == model.active_tab_id) {
                    if (ws.reloadFileById(modelIo(model), event.tab_id)) |_| {
                        model.disk_checker.clearStale(event.tab_id);
                        ws.setTabStale(event.tab_id, false);
                        syncDocumentFromWorkspace(model);
                    } else |_| {}
                }
            } else if (event.tab_id == model.active_tab_id) {
                active_changed = true;
            }
        }
        model.open_tabs = ws.tabsSlice();
        model.disk_changed = model.active_tab_id != 0 and model.disk_checker.isStale(model.active_tab_id);
        model.toast = if (active_changed)
            "Active file changed externally — Compare or Revert; edits were preserved"
        else
            "An open file changed externally; clean tabs reload when selected";
    } else if (manual) {
        model.toast = if (model.disk_changed) "Active file still differs from disk" else "Disk state up to date";
    }
}

fn persistHotExit(model: *Model) void {
    const ws = model.workspace orelse return;
    if (!model.workspace_from_disk or ws.rootPath().len == 0) return;
    syncActiveTabDirty(model);
    var session_tabs: [hot_exit_store.max_tabs]hot_exit_store.TabInput = undefined;
    const count = @min(ws.tabsSlice().len, session_tabs.len);
    for (ws.tabsSlice()[0..count], 0..) |tab, index| {
        session_tabs[index] = .{
            .path = tab.path,
            .dirty = tab.dirty,
            .dirty_text = if (tab.dirty and ws.tab_text_loaded[index])
                ws.tab_text_pool[index][0..ws.tab_text_lens[index]]
            else
                "",
        };
    }
    hot_exit_store.persist(modelIo(model), ws.rootPath(), .{
        .root = ws.rootPath(),
        .active_path = ws.editorPath(),
        .tabs = session_tabs[0..count],
    }) catch {};
}

fn restoreHotExit(model: *Model, ws: *workspace_store.WorkspaceBuffers) bool {
    const state = std.heap.page_allocator.create(hot_exit_store.State) catch return false;
    defer std.heap.page_allocator.destroy(state);
    hot_exit_store.restore(modelIo(model), ws.rootPath(), state) catch return false;
    if (!std.mem.eql(u8, state.root(), ws.rootPath())) return false;

    while (ws.tab_count > 0) ws.closeTab(ws.tabs[0].id);
    var restored: u32 = 0;
    var i: usize = 0;
    while (i < state.tab_count) : (i += 1) {
        const node = ws.findNodeByPath(state.tabPath(i)) orelse continue;
        ws.openFileById(modelIo(model), node.id) catch continue;
        if (state.tab_dirty[i]) {
            ws.cacheActiveText(state.dirtyText(i));
            ws.setTabDirty(node.id, true);
        }
        restored += 1;
    }
    if (restored == 0) return false;
    if (ws.findNodeByPath(state.activePath())) |active| {
        ws.openFileById(modelIo(model), active.id) catch {};
        model.active_tab_id = active.id;
        model.selected_file_id = active.id;
    } else if (ws.tab_count > 0) {
        model.active_tab_id = ws.tabs[0].id;
        model.selected_file_id = ws.tabs[0].id;
        ws.openFileById(modelIo(model), model.active_tab_id) catch {};
    }
    model.open_tabs = ws.tabsSlice();
    syncDocumentFromWorkspace(model);
    return true;
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

fn ensureTaskBuffers(model: *Model) !*task_detector.TaskDetector {
    if (model.task_bufs) |tasks| return tasks;
    const tasks = try std.heap.page_allocator.create(task_detector.TaskDetector);
    tasks.* = .{};
    model.task_bufs = tasks;
    return tasks;
}

fn ensureWorkspaceReplaceBuffers(model: *Model) !*workspace_replace.WorkspaceReplace {
    if (model.workspace_replace_bufs) |workflow| return workflow;
    const workflow = try std.heap.page_allocator.create(workspace_replace.WorkspaceReplace);
    workflow.* = .{};
    model.workspace_replace_bufs = workflow;
    return workflow;
}

fn syncDocumentFromWorkspace(model: *Model) void {
    if (model.workspace) |ws| {
        model.document.set(ws.editorText());
        model.document_dirty = ws.activeTabDirty();
        model.disk_changed = ws.activeFileChanged(modelIo(model));
        resetUndoHistory(model);
        model.editor_mode_label = "editable";
        model.toast = "";
        refreshDocStats(model);
        refreshBreadcrumb(model);
        syncActiveTabDirty(model);
        refreshOutline(model);
        if (model.editor_focus_line > 0) refreshPeek(model);
    }
}

fn syncActiveTabDirty(model: *Model) void {
    if (model.workspace) |ws| {
        ws.cacheActiveText(model.document.text());
        ws.setTabDirty(model.active_tab_id, model.document_dirty);
        model.open_tabs = ws.tabsSlice();
    }
}

fn reloadCleanOpenPath(model: *Model, path: []const u8) void {
    const ws = model.workspace orelse return;
    const node = ws.findNodeByPath(path) orelse return;
    const was_active = node.id == model.active_tab_id;
    if (!ws.reloadCleanTabByPath(modelIo(model), path)) return;
    model.disk_checker.clearStale(node.id);
    ws.setTabStale(node.id, false);
    model.open_tabs = ws.tabsSlice();
    if (was_active) syncDocumentFromWorkspace(model);
}

/// Test helper — same as syncActiveTabDirty.
pub fn syncActiveTabDirtyForTest(model: *Model) void {
    syncActiveTabDirty(model);
}

pub fn refreshDocStats(model: *Model) void {
    const text = model.document.text();
    var lines: u32 = if (text.len == 0) 0 else 1;
    for (text) |c| {
        if (c == '\n') lines += 1;
    }
    if (text.len == 0) lines = 0;
    const eol = edit_transforms.detectEol(text);
    const words = edit_transforms.countWords(text);
    const enc = edit_transforms.encodingLabel(text);
    const label = std.fmt.bufPrint(&model.doc_stats_buf, "{d} lines · {d} words · {d} bytes · {s} · {s}", .{ lines, words, text.len, eol, enc }) catch "stats";
    model.doc_stats = label;
}

pub fn refreshBreadcrumb(model: *Model) void {
    const path = Model.activeTabPath(model);
    if (path.len == 0) {
        model.breadcrumb = model.project_name;
        model.breadcrumb_seg_count = 0;
        model.breadcrumb_segs = &.{};
        return;
    }
    const n = @min(path.len, model.breadcrumb_buf.len);
    @memcpy(model.breadcrumb_buf[0..n], path[0..n]);
    model.breadcrumb = model.breadcrumb_buf[0..n];

    var count: u32 = 0;
    {
        const label = model.project_name;
        const llen = @min(label.len, model.breadcrumb_label_pool[0].len);
        @memcpy(model.breadcrumb_label_pool[0][0..llen], label[0..llen]);
        model.breadcrumb_seg_storage[0] = .{
            .id = 1,
            .label = model.breadcrumb_label_pool[0][0..llen],
            .path = "",
        };
        count = 1;
    }
    var start: usize = 0;
    var i: usize = 0;
    while (i <= path.len and count < model.breadcrumb_seg_storage.len) : (i += 1) {
        if (i == path.len or path[i] == '/' or path[i] == '\\') {
            if (i > start) {
                const label = path[start..i];
                const prefix = path[0..i];
                const idx = count;
                const llen = @min(label.len, model.breadcrumb_label_pool[idx].len);
                @memcpy(model.breadcrumb_label_pool[idx][0..llen], label[0..llen]);
                const plen = @min(prefix.len, model.breadcrumb_path_pool[idx].len);
                @memcpy(model.breadcrumb_path_pool[idx][0..plen], prefix[0..plen]);
                model.breadcrumb_seg_storage[idx] = .{
                    .id = idx + 1,
                    .label = model.breadcrumb_label_pool[idx][0..llen],
                    .path = model.breadcrumb_path_pool[idx][0..plen],
                };
                count += 1;
            }
            start = i + 1;
        }
    }
    model.breadcrumb_seg_count = count;
    model.breadcrumb_segs = model.breadcrumb_seg_storage[0..count];
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
    applyDocumentTransform(model, out[0..result.out_len], "Replaced 1");
    var toast_keep: [48]u8 = undefined;
    const tn = @min(model.toast.len, toast_keep.len);
    @memcpy(toast_keep[0..tn], model.toast[0..tn]);
    runFindInDocument(model);
    model.toast = toast_keep[0..tn];
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
    const msg = std.fmt.bufPrint(&model.action_toast_buf, "Replaced {d}", .{result.count}) catch "Replaced";
    applyDocumentTransform(model, out[0..result.out_len], msg);
    var toast_keep: [48]u8 = undefined;
    const tn = @min(model.toast.len, toast_keep.len);
    @memcpy(toast_keep[0..tn], model.toast[0..tn]);
    runFindInDocument(model);
    @memcpy(model.action_toast_buf[0..tn], toast_keep[0..tn]);
    model.toast = model.action_toast_buf[0..tn];
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

fn copyAbsolutePath(model: *Model) void {
    const rel = Model.activeTabPath(model);
    if (rel.len == 0) {
        model.toast = "No active path";
        model.path_toast = "";
        return;
    }
    const root = model.project_path;
    if (root.len == 0 or std.mem.eql(u8, root, "(scratch)")) {
        copyActivePath(model);
        return;
    }
    const sep: u8 = if (root.len > 0 and root[root.len - 1] == '/') 0 else '/';
    const need = root.len + (if (sep == 0) @as(usize, 0) else 1) + rel.len;
    if (need > model.path_toast_buf.len) {
        model.toast = "Path too long";
        return;
    }
    @memcpy(model.path_toast_buf[0..root.len], root);
    var dst = root.len;
    if (sep != 0) {
        model.path_toast_buf[dst] = sep;
        dst += 1;
    }
    @memcpy(model.path_toast_buf[dst..][0..rel.len], rel);
    dst += rel.len;
    model.path_toast = model.path_toast_buf[0..dst];
    model.toast = model.path_toast;
}

fn copyFileName(model: *Model) void {
    const path = Model.activeTabPath(model);
    if (path.len == 0) {
        model.toast = "No active path";
        model.path_toast = "";
        return;
    }
    const name = edit_transforms.fileNameOf(path);
    const n = @min(name.len, model.path_toast_buf.len);
    @memcpy(model.path_toast_buf[0..n], name[0..n]);
    model.path_toast = model.path_toast_buf[0..n];
    model.toast = model.path_toast;
}

fn showWordCount(model: *Model) void {
    refreshDocStats(model);
    const words = edit_transforms.countWords(model.document.text());
    const msg = std.fmt.bufPrint(&model.action_toast_buf, "{d} words", .{words}) catch "words";
    model.toast = msg;
}

fn removeBlankLines(model: *Model) void {
    var out: [edit_transforms.max_out]u8 = undefined;
    const n = edit_transforms.removeBlankLines(model.document.text(), &out) orelse {
        model.toast = "Remove blank lines failed";
        return;
    };
    applyDocumentTransform(model, out[0..n], "Removed blank lines");
}

fn insertBlankLine(model: *Model) void {
    var out: [edit_transforms.max_out]u8 = undefined;
    const n = edit_transforms.insertBlankLineAtEnd(model.document.text(), &out) orelse {
        model.toast = "Insert blank line failed";
        return;
    };
    applyDocumentTransform(model, out[0..n], "Inserted blank line");
}

fn cycleTab(model: *Model, forward: bool) void {
    const open = model.open_tabs;
    if (open.len < 2) {
        model.toast = if (open.len == 0) "No tabs" else "Only one tab";
        return;
    }
    var idx: usize = 0;
    var found = false;
    for (open, 0..) |tab, i| {
        if (tab.id == model.active_tab_id) {
            idx = i;
            found = true;
            break;
        }
    }
    if (!found) idx = 0;
    const next_idx: usize = if (forward)
        (idx + 1) % open.len
    else if (idx == 0)
        open.len - 1
    else
        idx - 1;
    const next_id = open[next_idx].id;
    model.active_tab_id = next_id;
    if (model.workspace_from_disk) {
        if (model.workspace) |ws| {
            ws.openFileById(modelIo(model), next_id) catch {};
            model.open_tabs = ws.tabsSlice();
            syncDocumentFromWorkspace(model);
        }
    }
    model.toast = "Switched tab";
}

fn pushUndoSnapshot(model: *Model) void {
    const history = ensureUndoHistory(model) catch return;
    _ = history.record(model.document.text()) catch {};
}

fn undoLastEdit(model: *Model) void {
    const history = model.undo_history orelse {
        model.toast = "Nothing to undo";
        return;
    };
    var output: [max_document]u8 = undefined;
    const previous = history.undo(&output) catch {
        model.toast = "Undo failed";
        return;
    };
    const text = previous orelse {
        model.toast = "Nothing to undo";
        return;
    };
    model.document.set(text);
    model.document_dirty = true;
    refreshDocStats(model);
    syncActiveTabDirty(model);
    model.toast = "Undone";
}

fn redoLastEdit(model: *Model) void {
    const history = model.undo_history orelse {
        model.toast = "Nothing to redo";
        return;
    };
    var output: [max_document]u8 = undefined;
    const next = history.redo(&output) catch {
        model.toast = "Redo failed";
        return;
    };
    const text = next orelse {
        model.toast = "Nothing to redo";
        return;
    };
    model.document.set(text);
    model.document_dirty = true;
    refreshDocStats(model);
    syncActiveTabDirty(model);
    model.toast = "Redone";
}

fn ensureUndoHistory(model: *Model) !*undo_stack.UndoStack {
    if (model.undo_history) |history| return history;
    const history = try std.heap.page_allocator.create(undo_stack.UndoStack);
    errdefer std.heap.page_allocator.destroy(history);
    history.* = try undo_stack.UndoStack.init(std.heap.page_allocator, .{
        .max_entries = 32,
        .max_bytes = max_document * 16,
    });
    model.undo_history = history;
    return history;
}

fn recordUndoResult(model: *Model) void {
    const history = ensureUndoHistory(model) catch return;
    _ = history.record(model.document.text()) catch {};
}

fn resetUndoHistory(model: *Model) void {
    const history = ensureUndoHistory(model) catch return;
    history.clear();
    _ = history.record(model.document.text()) catch {};
}

fn revertActiveFile(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Nothing to revert";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    if (model.active_tab_id == 0) {
        model.toast = "No active file";
        return;
    }
    pushUndoSnapshot(model);
    ws.reloadFileById(modelIo(model), model.active_tab_id) catch {
        model.toast = "Revert failed";
        return;
    };
    model.open_tabs = ws.tabsSlice();
    if (model.workspace) |w| {
        model.document.set(w.editorText());
        model.document_dirty = false;
        model.disk_changed = false;
        model.editor_mode_label = "editable";
        refreshDocStats(model);
        refreshBreadcrumb(model);
        syncActiveTabDirty(model);
    }
    recordUndoResult(model);
    model.toast = "Reverted from disk";
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
    refreshWorkspaceFileCount(model);
    applyExplorerFilter(model);
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
    const restored = meta.scan_error.len == 0 and restoreHotExit(model, ws);
    refreshTasks(model);
    if (meta.scan_error.len > 0) {
        model.toast = meta.scan_error;
    } else if (restored) {
        model.toast = "Hot-exit session restored";
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
    if (ws.activeFileChanged(modelIo(model))) {
        model.disk_changed = true;
        model.toast = "File changed on disk — Compare, Revert, or Overwrite";
        return;
    }
    applySaveHygiene(model);
    ws.saveActiveFile(modelIo(model), model.document.text()) catch |err| {
        if (err == error.FileChanged) {
            model.disk_changed = true;
            model.toast = "File changed on disk — Compare, Revert, or Overwrite";
        } else if (err == error.FileTooLarge) {
            model.toast = "File exceeds the 16 KiB editor limit; nothing was saved";
        } else {
            model.toast = "Save failed";
        }
        return;
    };
    model.document_dirty = false;
    model.disk_changed = false;
    model.toast = "Saved";
    syncActiveTabDirty(model);
}

fn overwriteActiveDocument(model: *Model) void {
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    if (!model.disk_changed) {
        saveActiveDocument(model);
        return;
    }
    if (!std.mem.startsWith(u8, model.toast, "Overwrite changed file")) {
        model.toast = "Overwrite changed file? Confirm again";
        return;
    }
    applySaveHygiene(model);
    ws.saveActiveFileForce(modelIo(model), model.document.text()) catch |err| {
        model.toast = if (err == error.FileTooLarge)
            "File exceeds the 16 KiB backup limit; original left unchanged"
        else
            "Overwrite failed; original left unchanged";
        return;
    };
    model.document_dirty = false;
    model.disk_changed = false;
    model.disk_checker.reset();
    syncActiveTabDirty(model);
    model.toast = "Overwritten safely";
}

fn applySaveHygiene(model: *Model) void {
    var out: [edit_transforms.max_out]u8 = undefined;
    var text = model.document.text();
    var changed = false;
    if (model.trim_trailing_ws) {
        if (edit_transforms.trimTrailingWhitespace(text, &out)) |n| {
            if (!std.mem.eql(u8, text, out[0..n])) {
                model.document.set(out[0..n]);
                text = model.document.text();
                changed = true;
            }
        }
    }
    if (model.insert_final_newline) {
        if (edit_transforms.ensureFinalNewline(text, &out)) |n| {
            if (!std.mem.eql(u8, text, out[0..n])) {
                model.document.set(out[0..n]);
                changed = true;
            }
        }
    }
    if (changed) refreshDocStats(model);
}

fn saveAllDirtyTabs(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Nothing to save";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    if (model.document_dirty) {
        syncActiveTabDirty(model);
    }
    var saved: u32 = 0;
    var conflicts: u32 = 0;
    var failures: u32 = 0;
    var i: u32 = 0;
    while (i < ws.tab_count) : (i += 1) {
        if (ws.tabs[i].dirty) {
            ws.saveTabById(modelIo(model), ws.tabs[i].id) catch |err| {
                if (err == error.FileChanged) {
                    conflicts += 1;
                    if (ws.tabs[i].id == model.active_tab_id) model.disk_changed = true;
                } else {
                    failures += 1;
                }
                continue;
            };
            saved += 1;
        }
    }
    model.document_dirty = ws.tabIsDirty(model.active_tab_id);
    model.open_tabs = ws.tabsSlice();
    if (conflicts > 0 or failures > 0) {
        model.toast = std.fmt.bufPrint(
            &model.action_toast_buf,
            "Saved {d}; {d} conflicts, {d} errors remain",
            .{ saved, conflicts, failures },
        ) catch "Save All partial; conflicts remain";
    } else {
        model.disk_changed = false;
        model.toast = if (saved == 0) "Nothing dirty" else "Saved all";
    }
}

fn filterCommandPalette(model: *Model) void {
    const q = model.command_query.text();
    if (q.len == 0) {
        model.command_items = &commands;
        model.command_filtered_count = 0;
        return;
    }
    var count: u32 = 0;
    for (commands) |cmd| {
        if (count >= model.command_filtered.len) break;
        if (std.ascii.indexOfIgnoreCase(cmd.title, q) != null or std.ascii.indexOfIgnoreCase(cmd.id, q) != null) {
            model.command_filtered[count] = cmd;
            count += 1;
        }
    }
    model.command_filtered_count = count;
    model.command_items = model.command_filtered[0..count];
}

pub fn filterCommandPaletteForTest(model: *Model) void {
    filterCommandPalette(model);
}

fn jumpToDocumentLine(model: *Model, line_no: u32) void {
    if (line_no == 0) return;
    var total: u32 = 1;
    for (model.document.text()) |c| {
        if (c == '\n') total += 1;
    }
    const target = @min(line_no, total);
    const label = std.fmt.bufPrint(&model.goto_line_buf, "Line {d}/{d}", .{ target, total }) catch "line";
    model.goto_line_label = label;
    model.editor_focus_line = target;
    const fl = std.fmt.bufPrint(&model.editor_focus_buf, "L{d}", .{target}) catch "L?";
    model.editor_focus_label = fl;
    refreshPeek(model);
    model.toast = model.goto_line_label;
}

fn refreshPeek(model: *Model) void {
    model.peek_count = editor_view.buildPeek(
        model.document.text(),
        model.editor_focus_line,
        model.peek_storage[0..],
        model.peek_pool[0..],
        model.peek_lens[0..],
    );
    model.peek_lines = model.peek_storage[0..model.peek_count];
}

fn appendOutput(model: *Model, text: []const u8) void {
    if (text.len == 0) return;
    var i: usize = 47;
    while (i > 0) : (i -= 1) {
        if (i - 1 >= model.output_count) continue;
        const len = model.output_lens[i - 1];
        @memcpy(model.output_pool[i][0..len], model.output_pool[i - 1][0..len]);
        model.output_lens[i] = len;
        model.output_storage[i] = .{
            .id = model.output_storage[i - 1].id,
            .text = model.output_pool[i][0..len],
        };
    }
    const n = @min(text.len, model.output_pool[0].len);
    @memcpy(model.output_pool[0][0..n], text[0..n]);
    model.output_lens[0] = n;
    model.output_storage[0] = .{
        .id = model.output_next_id,
        .text = model.output_pool[0][0..n],
    };
    model.output_next_id +%= 1;
    if (model.output_count < 48) model.output_count += 1;
    model.output_lines = model.output_storage[0..model.output_count];
}

fn pushRecentFile(model: *Model, path: []const u8) void {
    if (path.len == 0) return;
    var i: u32 = 0;
    while (i < model.recent_file_count) : (i += 1) {
        if (std.mem.eql(u8, model.recent_files[i][0..model.recent_file_lens[i]], path)) {
            var j = i;
            while (j + 1 < model.recent_file_count) : (j += 1) {
                const len = model.recent_file_lens[j + 1];
                @memcpy(model.recent_files[j][0..len], model.recent_files[j + 1][0..len]);
                model.recent_file_lens[j] = len;
            }
            model.recent_file_count -= 1;
            break;
        }
    }
    if (model.recent_file_count >= 8) model.recent_file_count = 7;
    var k = model.recent_file_count;
    while (k > 0) : (k -= 1) {
        const len = model.recent_file_lens[k - 1];
        @memcpy(model.recent_files[k][0..len], model.recent_files[k - 1][0..len]);
        model.recent_file_lens[k] = len;
    }
    const n = @min(path.len, model.recent_files[0].len);
    @memcpy(model.recent_files[0][0..n], path[0..n]);
    model.recent_file_lens[0] = n;
    model.recent_file_count += 1;
    ensurePrefsLoaded(model);
    model.prefs.pushRecentFile(path);
    persistPrefs(model);
}

fn ensureOutlineBuffers(model: *Model) !*outline_mod.OutlineBuffers {
    if (model.outline_bufs) |o| return o;
    const o = try std.heap.page_allocator.create(outline_mod.OutlineBuffers);
    o.* = .{};
    model.outline_bufs = o;
    return o;
}

fn ensureDefBuffers(model: *Model) !*go_to_def_mod.GoToDefBuffers {
    if (model.def_bufs) |d| return d;
    const d = try std.heap.page_allocator.create(go_to_def_mod.GoToDefBuffers);
    d.* = .{};
    model.def_bufs = d;
    return d;
}

fn refreshOutline(model: *Model) void {
    const bufs = ensureOutlineBuffers(model) catch {
        model.outline_status = "alloc failed";
        model.outline_symbols = &.{};
        return;
    };
    const path = Model.activeTabPath(model);
    bufs.scan(model.document.text(), path);
    model.outline_status = bufs.status;
    filterOutlineSymbols(model);
}

fn filterOutlineSymbols(model: *Model) void {
    const bufs = model.outline_bufs orelse {
        model.outline_symbols = &.{};
        return;
    };
    // Always rescan so filtering never permanently shrinks the buffer.
    const path = Model.activeTabPath(model);
    bufs.scan(model.document.text(), path);
    model.outline_status = bufs.status;
    const q = model.symbol_query.text();
    if (q.len == 0) {
        model.outline_symbols = bufs.symbolsSlice();
        return;
    }
    var write: u32 = 0;
    var i: u32 = 0;
    const total = bufs.count;
    while (i < total) : (i += 1) {
        const sym = bufs.symbols[i];
        if (std.ascii.indexOfIgnoreCase(sym.name, q) != null) {
            bufs.symbols[write] = sym;
            bufs.symbols[write].id = write + 1;
            write += 1;
        }
    }
    bufs.count = write;
    model.outline_symbols = bufs.symbolsSlice();
}

fn runGoToDefinition(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace first";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    var symbol: []const u8 = model.find_query.text();
    if (symbol.len == 0) symbol = model.symbol_query.text();
    if (symbol.len == 0) {
        model.toast = "Enter symbol in Find then Go to Definition";
        return;
    }
    const bufs = ensureDefBuffers(model) catch {
        model.toast = "Go to Def alloc failed";
        return;
    };
    bufs.search(modelIo(model), ws, symbol);
    model.def_hits = bufs.hitsSlice();
    model.def_status = bufs.status;
    appendOutput(model, model.def_status);
    if (bufs.count == 0) {
        model.toast = "Definition not found";
        return;
    }
    openDefHit(model, bufs.hits[0].id);
}

fn openDefHit(model: *Model, hit_id: u32) void {
    if (model.def_bufs) |bufs| {
        for (bufs.hitsSlice()) |hit| {
            if (hit.id == hit_id) {
                model.selected_file_id = hit.file_id;
                model.current_view = .ide;
                model.selected_activity = .explorer;
                if (model.workspace) |ws| {
                    if (!openWorkspaceFile(model, ws, hit.file_id)) return;
                    model.active_tab_id = hit.file_id;
                    model.open_tabs = ws.tabsSlice();
                    if (ws.findNode(hit.file_id)) |node| {
                        if (!node.is_dir) {
                            model.status_language = workspace_store.scannerLanguage(node.path);
                            pushRecentFile(model, node.path);
                        }
                    }
                    syncDocumentFromWorkspace(model);
                    jumpToDocumentLine(model, hit.line);
                    model.toast = "Definition";
                }
                return;
            }
        }
    }
    model.toast = "Hit not found";
}

fn selectBreadcrumbSeg(model: *Model, seg_id: u32) void {
    for (model.breadcrumb_segs) |seg| {
        if (seg.id == seg_id) {
            if (seg.path.len == 0) {
                model.selected_activity = .explorer;
                model.show_sidebar = true;
                model.toast = "Explorer";
                return;
            }
            if (model.workspace) |ws| {
                if (ws.findNodeByPath(seg.path)) |node| {
                    model.selected_file_id = node.id;
                    model.selected_activity = .explorer;
                    model.show_sidebar = true;
                    if (node.is_dir) {
                        model.explorer_filter.clear();
                        applyExplorerFilter(model);
                        model.toast = "Folder selected";
                    } else {
                        if (!openWorkspaceFile(model, ws, node.id)) return;
                        model.active_tab_id = node.id;
                        model.open_tabs = ws.tabsSlice();
                        model.status_language = workspace_store.scannerLanguage(node.path);
                        syncDocumentFromWorkspace(model);
                        pushRecentFile(model, node.path);
                        model.toast = "Opened";
                    }
                    return;
                }
            }
            model.explorer_filter.set(seg.path);
            applyExplorerFilter(model);
            model.selected_activity = .explorer;
            model.show_sidebar = true;
            model.toast = "Filtered explorer";
            return;
        }
    }
}

fn toggleTerminalPanel(model: *Model) void {
    if (model.bottom_panel_open and model.bottom_panel_tab == .terminal) {
        model.bottom_panel_open = false;
        model.show_terminal = false;
        persistPrefs(model);
    } else {
        openBottomPanel(model, .terminal);
    }
}

fn openBottomPanel(model: *Model, tab: BottomPanelTab) void {
    model.bottom_panel_open = true;
    model.bottom_panel_tab = tab;
    model.show_terminal = tab == .terminal;
    if (tab == .problems and
        model.workspace_from_disk and
        model.problems.len == 0 and
        std.mem.eql(u8, model.problems_status, "idle"))
    {
        scanProblems(model);
    }
    persistPrefs(model);
}

fn stopTerminalTask(model: *Model, fx: ?*Effects) void {
    if (!model.terminal_async) {
        model.toast = "No terminal command or task is running";
        return;
    }
    if (model.terminal_stopping) {
        model.toast = "Stop already requested; waiting for command exit";
        return;
    }
    const effects = fx orelse {
        model.toast = "Stop is available while the async terminal is running";
        return;
    };
    effects.cancel(model.terminal_effect_key);
    model.terminal_stopping = true;
    if (model.terminal) |term| term.status = "stopping";
    if (model.task_running) model.task_status = "Stopping task";
    model.toast = "Stopping terminal command...";
}

fn runTerminalFromModel(model: *Model, fx: ?*Effects) void {
    const cmd = model.terminal_command.text();
    if (cmd.len == 0) {
        model.toast = "Enter a command";
        return;
    }
    if (model.terminal_async or (model.terminal != null and model.terminal.?.running)) {
        model.toast = "A command is already running; use Stop Terminal/Task before starting another";
        return;
    }
    const term = ensureTerminalBuffers(model) catch {
        model.toast = "Terminal alloc failed";
        return;
    };
    const cwd = if (model.workspace_from_disk) model.project_path else "";
    const process_id = model.governor.spawnEffect(
        "feature.terminal",
        cmd,
        model.terminal_effect_key,
        .{ .terminal = true, .task = model.task_running },
    ) catch {
        model.toast = "Terminal process budget is in use; stop the active command and retry";
        if (model.task_running) {
            model.task_running = false;
            model.task_status = "Task refused: process budget in use";
        }
        return;
    };
    model.terminal_process_id = process_id;
    model.process_count = model.governor.aliveCount();
    model.terminal_process_count = 1;
    model.show_terminal = true;
    openBottomPanel(model, .terminal);

    if (fx) |effects| {
        // Async path: wrap with cd when workspace is open (fx.spawn has no cwd).
        term.pushPrompt(cmd);
        term.running = true;
        term.status = "running";
        model.term_lines = term.linesSlice();
        model.terminal_async = true;
        model.terminal_stopping = false;

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
    clearActiveCommand(model, .exited, term.last_exit);
    parseTerminalDiagnostics(model, false);
    if (model.problems.len == 0) {
        model.toast = if (term.last_exit == 0) "Command ok" else "Command exited";
    }
}

fn refreshTasks(model: *Model) void {
    model.workspace_tasks = &.{};
    model.selected_task_id = 0;
    if (!model.terminal_async) model.task_running = false;
    if (!model.workspace_from_disk) {
        model.task_status = "Open a workspace to detect tasks";
        model.toast = model.task_status;
        return;
    }
    const detector = ensureTaskBuffers(model) catch {
        model.task_status = "Task detector allocation failed";
        model.toast = model.task_status;
        return;
    };
    const count = detector.discover(modelIo(model), model.project_path) catch |err| {
        detector.clear();
        model.task_status = switch (err) {
            error.FileNotFound => "No package.json tasks",
            error.PackageTooLarge => "package.json exceeds task detector limit",
            error.InvalidPackage => "package.json is invalid",
            error.TooManyTasks => "Too many npm scripts (limit 32)",
            error.NameTooLong => "An npm script name is too long",
            error.CommandTooLong => "An npm script command is too long",
            else => "Unable to detect npm scripts",
        };
        model.toast = model.task_status;
        return;
    };
    model.workspace_tasks = detector.tasksSlice();
    if (count > 0) model.selected_task_id = model.workspace_tasks[0].id;
    model.task_status = std.fmt.bufPrint(
        &model.task_status_buf,
        "{d} npm scripts detected",
        .{count},
    ) catch "Tasks detected";
    model.toast = model.task_status;
}

fn selectTask(model: *Model, task_id: u32) void {
    for (model.workspace_tasks) |task| {
        if (task.id == task_id) {
            model.selected_task_id = task_id;
            model.task_status = std.fmt.bufPrint(
                &model.task_status_buf,
                "Selected npm run {s}",
                .{task.name},
            ) catch "Task selected";
            openBottomPanel(model, .terminal);
            return;
        }
    }
    model.toast = "Workspace task not found";
}

fn appendShellQuoted(out: []u8, used: *usize, value: []const u8) bool {
    if (used.* >= out.len) return false;
    out[used.*] = '\'';
    used.* += 1;
    for (value) |byte| {
        if (byte == '\'') {
            const escaped = "'\\''";
            if (used.* + escaped.len > out.len) return false;
            @memcpy(out[used.*..][0..escaped.len], escaped);
            used.* += escaped.len;
        } else {
            if (used.* >= out.len) return false;
            out[used.*] = byte;
            used.* += 1;
        }
    }
    if (used.* >= out.len) return false;
    out[used.*] = '\'';
    used.* += 1;
    return true;
}

fn runSelectedTask(model: *Model, fx: ?*Effects) void {
    if (model.terminal_async or (model.terminal != null and model.terminal.?.running)) {
        model.toast = "A command is already running; use Stop Terminal/Task before starting another";
        openBottomPanel(model, .terminal);
        return;
    }
    if (model.workspace_tasks.len == 0) refreshTasks(model);
    var selected: ?WorkspaceTask = null;
    for (model.workspace_tasks) |task| {
        if (task.id == model.selected_task_id) {
            selected = task;
            break;
        }
    }
    const task = selected orelse {
        model.toast = "Select an npm task first";
        openBottomPanel(model, .terminal);
        return;
    };

    var command_buf: [max_terminal_command]u8 = undefined;
    const prefix = "npm run -- ";
    @memcpy(command_buf[0..prefix.len], prefix);
    var used = prefix.len;
    if (!appendShellQuoted(&command_buf, &used, task.name)) {
        model.toast = "Task name is too long to run safely";
        return;
    }
    model.terminal_command.set(command_buf[0..used]);
    model.task_running = true;
    model.task_status = std.fmt.bufPrint(
        &model.task_status_buf,
        "Running npm run {s}",
        .{task.name},
    ) catch "Task running";
    runTerminalFromModel(model, fx);
    if (fx == null) {
        model.task_running = false;
        const exit_code = if (model.terminal) |term| term.last_exit else 1;
        model.task_status = std.fmt.bufPrint(
            &model.task_status_buf,
            "Task exited with code {d}",
            .{exit_code},
        ) catch "Task finished";
    }
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
    bufs.searchWithOptions(modelIo(model), ws, model.search_query.text(), model.search_case_sensitive);
    model.search_hits = bufs.hitsSlice();
    model.governor.killFeature("feature.search");
    model.process_count = model.governor.aliveCount();
    model.toast = bufs.status;
    model.current_view = .ide;
    model.selected_activity = .search;
    model.show_sidebar = true;
}

fn invalidateWorkspaceReplace(model: *Model) void {
    if (model.workspace_replace_bufs) |workflow| workflow.clear();
    model.replace_previews = &.{};
    model.replace_status = "Preview changes before applying";
}

const ReplaceConflict = enum { none, dirty, stale };

fn matchingOpenTabConflict(model: *Model) ReplaceConflict {
    const ws = model.workspace orelse return .none;
    syncActiveTabDirty(model);
    _ = model.disk_checker.check(modelIo(model), ws, workspace_store.max_open_tabs);
    model.disk_changed = model.active_tab_id != 0 and model.disk_checker.isStale(model.active_tab_id);
    for (model.replace_previews) |preview| {
        for (ws.tabsSlice()) |tab| {
            if (!std.mem.eql(u8, preview.path, tab.path)) continue;
            if (tab.dirty) return .dirty;
            if (model.disk_checker.isStale(tab.id)) return .stale;
        }
    }
    return .none;
}

fn previewWorkspaceReplace(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace to replace";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    const needle = model.search_query.text();
    if (needle.len == 0) {
        model.toast = "Enter workspace search text";
        return;
    }
    const workflow = ensureWorkspaceReplaceBuffers(model) catch {
        model.toast = "Replace preview allocation failed";
        return;
    };
    const summary = workflow.preview(
        modelIo(model),
        ws,
        needle,
        model.replace_text.text(),
        model.search_case_sensitive,
    ) catch |err| {
        model.replace_previews = &.{};
        model.replace_status = switch (err) {
            error.EmptyNeedle => "Enter workspace search text",
            error.NeedleTooLong => "Search text exceeds replace limit",
            error.ReplacementTooLong => "Replacement text exceeds limit",
            error.TooManyFiles => "Replace preview exceeds 64 files",
            error.OutputTooLarge => "Replacement would exceed a file limit",
            else => "Workspace replace preview failed",
        };
        model.toast = model.replace_status;
        return;
    };
    model.replace_previews = workflow.previewsSlice();
    model.replace_status = std.fmt.bufPrint(
        &model.replace_status_buf,
        "Preview: {d} replacements in {d} files",
        .{ summary.replacements, summary.files },
    ) catch "Replace preview ready";
    model.current_view = .ide;
    model.selected_activity = .search;
    model.show_sidebar = true;
    model.toast = model.replace_status;
}

fn applyWorkspaceReplace(model: *Model) void {
    if (model.replace_previews.len == 0) {
        model.toast = "Preview workspace replace first";
        return;
    }
    const conflict = matchingOpenTabConflict(model);
    if (conflict != .none) {
        model.toast = switch (conflict) {
            .dirty => "Replace refused: a matching open tab has unsaved changes",
            .stale => "Replace refused: a matching open tab changed on disk",
            .none => unreachable,
        };
        return;
    }
    if (!std.mem.startsWith(u8, model.toast, "Apply workspace replace")) {
        model.toast = "Apply workspace replace? Confirm again";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    const workflow = model.workspace_replace_bufs orelse {
        model.toast = "Preview workspace replace first";
        return;
    };
    const summary = workflow.apply(
        modelIo(model),
        ws,
        model.search_query.text(),
        model.replace_text.text(),
        model.search_case_sensitive,
    ) catch {
        model.toast = "Workspace replace failed; rescan before retrying";
        return;
    };
    for (model.replace_previews) |preview| {
        reloadCleanOpenPath(model, preview.path);
    }
    invalidateWorkspaceReplace(model);
    model.selected_activity = .search;
    model.show_sidebar = true;
    runWorkspaceSearch(model);
    model.replace_status = std.fmt.bufPrint(
        &model.replace_status_buf,
        "Applied {d} replacements in {d} files",
        .{ summary.replacements, summary.files },
    ) catch "Workspace replace applied";
    model.toast = model.replace_status;
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
                        if (!openWorkspaceFile(model, ws, node.id)) return;
                        model.active_tab_id = node.id;
                        model.open_tabs = ws.tabsSlice();
                        if (!node.is_dir) {
                            model.status_language = workspace_store.scannerLanguage(node.path);
                        }
                        syncDocumentFromWorkspace(model);
                        jumpToDocumentLine(model, hit.line);
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
                model.selected_git_entry_id = entry_id;
                // Always load diff preview for the selected entry.
                bufs.loadDiff(modelIo(model), model.project_path, entry_id);
                model.git_diff_text = bufs.diffText();
                model.git_diff_status = bufs.diff_status;

                if (ws.findNodeByPath(entry.path)) |node| {
                    if (node.is_dir) {
                        model.toast = "Directory entry";
                        return;
                    }
                    model.selected_file_id = node.id;
                    model.current_view = .ide;
                    model.selected_activity = .explorer;
                    if (!openWorkspaceFile(model, ws, node.id)) return;
                    model.active_tab_id = node.id;
                    model.open_tabs = ws.tabsSlice();
                    model.status_language = workspace_store.scannerLanguage(node.path);
                    syncDocumentFromWorkspace(model);
                    model.toast = "Opened from SCM";
                    return;
                }
                model.toast = "Diff loaded (file not in scan)";
                return;
            }
        }
    }
    model.toast = "Git entry not found";
}

fn selectGitEntry(model: *Model, entry_id: u32) void {
    const bufs = model.git_bufs orelse {
        model.toast = "Refresh Git status first";
        return;
    };
    for (bufs.entriesSlice()) |entry| {
        if (entry.id != entry_id) continue;
        model.selected_git_entry_id = entry_id;
        bufs.loadDiff(modelIo(model), model.project_path, entry_id);
        model.git_diff_text = bufs.diffText();
        model.git_diff_status = bufs.diff_status;
        model.toast = bufs.diff_status;
        return;
    }
    model.toast = "Git entry not found";
}

fn gitEntryById(model: *Model, entry_id: u32) ?GitEntry {
    const bufs = model.git_bufs orelse return null;
    for (bufs.entriesSlice()) |entry| {
        if (entry.id == entry_id) return entry;
    }
    return null;
}

fn syncGitModel(model: *Model, bufs: *git_status.GitBuffers) void {
    model.git_entries = bufs.entriesSlice();
    model.git_summary = bufs.summary;
    model.git_branch = bufs.branch();
    model.git_diff_text = bufs.diffText();
    model.git_diff_status = bufs.diff_status;
    model.selected_git_entry_id = 0;
}

fn stageGitEntry(model: *Model, entry_id: u32) void {
    const entry = gitEntryById(model, entry_id) orelse {
        model.toast = "Select a Git file to stage";
        return;
    };
    const bufs = model.git_bufs.?;
    _ = model.governor.spawn("feature.scm", "git add path") catch {};
    const status = bufs.stagePath(modelIo(model), model.project_path, entry.path);
    model.governor.killFeature("feature.scm");
    model.process_count = model.governor.aliveCount();
    syncGitModel(model, bufs);
    model.toast = status;
}

fn unstageGitEntry(model: *Model, entry_id: u32) void {
    const entry = gitEntryById(model, entry_id) orelse {
        model.toast = "Select a Git file to unstage";
        return;
    };
    const bufs = model.git_bufs.?;
    _ = model.governor.spawn("feature.scm", "git reset path") catch {};
    const status = bufs.unstagePath(modelIo(model), model.project_path, entry.path);
    model.governor.killFeature("feature.scm");
    model.process_count = model.governor.aliveCount();
    syncGitModel(model, bufs);
    model.toast = status;
}

fn restoreGitEntry(model: *Model, entry_id: u32) void {
    const entry = gitEntryById(model, entry_id) orelse {
        model.toast = "Select a Git file to restore";
        return;
    };
    var restored_path_buf: [git_status.max_path]u8 = undefined;
    if (entry.path.len > restored_path_buf.len) {
        model.toast = "Restore failed: path is too long";
        return;
    }
    @memcpy(restored_path_buf[0..entry.path.len], entry.path);
    const restored_path = restored_path_buf[0..entry.path.len];
    if (entry.status.len > 0 and (entry.status[0] == '?' or (entry.status.len > 1 and entry.status[1] == '?'))) {
        model.toast = "Restore refused: untracked files are never removed";
        return;
    }
    syncActiveTabDirty(model);
    if (model.workspace) |ws| {
        for (ws.tabsSlice()) |tab| {
            if (std.mem.eql(u8, tab.path, restored_path) and tab.dirty) {
                model.toast = "Restore refused: matching open tab has unsaved changes";
                return;
            }
        }
    }
    if (!std.mem.startsWith(u8, model.toast, "Restore selected file")) {
        model.toast = "Restore selected file? Confirm again";
        return;
    }
    const bufs = model.git_bufs.?;
    _ = model.governor.spawn("feature.scm", "git checkout path") catch {};
    const status = bufs.restorePath(modelIo(model), model.project_path, restored_path);
    model.governor.killFeature("feature.scm");
    model.process_count = model.governor.aliveCount();
    syncGitModel(model, bufs);
    if (std.mem.eql(u8, status, "restored")) {
        reloadCleanOpenPath(model, restored_path);
        if (model.workspace) |ws| {
            if (ws.findNodeByPath(restored_path) == null) {
                refreshExplorer(model);
            }
        }
        model.selected_activity = .scm;
        model.show_sidebar = true;
        refreshGitStatus(model);
    }
    model.toast = status;
}

fn previewGitDiff(model: *Model, entry_id: u32) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace first";
        return;
    }
    const bufs = ensureGitBuffers(model) catch {
        model.toast = "Git alloc failed";
        return;
    };
    if (bufs.entry_count == 0) refreshGitStatus(model);
    bufs.loadDiff(modelIo(model), model.project_path, entry_id);
    model.git_diff_text = bufs.diffText();
    model.git_diff_status = bufs.diff_status;
    model.current_view = .ide;
    model.selected_activity = .scm;
    model.show_sidebar = true;
    model.toast = bufs.diff_status;
}

fn clearFind(model: *Model) void {
    model.find_query.clear();
    model.replace_text.clear();
    model.find_matches = &.{};
    model.find_active_label = "";
    model.find_status = "idle";
    model.show_find_panel = false;
    if (model.find_bufs) |f| f.clear();
    model.toast = "Find cleared";
}

fn dismissOverlay(model: *Model) void {
    if (model.symbol_palette_open) {
        model.symbol_palette_open = false;
        model.symbol_query.clear();
        model.toast = "";
        return;
    }
    if (model.shortcuts_help_visible) {
        model.shortcuts_help_visible = false;
        model.toast = "";
        return;
    }
    if (model.notifications_panel_open) {
        model.notifications_panel_open = false;
        model.toast = "";
        return;
    }
    if (model.command_palette_open) {
        model.command_palette_open = false;
        model.command_query.clear();
        model.command_items = &commands;
        model.toast = "";
        return;
    }
    if (model.quick_open_visible) {
        model.quick_open_visible = false;
        model.toast = "";
        return;
    }
    if (model.show_find_panel) {
        clearFind(model);
        return;
    }
    if (model.hasPeek()) {
        model.peek_lines = &.{};
        model.peek_count = 0;
        model.editor_focus_line = 0;
        model.editor_focus_label = "";
        model.toast = "";
        return;
    }
    if (model.focus_mode) {
        model.focus_mode = false;
        persistPrefs(model);
        model.toast = "Focus mode off";
        return;
    }
    if (model.find_query.text().len > 0 or model.find_matches.len > 0) {
        clearFind(model);
        return;
    }
    model.toast = "";
}

fn refreshWorkspaceFileCount(model: *Model) void {
    var files: u32 = 0;
    for (model.file_nodes) |n| {
        if (!n.is_dir) files += 1;
    }
    model.workspace_file_count = files;
    const label = std.fmt.bufPrint(&model.workspace_files_buf, "{d} files / {d} nodes", .{ files, model.workspace_node_count }) catch "files";
    model.workspace_files_label = label;
}

fn duplicateDocumentTail(model: *Model) void {
    const text = model.document.text();
    if (text.len == 0) {
        model.toast = "Nothing to duplicate";
        return;
    }
    // Append a blank line + copy of the last non-empty line (MVP stand-in for duplicate line).
    var last_start: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (text[i] == '\n') last_start = i + 1;
    }
    const last_line = text[last_start..];
    if (last_line.len == 0) {
        model.toast = "Empty last line";
        return;
    }
    const need = text.len + 1 + last_line.len;
    if (need > edit_transforms.max_out) {
        model.toast = "Document too large";
        return;
    }
    var out: [edit_transforms.max_out]u8 = undefined;
    @memcpy(out[0..text.len], text);
    out[text.len] = '\n';
    @memcpy(out[text.len + 1 ..][0..last_line.len], last_line);
    applyDocumentTransform(model, out[0..need], "Duplicated last line");
}

fn applyDocumentTransform(model: *Model, new_text: []const u8, ok_toast: []const u8) void {
    pushUndoSnapshot(model);
    model.document.set(new_text);
    recordUndoResult(model);
    model.document_dirty = true;
    refreshDocStats(model);
    syncActiveTabDirty(model);
    if (model.auto_save and model.workspace_from_disk) saveActiveDocument(model);
    model.toast = ok_toast;
}

fn deleteLastLine(model: *Model) void {
    var out: [edit_transforms.max_out]u8 = undefined;
    const n = edit_transforms.deleteLastLine(model.document.text(), &out) orelse {
        model.toast = "Delete line failed";
        return;
    };
    applyDocumentTransform(model, out[0..n], "Deleted last line");
}

fn joinDocumentLines(model: *Model) void {
    var out: [edit_transforms.max_out]u8 = undefined;
    const n = edit_transforms.joinLines(model.document.text(), &out) orelse {
        model.toast = "Join lines failed";
        return;
    };
    applyDocumentTransform(model, out[0..n], "Joined lines");
}

fn moveDocumentLine(model: *Model, up: bool) void {
    var out: [edit_transforms.max_out]u8 = undefined;
    const n = if (up)
        edit_transforms.moveLastLineUp(model.document.text(), &out)
    else
        edit_transforms.moveLastLineDown(model.document.text(), &out);
    const len = n orelse {
        model.toast = "Move line failed";
        return;
    };
    applyDocumentTransform(model, out[0..len], if (up) "Moved line up" else "Moved line down");
}

fn toggleLineComment(model: *Model) void {
    const path = Model.activeTabPath(model);
    var out: [edit_transforms.max_out]u8 = undefined;
    const n = edit_transforms.toggleLineComments(model.document.text(), path, &out) orelse {
        model.toast = "Comment transform failed";
        return;
    };
    applyDocumentTransform(model, out[0..n], "Toggled comments");
}

fn indentDocument(model: *Model, indent: bool) void {
    var out: [edit_transforms.max_out]u8 = undefined;
    const spaces = model.indent_size;
    const n = if (indent)
        edit_transforms.indentLines(model.document.text(), spaces, &out)
    else
        edit_transforms.outdentLines(model.document.text(), spaces, &out);
    const len = n orelse {
        model.toast = "Indent failed";
        return;
    };
    applyDocumentTransform(model, out[0..len], if (indent) "Indented" else "Outdented");
}

fn cycleIndentSize(model: *Model) void {
    model.indent_size = if (model.indent_size == 2) 4 else 2;
    persistPrefs(model);
    const msg = std.fmt.bufPrint(&model.action_toast_buf, "Indent size {d}", .{model.indent_size}) catch "Indent";
    model.toast = msg;
}

fn convertIndent(model: *Model, tabs_to_spaces: bool) void {
    var out: [edit_transforms.max_out]u8 = undefined;
    const n = if (tabs_to_spaces)
        edit_transforms.tabsToSpaces(model.document.text(), model.indent_size, &out)
    else
        edit_transforms.spacesToTabs(model.document.text(), model.indent_size, &out);
    const len = n orelse {
        model.toast = "Indent convert failed";
        return;
    };
    applyDocumentTransform(model, out[0..len], if (tabs_to_spaces) "Tabs to spaces" else "Spaces to tabs");
}

fn ensureProblemBuffers(model: *Model) !*problems_mod.ProblemBuffers {
    if (model.problem_bufs) |p| return p;
    const p = try std.heap.page_allocator.create(problems_mod.ProblemBuffers);
    p.* = .{};
    model.problem_bufs = p;
    return p;
}

fn ensureMatcherBuffers(model: *Model) !*problem_matchers.MatcherBuffers {
    if (model.matcher_bufs) |p| return p;
    const p = try std.heap.page_allocator.create(problem_matchers.MatcherBuffers);
    p.* = .{};
    model.matcher_bufs = p;
    return p;
}

fn parseTerminalDiagnostics(model: *Model, show_when_empty: bool) void {
    const term = model.terminal orelse {
        model.toast = "No terminal output";
        return;
    };
    const matcher = ensureMatcherBuffers(model) catch {
        model.toast = "Diagnostic parser alloc failed";
        return;
    };
    matcher.parseLines(term.linesSlice());
    const problems = ensureProblemBuffers(model) catch {
        model.toast = "Problems alloc failed";
        return;
    };
    problems.ingestDiagnostics(matcher.diagnosticsSlice());
    model.problems = problems.itemsSlice();
    model.problems_status = problems.status;
    appendOutput(model, problems.status);
    if (problems.item_count > 0) {
        openBottomPanel(model, .problems);
        model.toast = problems.status;
    } else if (show_when_empty) {
        openBottomPanel(model, .problems);
        model.toast = "No terminal diagnostics";
    }
}

fn scanProblems(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace to scan";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    const bufs = ensureProblemBuffers(model) catch {
        model.toast = "Problems alloc failed";
        return;
    };
    bufs.scan(modelIo(model), ws);
    model.problems = bufs.itemsSlice();
    model.problems_status = bufs.status;
    model.current_view = .ide;
    openBottomPanel(model, .problems);
    model.toast = bufs.status;
}

fn openProblem(model: *Model, problem_id: u32) void {
    if (model.problem_bufs) |bufs| {
        for (bufs.itemsSlice()) |item| {
            if (item.id == problem_id) {
                if (model.workspace) |ws| {
                    if (ws.findNodeByPath(item.path)) |node| {
                        model.selected_file_id = node.id;
                        model.current_view = .ide;
                        model.selected_activity = .explorer;
                        if (!openWorkspaceFile(model, ws, node.id)) return;
                        model.active_tab_id = node.id;
                        model.open_tabs = ws.tabsSlice();
                        model.status_language = workspace_store.scannerLanguage(node.path);
                        syncDocumentFromWorkspace(model);
                        jumpToDocumentLine(model, item.line);
                        return;
                    }
                }
            }
        }
    }
    model.toast = "Problem not found";
}

fn terminalHistory(model: *Model, older: bool) void {
    const term = ensureTerminalBuffers(model) catch {
        model.toast = "Terminal alloc failed";
        return;
    };
    const recalled = if (older) term.historyOlder() else term.historyNewer();
    if (recalled) |cmd| {
        model.terminal_command.set(cmd);
        model.toast = if (cmd.len == 0) "History end" else "History";
    } else {
        model.toast = "No history";
    }
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
    syncActiveTabDirty(model);
    const id = ws.createFile(modelIo(model), rel, "") catch {
        model.toast = "Create file failed";
        return;
    };
    model.file_nodes = ws.fileNodesSlice();
    model.open_tabs = ws.tabsSlice();
    model.workspace_node_count = ws.file_node_count;
    refreshWorkspaceFileCount(model);
    applyExplorerFilter(model);
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
    const node = ws.findNode(id) orelse {
        model.toast = "No file selected";
        return;
    };
    if (!std.mem.startsWith(u8, model.toast, "Delete ")) {
        const msg = std.fmt.bufPrint(&model.action_toast_buf, "Delete {s}? Del again to confirm", .{node.name}) catch "Delete again to confirm";
        model.toast = msg;
        return;
    }
    syncActiveTabDirty(model);
    const delete_result = if (node.is_dir)
        ws.deleteEmptyFolderById(modelIo(model), id)
    else
        ws.deleteFileById(modelIo(model), id);
    delete_result catch {
        model.toast = "Delete failed";
        return;
    };
    model.file_nodes = ws.fileNodesSlice();
    model.open_tabs = ws.tabsSlice();
    model.workspace_node_count = ws.file_node_count;
    refreshWorkspaceFileCount(model);
    applyExplorerFilter(model);
    if (ws.tab_count > 0) {
        const next_id = if (ws.findNodeByPath(ws.editorPath())) |active_node|
            active_node.id
        else
            ws.tabs[0].id;
        model.active_tab_id = next_id;
        model.selected_file_id = next_id;
        ws.openFileById(modelIo(model), next_id) catch {};
        model.status_language = workspace_store.scannerLanguage(ws.editorPath());
        syncDocumentFromWorkspace(model);
    } else {
        model.document.clear();
        model.document_dirty = false;
        model.selected_file_id = 0;
        model.active_tab_id = 0;
    }
    model.toast = if (node.is_dir) "Folder deleted" else "File deleted";
}

fn revealInExplorer(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace first";
        return;
    }
    const path = Model.activeTabPath(model);
    if (path.len == 0) {
        model.toast = "No active file";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    if (ws.findNodeByPath(path)) |node| {
        model.selected_file_id = node.id;
        model.current_view = .ide;
        model.selected_activity = .explorer;
        model.explorer_filter.clear();
        applyExplorerFilter(model);
        model.toast = "Revealed in explorer";
        return;
    }
    model.toast = "Not in explorer";
}

pub fn applyExplorerFilter(model: *Model) void {
    const query = model.explorer_filter.text();
    if (query.len == 0) {
        // Keep full tree slice from workspace / mock.
        if (model.workspace_from_disk) {
            if (model.workspace) |ws| model.file_nodes = ws.fileNodesSlice();
        } else {
            model.file_nodes = &file_tree;
        }
        return;
    }
    var count: u32 = 0;
    const source: []const FileNode = if (model.workspace_from_disk)
        if (model.workspace) |ws| ws.fileNodesSlice() else model.file_nodes
    else
        &file_tree;
    for (source) |n| {
        if (count >= model.explorer_filtered.len) break;
        if (std.ascii.indexOfIgnoreCase(n.name, query) != null or std.ascii.indexOfIgnoreCase(n.path, query) != null) {
            model.explorer_filtered[count] = workspace_store.decorateFileNode(n);
            count += 1;
        }
    }
    model.explorer_filtered_count = count;
    model.file_nodes = model.explorer_filtered[0..count];
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
    syncActiveTabDirty(model);
    const id = ws.renameFileById(modelIo(model), model.selected_file_id, new_rel) catch {
        model.toast = "Rename failed";
        return;
    };
    model.file_nodes = ws.fileNodesSlice();
    model.open_tabs = ws.tabsSlice();
    model.workspace_node_count = ws.file_node_count;
    refreshWorkspaceFileCount(model);
    applyExplorerFilter(model);
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
    model.show_find_panel = true;
    const bufs = ensureFindBuffers(model) catch {
        model.toast = "Find alloc failed";
        return;
    };
    if (model.find_query.text().len == 0) {
        model.toast = "Find";
        return;
    }
    bufs.findWithFullOptions(model.document.text(), model.find_query.text(), model.find_case_sensitive, model.find_whole_word);
    model.find_matches = bufs.matchesSlice();
    model.find_status = bufs.status;
    updateFindLabel(model);
    if (bufs.match_count == 0) {
        model.toast = bufs.status;
    } else {
        const msg = std.fmt.bufPrint(&model.action_toast_buf, "{d} matches", .{bufs.match_count}) catch "matches";
        model.toast = msg;
        if (bufs.activeMatch()) |match| jumpToDocumentLine(model, match.line);
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

fn toggleFindWholeWord(model: *Model) void {
    model.find_whole_word = !model.find_whole_word;
    persistPrefs(model);
    if (model.find_query.text().len > 0) {
        runFindInDocument(model);
    } else {
        model.toast = if (model.find_whole_word) "Find: whole word" else "Find: substring";
    }
}

fn toggleSearchCase(model: *Model) void {
    model.search_case_sensitive = !model.search_case_sensitive;
    persistPrefs(model);
    model.toast = if (model.search_case_sensitive) "Search: case sensitive" else "Search: ignore case";
}

fn toggleSidebar(model: *Model) void {
    model.show_sidebar = !model.show_sidebar;
    persistPrefs(model);
    if (model.show_sidebar and model.current_view == .ide) {
        model.selected_activity = .explorer;
    }
    model.toast = if (model.show_sidebar) "Sidebar shown" else "Sidebar hidden";
}

fn insertTimestamp(model: *Model) void {
    var stamp: [32]u8 = undefined;
    const now_secs = std.Io.Clock.real.now(modelIo(model)).toSeconds();
    const n = edit_transforms.formatTimestamp(now_secs, &stamp) orelse {
        model.toast = "Timestamp failed";
        return;
    };
    const text = model.document.text();
    if (text.len + n > edit_transforms.max_out) {
        model.toast = "Document too large";
        return;
    }
    var out: [edit_transforms.max_out]u8 = undefined;
    @memcpy(out[0..text.len], text);
    @memcpy(out[text.len..][0..n], stamp[0..n]);
    applyDocumentTransform(model, out[0 .. text.len + n], "Inserted timestamp");
}

fn convertLineEndings(model: *Model, to_lf: bool) void {
    var out: [edit_transforms.max_out]u8 = undefined;
    const n = if (to_lf)
        edit_transforms.crlfToLf(model.document.text(), &out)
    else
        edit_transforms.lfToCrlf(model.document.text(), &out);
    const len = n orelse {
        model.toast = "EOL convert failed";
        return;
    };
    applyDocumentTransform(model, out[0..len], if (to_lf) "Converted to LF" else "Converted to CRLF");
}

fn duplicateSelectedFile(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace first";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    const id = model.selected_file_id;
    const node = ws.findNode(id) orelse {
        model.toast = "No file selected";
        return;
    };
    if (node.is_dir) {
        model.toast = "Cannot duplicate directories yet";
        return;
    }
    var path_buf: [260]u8 = undefined;
    const n = edit_transforms.duplicatePathName(node.path, &path_buf) orelse {
        model.toast = "Duplicate path failed";
        return;
    };
    const seed = if (model.active_tab_id == id) model.document.text() else "";
    // Prefer disk contents when not the active dirty buffer.
    const new_id = blk: {
        if (model.active_tab_id == id) {
            break :blk ws.createFile(modelIo(model), path_buf[0..n], seed) catch {
                model.toast = "Duplicate failed";
                return;
            };
        }
        // Read via open then create with current editor text of that file.
        if (!openWorkspaceFile(model, ws, id)) return;
        const body = ws.editorText();
        break :blk ws.createFile(modelIo(model), path_buf[0..n], body) catch {
            model.toast = "Duplicate failed";
            return;
        };
    };
    model.file_nodes = ws.fileNodesSlice();
    model.open_tabs = ws.tabsSlice();
    model.workspace_node_count = ws.file_node_count;
    refreshWorkspaceFileCount(model);
    applyExplorerFilter(model);
    model.selected_file_id = new_id;
    model.active_tab_id = new_id;
    model.status_language = workspace_store.scannerLanguage(path_buf[0..n]);
    syncDocumentFromWorkspace(model);
    model.toast = "File duplicated";
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
    if (bufs.activeMatch()) |match| jumpToDocumentLine(model, match.line);
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
    const q = model.quick_query.text();
    if (q.len == 0 and model.recent_file_count > 0) {
        // Prefer recent files when query empty.
        bufs.clear();
        var i: u32 = 0;
        while (i < model.recent_file_count and bufs.item_count < quick_open.max_results) : (i += 1) {
            const path = model.recent_files[i][0..model.recent_file_lens[i]];
            if (ws.findNodeByPath(path)) |node| {
                if (!node.is_dir) bufs.push(node.id, node.name, node.path);
            }
        }
        if (bufs.item_count > 0) {
            bufs.status = "recent";
            model.quick_items = bufs.itemsSlice();
            return;
        }
    }
    bufs.filter(ws, q);
    model.quick_items = bufs.itemsSlice();
}

fn openQuickItem(model: *Model, item_id: u32) void {
    if (model.quick_bufs) |bufs| {
        for (bufs.itemsSlice()) |item| {
            if (item.id == item_id) {
                model.quick_open_visible = false;
                model.selected_file_id = item.file_id;
                model.current_view = .ide;
                model.selected_activity = .explorer;
                if (model.workspace) |ws| {
                    if (!openWorkspaceFile(model, ws, item.file_id)) return;
                    model.active_tab_id = item.file_id;
                    model.open_tabs = ws.tabsSlice();
                    if (ws.findNode(item.file_id)) |node| {
                        if (!node.is_dir) {
                            model.status_language = workspace_store.scannerLanguage(node.path);
                            pushRecentFile(model, node.path);
                        }
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
    if (model.pinned_tab_id != 0 and model.pinned_tab_id == model.active_tab_id) {
        model.toast = "Unpin tab before closing";
        return;
    }
    closeTabById(model, model.active_tab_id);
}

fn closeOtherTabs(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace first";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    const keep = model.active_tab_id;
    var has_dirty = false;
    for (ws.tabsSlice()) |tab| {
        if (tab.id != keep and tab.dirty) {
            has_dirty = true;
            break;
        }
    }
    if (has_dirty and !std.mem.startsWith(u8, model.toast, "Close other tabs")) {
        model.toast = "Close other tabs? Confirm again to discard dirty";
        return;
    }
    // Collect ids to close (copy first — close mutates tabs).
    var to_close: [8]u32 = undefined;
    var n: u32 = 0;
    for (ws.tabsSlice()) |tab| {
        if (tab.id == keep) continue;
        if (model.pinned_tab_id != 0 and tab.id == model.pinned_tab_id) continue;
        if (n >= to_close.len) break;
        to_close[n] = tab.id;
        n += 1;
    }
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        // Remember + close
        const id = to_close[i];
        if (ws.findNode(id)) |node| {
            pushClosedTab(model, node.path, scannerBaseName(node.path));
        } else {
            for (ws.tabsSlice()) |tab| {
                if (tab.id == id) {
                    pushClosedTab(model, tab.path, tab.title);
                    break;
                }
            }
        }
        ws.closeTab(id);
    }
    model.open_tabs = ws.tabsSlice();
    model.active_tab_id = keep;
    model.selected_file_id = keep;
    ws.openFileById(modelIo(model), keep) catch {};
    syncDocumentFromWorkspace(model);
    model.toast = "Closed other tabs";
}

fn closeAllTabs(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace first";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    var has_dirty = model.document_dirty;
    if (!has_dirty) {
        for (ws.tabsSlice()) |tab| {
            if (tab.dirty) {
                has_dirty = true;
                break;
            }
        }
    }
    if (has_dirty) {
        if (!std.mem.startsWith(u8, model.toast, "Close all")) {
            model.toast = "Close all? Confirm again to discard dirty";
            return;
        }
        model.document_dirty = false;
    }
    var to_close: [8]u32 = undefined;
    var n: u32 = 0;
    for (ws.tabsSlice()) |tab| {
        if (model.pinned_tab_id != 0 and tab.id == model.pinned_tab_id) continue;
        if (n >= to_close.len) break;
        to_close[n] = tab.id;
        n += 1;
    }
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const id = to_close[i];
        if (ws.findNode(id)) |node| {
            pushClosedTab(model, node.path, scannerBaseName(node.path));
        } else {
            for (ws.tabsSlice()) |tab| {
                if (tab.id == id) {
                    pushClosedTab(model, tab.path, tab.title);
                    break;
                }
            }
        }
        ws.closeTab(id);
    }
    model.open_tabs = ws.tabsSlice();
    if (ws.tab_count > 0) {
        model.active_tab_id = ws.tabs[0].id;
        model.selected_file_id = model.active_tab_id;
        ws.openFileById(modelIo(model), model.active_tab_id) catch {};
        syncDocumentFromWorkspace(model);
    } else {
        model.document.clear();
        model.active_tab_id = 0;
        model.selected_file_id = 0;
        model.pinned_tab_id = 0;
    }
    model.toast = "Closed all tabs";
}

fn pinActiveTab(model: *Model) void {
    if (model.active_tab_id == 0) {
        model.toast = "No active tab";
        return;
    }
    if (model.pinned_tab_id == model.active_tab_id) {
        model.pinned_tab_id = 0;
        model.toast = "Tab unpinned";
    } else {
        model.pinned_tab_id = model.active_tab_id;
        model.toast = "Tab pinned";
    }
}

fn toggleFocusMode(model: *Model) void {
    model.focus_mode = !model.focus_mode;
    if (model.focus_mode) {
        model.current_view = .ide;
        model.toast = "Focus mode on";
    } else {
        model.toast = "Focus mode off";
    }
    persistPrefs(model);
}

const TextTransformKind = enum { upper, lower, title, sort, reverse, sort_unique };

fn runTextTransform(model: *Model, kind: TextTransformKind) void {
    var out: [edit_transforms.max_out]u8 = undefined;
    const text = model.document.text();
    const n = switch (kind) {
        .upper => edit_transforms.toUpperCase(text, &out),
        .lower => edit_transforms.toLowerCase(text, &out),
        .title => edit_transforms.toTitleCase(text, &out),
        .sort => edit_transforms.sortLines(text, &out),
        .reverse => edit_transforms.reverseLines(text, &out),
        .sort_unique => edit_transforms.sortUniqueLines(text, &out),
    } orelse {
        model.toast = "Transform failed";
        return;
    };
    const toast: []const u8 = switch (kind) {
        .upper => "Uppercased",
        .lower => "Lowercased",
        .title => "Title cased",
        .sort => "Sorted lines",
        .reverse => "Reversed lines",
        .sort_unique => "Sorted unique lines",
    };
    applyDocumentTransform(model, out[0..n], toast);
}

fn collapseBlankLines(model: *Model) void {
    var out: [edit_transforms.max_out]u8 = undefined;
    const n = edit_transforms.collapseBlankLines(model.document.text(), &out) orelse {
        model.toast = "Collapse blank lines failed";
        return;
    };
    applyDocumentTransform(model, out[0..n], "Collapsed blank lines");
}

fn trimBlankLines(model: *Model) void {
    var out: [edit_transforms.max_out]u8 = undefined;
    const n = edit_transforms.trimBlankLines(model.document.text(), &out) orelse {
        model.toast = "Trim blank lines failed";
        return;
    };
    applyDocumentTransform(model, out[0..n], "Trimmed blank lines");
}

fn stageAllChanges(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace for git";
        return;
    }
    const bufs = ensureGitBuffers(model) catch {
        model.toast = "Git alloc failed";
        return;
    };
    _ = model.governor.spawn("feature.scm", "git add") catch {};
    const status = bufs.stageAll(modelIo(model), model.project_path);
    model.git_entries = bufs.entriesSlice();
    model.git_summary = bufs.summary;
    model.git_branch = bufs.branch();
    model.governor.killFeature("feature.scm");
    model.process_count = model.governor.aliveCount();
    model.current_view = .ide;
    model.selected_activity = .scm;
    model.show_sidebar = true;
    model.toast = status;
}

fn commitChanges(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace for git";
        return;
    }
    const msg = model.git_commit_message.text();
    if (msg.len == 0) {
        model.toast = "Enter a commit message";
        return;
    }
    const bufs = ensureGitBuffers(model) catch {
        model.toast = "Git alloc failed";
        return;
    };
    _ = model.governor.spawn("feature.scm", "git commit") catch {};
    const status = bufs.commitWithMessage(modelIo(model), model.project_path, msg);
    model.git_entries = bufs.entriesSlice();
    model.git_summary = bufs.summary;
    model.git_branch = bufs.branch();
    model.governor.killFeature("feature.scm");
    model.process_count = model.governor.aliveCount();
    model.current_view = .ide;
    model.selected_activity = .scm;
    model.show_sidebar = true;
    if (std.mem.eql(u8, status, "committed")) {
        model.git_commit_message.clear();
    }
    model.toast = status;
}

fn unstageAllChanges(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace for git";
        return;
    }
    const bufs = ensureGitBuffers(model) catch {
        model.toast = "Git alloc failed";
        return;
    };
    _ = model.governor.spawn("feature.scm", "git reset") catch {};
    const status = bufs.unstageAll(modelIo(model), model.project_path);
    model.git_entries = bufs.entriesSlice();
    model.git_summary = bufs.summary;
    model.git_branch = bufs.branch();
    model.governor.killFeature("feature.scm");
    model.process_count = model.governor.aliveCount();
    model.current_view = .ide;
    model.selected_activity = .scm;
    model.show_sidebar = true;
    model.toast = status;
}

fn discardWorkingTreeChanges(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace for git";
        return;
    }
    if (!std.mem.startsWith(u8, model.toast, "Discard")) {
        model.toast = "Discard working tree? Confirm again";
        return;
    }
    const bufs = ensureGitBuffers(model) catch {
        model.toast = "Git alloc failed";
        return;
    };
    _ = model.governor.spawn("feature.scm", "git checkout") catch {};
    const status = bufs.discardWorkingTree(modelIo(model), model.project_path);
    model.git_entries = bufs.entriesSlice();
    model.git_summary = bufs.summary;
    model.git_branch = bufs.branch();
    model.governor.killFeature("feature.scm");
    model.process_count = model.governor.aliveCount();
    model.current_view = .ide;
    model.selected_activity = .scm;
    model.show_sidebar = true;
    // Reload active editor from disk after discard when clean.
    if (std.mem.eql(u8, status, "discarded changes") and !model.document_dirty) {
        if (model.workspace) |ws| {
            if (model.active_tab_id != 0) {
                ws.reloadFileById(modelIo(model), model.active_tab_id) catch {};
                syncDocumentFromWorkspace(model);
            }
        }
    }
    model.toast = status;
}

fn refreshExplorer(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace first";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    syncActiveTabDirty(model);
    const active_path = Model.activeTabPath(model);

    const new_id = ws.rescanPreserveTabs(modelIo(model), active_path) catch {
        model.toast = "Refresh failed";
        return;
    };
    model.file_nodes = ws.fileNodesSlice();
    model.open_tabs = ws.tabsSlice();
    model.workspace_node_count = ws.file_node_count;
    refreshWorkspaceFileCount(model);
    applyExplorerFilter(model);

    if (new_id != 0) {
        model.active_tab_id = new_id;
        model.selected_file_id = new_id;
        if (ws.findNode(new_id)) |node| {
            model.status_language = workspace_store.scannerLanguage(node.path);
        }
        syncDocumentFromWorkspace(model);
    } else {
        model.document.clear();
        model.document_dirty = false;
        model.active_tab_id = 0;
        model.selected_file_id = 0;
        refreshDocStats(model);
        refreshBreadcrumb(model);
    }
    model.current_view = .ide;
    model.selected_activity = .explorer;
    refreshTasks(model);
    model.toast = "Explorer refreshed";
}

fn closeSavedTabs(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace first";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    const keep = model.active_tab_id;
    var to_close: [8]u32 = undefined;
    var n: u32 = 0;
    for (ws.tabsSlice()) |tab| {
        if (tab.id == keep) continue;
        if (model.pinned_tab_id != 0 and tab.id == model.pinned_tab_id) continue;
        // Close only clean tabs (title without " *" / dirty flag false).
        if (tab.dirty) continue;
        if (n >= to_close.len) break;
        to_close[n] = tab.id;
        n += 1;
    }
    if (n == 0) {
        model.toast = "No saved tabs to close";
        return;
    }
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const id = to_close[i];
        if (ws.findNode(id)) |node| {
            pushClosedTab(model, node.path, scannerBaseName(node.path));
        } else {
            for (ws.tabsSlice()) |tab| {
                if (tab.id == id) {
                    pushClosedTab(model, tab.path, tab.title);
                    break;
                }
            }
        }
        ws.closeTab(id);
    }
    model.open_tabs = ws.tabsSlice();
    if (keep != 0) {
        model.active_tab_id = keep;
        model.selected_file_id = keep;
        ws.openFileById(modelIo(model), keep) catch {};
        syncDocumentFromWorkspace(model);
    }
    const msg = std.fmt.bufPrint(&model.action_toast_buf, "Closed {d} saved", .{n}) catch "Closed saved tabs";
    model.toast = msg;
}

fn compareWithSaved(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace first";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    const rel = Model.activeTabPath(model);
    if (rel.len == 0) {
        model.toast = "No active file";
        return;
    }
    var disk_buf: [workspace_store.max_editor_bytes]u8 = undefined;
    const disk_len = scanner_mod.readTextFile(modelIo(model), ws.rootPath(), rel, disk_buf[0..]) catch {
        model.toast = "Read disk failed";
        return;
    };
    var status: [64]u8 = undefined;
    const n = edit_transforms.compareBuffers(model.document.text(), disk_buf[0..disk_len], &status) orelse {
        model.toast = "Compare failed";
        return;
    };
    const tn = @min(n, model.action_toast_buf.len);
    @memcpy(model.action_toast_buf[0..tn], status[0..tn]);
    model.toast = model.action_toast_buf[0..tn];
    model.disk_changed = ws.activeFileChanged(modelIo(model));
}

fn copyGitBranch(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace for git";
        return;
    }
    // Ensure branch is loaded.
    if (model.git_branch.len == 0 or std.mem.eql(u8, model.git_branch, "unknown")) {
        refreshGitStatus(model);
    }
    const branch = model.git_branch;
    if (branch.len == 0) {
        model.toast = "No branch";
        model.path_toast = "";
        return;
    }
    const n = @min(branch.len, model.path_toast_buf.len);
    @memcpy(model.path_toast_buf[0..n], branch[0..n]);
    model.path_toast = model.path_toast_buf[0..n];
    model.toast = model.path_toast;
}

fn clearRecentProjects(model: *Model) void {
    ensurePrefsLoaded(model);
    if (!std.mem.startsWith(u8, model.toast, "Clear recent")) {
        model.toast = "Clear recent projects? Confirm again";
        return;
    }
    model.prefs.clearRecent();
    persistPrefs(model);
    syncRecentFromPrefs(model);
    model.toast = "Recent projects cleared";
}

fn insertUuid(model: *Model) void {
    var id_buf: [36]u8 = undefined;
    const now_secs = std.Io.Clock.real.now(modelIo(model)).toSeconds();
    const seed: u64 = @bitCast(@as(i64, @intCast(now_secs)));
    const n = edit_transforms.formatUuid(seed, &id_buf) orelse {
        model.toast = "UUID failed";
        return;
    };
    const text = model.document.text();
    if (text.len + n > edit_transforms.max_out) {
        model.toast = "Document too large";
        return;
    }
    var out: [edit_transforms.max_out]u8 = undefined;
    @memcpy(out[0..text.len], text);
    @memcpy(out[text.len..][0..n], id_buf[0..n]);
    applyDocumentTransform(model, out[0 .. text.len + n], "Inserted UUID");
}

fn formatDocument(model: *Model) void {
    var out: [edit_transforms.max_out]u8 = undefined;
    const text = model.document.text();
    const n = edit_transforms.formatDocument(text, &out) orelse {
        model.toast = "Format failed";
        return;
    };
    if (std.mem.eql(u8, text, out[0..n])) {
        model.toast = "Already formatted";
        return;
    }
    applyDocumentTransform(model, out[0..n], "Formatted document");
}

fn hardWrapDocument(model: *Model) void {
    var out: [edit_transforms.max_out]u8 = undefined;
    const n = edit_transforms.hardWrapAt(model.document.text(), 80, &out) orelse {
        model.toast = "Hard wrap failed";
        return;
    };
    applyDocumentTransform(model, out[0..n], "Hard wrapped at 80");
}

fn copyDocument(model: *Model) void {
    const text = model.document.text();
    if (text.len == 0) {
        model.toast = "Empty document";
        model.path_toast = "";
        return;
    }
    const n = @min(text.len, model.path_toast_buf.len);
    @memcpy(model.path_toast_buf[0..n], text[0..n]);
    model.path_toast = model.path_toast_buf[0..n];
    if (text.len > model.path_toast_buf.len) {
        model.toast = "Copied (truncated)";
    } else {
        model.toast = "Copied document";
    }
}

fn goToSymbol(model: *Model) void {
    // Prefer outline scan when no find query — open symbol palette.
    if (model.find_query.text().len == 0 and model.symbol_query.text().len == 0) {
        refreshOutline(model);
        model.symbol_palette_open = true;
        model.toast = "Go to Symbol";
        return;
    }
    const query = if (model.symbol_query.text().len > 0) model.symbol_query.text() else model.find_query.text();
    refreshOutline(model);
    if (model.outline_bufs) |bufs| {
        for (bufs.symbolsSlice()) |sym| {
            if (std.ascii.indexOfIgnoreCase(sym.name, query) != null) {
                jumpToDocumentLine(model, sym.line);
                model.symbol_palette_open = false;
                model.toast = "Symbol";
                return;
            }
        }
    }
    const line = edit_transforms.findSymbolLine(model.document.text(), query) orelse {
        model.toast = "Symbol not found";
        return;
    };
    jumpToDocumentLine(model, line);
    model.symbol_palette_open = false;
}

fn createFolder(model: *Model) void {
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
        model.toast = "Enter a folder path";
        return;
    }
    syncActiveTabDirty(model);
    const id = ws.createFolder(modelIo(model), rel) catch {
        model.toast = "Create folder failed";
        return;
    };
    model.file_nodes = ws.fileNodesSlice();
    model.open_tabs = ws.tabsSlice();
    model.workspace_node_count = ws.file_node_count;
    refreshWorkspaceFileCount(model);
    applyExplorerFilter(model);
    model.selected_file_id = id;
    model.current_view = .ide;
    model.selected_activity = .explorer;
    model.toast = "Folder created";
    model.new_file_path.clear();
}

fn showFileSize(model: *Model) void {
    const text = model.document.text();
    const path = Model.activeTabPath(model);
    const name = if (path.len > 0) edit_transforms.fileNameOf(path) else "(buffer)";
    const msg = std.fmt.bufPrint(&model.action_toast_buf, "{s}: {d} bytes", .{ name, text.len }) catch "size";
    model.toast = msg;
}

fn toggleWordWrap(model: *Model) void {
    model.word_wrap = !model.word_wrap;
    persistPrefs(model);
    model.toast = if (model.word_wrap) "Word wrap on" else "Word wrap off";
}

fn copyAllTabPaths(model: *Model) void {
    const open = model.open_tabs;
    if (open.len == 0) {
        model.toast = "No open tabs";
        model.path_toast = "";
        return;
    }
    var dst: usize = 0;
    for (open, 0..) |tab, i| {
        if (i > 0) {
            if (dst + 1 > model.path_toast_buf.len) break;
            model.path_toast_buf[dst] = '\n';
            dst += 1;
        }
        const n = @min(tab.path.len, model.path_toast_buf.len - dst);
        @memcpy(model.path_toast_buf[dst..][0..n], tab.path[0..n]);
        dst += n;
    }
    model.path_toast = model.path_toast_buf[0..dst];
    model.toast = model.path_toast;
}

fn newUntitledBuffer(model: *Model) void {
    if (!model.workspace_from_disk) {
        // Scratch mode: just clear into a fresh buffer.
        model.document.clear();
        model.document_dirty = false;
        resetUndoHistory(model);
        model.editor_mode_label = "untitled";
        model.breadcrumb = "Untitled";
        refreshDocStats(model);
        model.toast = "Untitled buffer";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    var path_buf: [64]u8 = undefined;
    const rel = std.fmt.bufPrint(&path_buf, "Untitled-{d}.txt", .{model.untitled_seq}) catch {
        model.toast = "Untitled path failed";
        return;
    };
    model.untitled_seq += 1;
    const id = ws.createFile(modelIo(model), rel, "") catch {
        model.toast = "Create untitled failed";
        return;
    };
    model.file_nodes = ws.fileNodesSlice();
    model.open_tabs = ws.tabsSlice();
    model.workspace_node_count = ws.file_node_count;
    refreshWorkspaceFileCount(model);
    applyExplorerFilter(model);
    model.selected_file_id = id;
    model.active_tab_id = id;
    model.status_language = "Plain Text";
    syncDocumentFromWorkspace(model);
    model.current_view = .ide;
    model.selected_activity = .explorer;
    model.toast = "Untitled created";
}

fn toggleTrimTrailing(model: *Model) void {
    model.trim_trailing_ws = !model.trim_trailing_ws;
    persistPrefs(model);
    model.toast = if (model.trim_trailing_ws) "Trim trailing WS on" else "Trim trailing WS off";
}

fn toggleFinalNewline(model: *Model) void {
    model.insert_final_newline = !model.insert_final_newline;
    persistPrefs(model);
    model.toast = if (model.insert_final_newline) "Final newline on" else "Final newline off";
}

fn closeTabById(model: *Model, id: u32) void {
    const tab_dirty = (model.document_dirty and model.active_tab_id == id) or
        (if (model.workspace) |ws| ws.tabIsDirty(id) else false);
    if (tab_dirty) {
        if (std.mem.startsWith(u8, model.toast, "Unsaved changes")) {
            if (model.active_tab_id == id) model.document_dirty = false;
            if (model.workspace) |ws| ws.setTabDirty(id, false);
            model.toast = "Discarded unsaved changes";
        } else {
            model.toast = "Unsaved changes — Save, or Close again to discard";
            return;
        }
    }
    if (model.workspace_from_disk) {
        if (model.workspace) |ws| {
            // Remember closed path for reopen.
            if (ws.findNode(id)) |node| {
                pushClosedTab(model, node.path, scannerBaseName(node.path));
            } else {
                for (ws.tabsSlice()) |tab| {
                    if (tab.id == id) {
                        pushClosedTab(model, tab.path, tab.title);
                        break;
                    }
                }
            }
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

fn scannerBaseName(path: []const u8) []const u8 {
    var i = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') return path[i + 1 ..];
    }
    return path;
}

fn pushClosedTab(model: *Model, path: []const u8, title: []const u8) void {
    if (path.len == 0) return;
    // Shift existing entries down (newest at 0).
    var i: u32 = @min(model.closed_tab_count, 7);
    while (i > 0) : (i -= 1) {
        const plen = model.closed_path_lens[i - 1];
        @memcpy(model.closed_path_pool[i][0..plen], model.closed_path_pool[i - 1][0..plen]);
        model.closed_path_lens[i] = plen;
        const tlen = model.closed_title_lens[i - 1];
        @memcpy(model.closed_title_pool[i][0..tlen], model.closed_title_pool[i - 1][0..tlen]);
        model.closed_title_lens[i] = tlen;
        model.closed_tabs[i] = .{
            .path = model.closed_path_pool[i][0..plen],
            .title = model.closed_title_pool[i][0..tlen],
        };
    }
    const pn = @min(path.len, model.closed_path_pool[0].len);
    @memcpy(model.closed_path_pool[0][0..pn], path[0..pn]);
    model.closed_path_lens[0] = pn;
    const tn = @min(title.len, model.closed_title_pool[0].len);
    @memcpy(model.closed_title_pool[0][0..tn], title[0..tn]);
    model.closed_title_lens[0] = tn;
    model.closed_tabs[0] = .{
        .path = model.closed_path_pool[0][0..pn],
        .title = model.closed_title_pool[0][0..tn],
    };
    if (model.closed_tab_count < 8) model.closed_tab_count += 1;
}

fn reopenClosedTab(model: *Model) void {
    if (model.closed_tab_count == 0) {
        model.toast = "No closed tabs";
        return;
    }
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace first";
        return;
    }
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    const path = model.closed_tabs[0].path;
    // Pop front
    var i: u32 = 0;
    while (i + 1 < model.closed_tab_count) : (i += 1) {
        const plen = model.closed_path_lens[i + 1];
        @memcpy(model.closed_path_pool[i][0..plen], model.closed_path_pool[i + 1][0..plen]);
        model.closed_path_lens[i] = plen;
        const tlen = model.closed_title_lens[i + 1];
        @memcpy(model.closed_title_pool[i][0..tlen], model.closed_title_pool[i + 1][0..tlen]);
        model.closed_title_lens[i] = tlen;
        model.closed_tabs[i] = .{
            .path = model.closed_path_pool[i][0..plen],
            .title = model.closed_title_pool[i][0..tlen],
        };
    }
    model.closed_tab_count -= 1;

    if (ws.findNodeByPath(path)) |node| {
        model.selected_file_id = node.id;
        model.current_view = .ide;
        model.selected_activity = .explorer;
        if (!openWorkspaceFile(model, ws, node.id)) return;
        model.active_tab_id = node.id;
        model.open_tabs = ws.tabsSlice();
        model.status_language = workspace_store.scannerLanguage(node.path);
        syncDocumentFromWorkspace(model);
        model.toast = "Tab reopened";
        return;
    }
    model.toast = "File gone from workspace";
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
    jumpToDocumentLine(model, line_no);
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
    model.find_whole_word = model.prefs.find_whole_word;
    model.search_case_sensitive = model.prefs.search_case_sensitive;
    model.show_sidebar = model.prefs.show_sidebar;
    model.focus_mode = model.prefs.focus_mode;
    model.bottom_panel_open = model.prefs.bottom_panel_open;
    model.bottom_panel_tab = switch (model.prefs.bottom_panel_tab) {
        .terminal => .terminal,
        .output => .output,
        .problems => .problems,
    };
    model.show_terminal = model.bottom_panel_open and model.bottom_panel_tab == .terminal;
    model.disk_poll_interval_ms = model.prefs.disk_poll_interval_ms;
    model.word_wrap = model.prefs.word_wrap;
    model.trim_trailing_ws = model.prefs.trim_trailing_ws;
    model.insert_final_newline = model.prefs.insert_final_newline;
    model.indent_size = if (model.prefs.indent_size == 4) 4 else 2;
    if (model.prefs.last_path_len > 0 and model.open_path.text().len == 0) {
        model.open_path.set(model.prefs.lastPathSlice());
    }
    model.recent_file_count = @min(model.prefs.recent_file_count, prefs_mod.max_recent_files);
    var recent_i: u32 = 0;
    while (recent_i < model.recent_file_count) : (recent_i += 1) {
        const path = model.prefs.recentFile(recent_i);
        const n = @min(path.len, model.recent_files[recent_i].len);
        @memcpy(model.recent_files[recent_i][0..n], path[0..n]);
        model.recent_file_lens[recent_i] = n;
    }
    syncRecentFromPrefs(model);
}

/// Called once from main after io is attached.
pub fn ensurePrefsOnBoot(model: *Model) void {
    applyPrefsToModel(model);
    refreshDocStats(model);
    refreshBreadcrumb(model);
    // Quiet boot: no update banner/toast until the user checks Settings → About.
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
    model.prefs.find_whole_word = model.find_whole_word;
    model.prefs.search_case_sensitive = model.search_case_sensitive;
    model.prefs.show_sidebar = model.show_sidebar;
    model.prefs.focus_mode = model.focus_mode;
    model.prefs.bottom_panel_open = model.bottom_panel_open;
    model.prefs.bottom_panel_tab = switch (model.bottom_panel_tab) {
        .terminal => .terminal,
        .output => .output,
        .problems => .problems,
    };
    model.prefs.disk_poll_interval_ms = model.disk_poll_interval_ms;
    model.prefs.word_wrap = model.word_wrap;
    model.prefs.trim_trailing_ws = model.trim_trailing_ws;
    model.prefs.insert_final_newline = model.insert_final_newline;
    model.prefs.indent_size = model.indent_size;
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
    model.git_diff_text = bufs.diffText();
    model.git_diff_status = bufs.diff_status;
    model.selected_git_entry_id = 0;
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
    model.show_perf_hud = true;
    model.current_view = .perf;
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
