//! Velocity IDE application model — explicit TEA state.
//! Workspace folder open reads from disk (bounded scan). No network/plugins/secrets.

const std = @import("std");
const builtin = @import("builtin");
const native_sdk = @import("native_sdk");
const canvas = native_sdk.canvas;
const theme = @import("../theme/tokens.zig");
const workspace_store = @import("../workspace/workspace_store.zig");
const explorer_projection = @import("../workspace/explorer_projection.zig");
const workspace_search = @import("../workspace/search.zig");
const find_in_doc = @import("../workspace/find_in_doc.zig");
const quick_open = @import("../workspace/quick_open.zig");
const navigation_history = @import("../workspace/navigation_history.zig");
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
const tab_history = @import("../workspace/tab_history.zig");
const disk_sync = @import("../workspace/disk_sync.zig");
const hot_exit_store = @import("../workspace/hot_exit_store.zig");
const task_detector = @import("../workspace/task_detector.zig");
const launch_profiles = @import("../workspace/launch_profiles.zig");
const workspace_replace = @import("../workspace/workspace_replace.zig");
const command_registry = @import("../core/command_registry.zig");
const keybinding_registry = @import("../core/keybinding_registry.zig");
const feature_registry = @import("../core/feature_registry.zig");
const perf_model = @import("../perf/perf_model.zig");
const startup_timer = @import("../perf/startup_timer.zig");
const output_registry = @import("../core/output_registry.zig");
const notification_store = @import("../core/notification_store.zig");
const snippets_mod = @import("../workspace/snippets.zig");
const unified_diff = @import("../workspace/unified_diff.zig");

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
pub const LaunchProfile = launch_profiles.Profile;
pub const ReplacePreview = workspace_replace.FilePreview;

pub const PerfFrame = struct {
    timestamp_ns: u64,
    first_frame_latency_ns: u64,
    nonblank: bool,
};

pub const PerfRow = struct {
    label: []const u8 = "",
    value: []const u8 = "",
    semantics: []const u8 = "",
    available: bool = false,
    /// Honest measurement state shown as a badge next to the value.
    status_label: []const u8 = "",
};

pub const BreadcrumbSeg = struct {
    id: u32 = 0,
    label: []const u8 = "",
    path: []const u8 = "",
};

pub const OutputLine = output_registry.Line;
pub const OutputChannel = output_registry.Channel;
pub const NotificationItem = notification_store.Item;
pub const Snippet = snippets_mod.Snippet;
pub const DiffLine = unified_diff.ReviewLine;

pub const ClosedTab = struct {
    path: []const u8 = "",
    title: []const u8 = "",
};

pub const ViewKind = enum { launch, ide, plugins, settings, perf, features, processes, search, scm, debug, testing, problems };
pub const Activity = enum { explorer, search, scm, agents, terminal, plugins, settings, debug, testing, features, processes, problems, outline };
pub const BottomPanelTab = enum { terminal, output, problems };
pub const TestStatus = enum { idle, running, passed, failed, cancelled };
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

pub const CommandItem = command_registry.PaletteCommand;
pub const ShortcutHelpItem = keybinding_registry.HelpItem;

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
    close_settings,
    create_agent_task,
    update_agent_prompt: canvas.TextInputEvent,
    switch_theme,
    open_plugin_registry,
    open_settings,
    open_feature_matrix,
    open_process_governor,
    run_perf,
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
    update_search_include: canvas.TextInputEvent,
    update_search_exclude: canvas.TextInputEvent,
    run_search,
    search_debounce_timer: native_sdk.EffectTimer,
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
    toggle_new_file_field,
    create_new_file,
    delete_selected_file,
    rename_selected_file,
    reveal_in_explorer,
    toggle_explorer_folder: u32,
    collapse_all_explorer,
    expand_all_explorer,
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
    restore_backup,
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
    toggle_search_whole_word,
    navigate_back,
    navigate_forward,
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
    refresh_launch_profiles,
    select_launch_profile: u32,
    run_launch_profile,
    run_workspace_tests,
    rerun_workspace_tests,
    toggle_line_comment,
    indent_document,
    outdent_document,
    reopen_closed_tab,
    scan_problems,
    parse_terminal_diagnostics,
    open_problem: u32,
    set_problem_severity_filter: problems_mod.SeverityFilter,
    set_problem_source_filter: problems_mod.SourceFilter,
    preview_git_diff: u32,
    update_commit_message: canvas.TextInputEvent,
    stage_all,
    unstage_all,
    discard_changes,
    commit_changes,
    trim_blank_lines,
    refresh_explorer,
    refresh_disk_sync,
    cycle_disk_poll_interval,
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
    set_notification_severity_filter: notification_store.SeverityFilter,
    set_notification_source_filter: notification_store.SourceFilter,
    run_notification_action: u32,
    clear_notifications,
    update_settings_query: canvas.TextInputEvent,
    open_outline,
    select_outline_symbol: u32,
    go_to_definition,
    open_def_hit: u32,
    select_breadcrumb: u32,
    select_bottom_tab: BottomPanelTab,
    toggle_bottom_panel,
    clear_output,
    select_output_channel: OutputChannel,
    open_symbol_palette,
    close_symbol_palette,
    update_symbol_query: canvas.TextInputEvent,
    open_symbol_item: u32,
    open_snippet_picker,
    close_snippet_picker,
    update_snippet_query: canvas.TextInputEvent,
    append_snippet: u32,
    reload_snippets,
    open_scm_diff,
    open_staged_scm_diff,
    open_unstaged_scm_diff,
    close_diff_review,
    copy_diff_internal,
    terminal_line: native_sdk.EffectLine,
    terminal_exit: native_sdk.EffectExit,
    chrome_changed: native_sdk.WindowChrome,
    perf_frame: PerfFrame,
    set_appearance: native_sdk.Appearance,

    pub const view_unbound = .{
        // Commands relocated out of the editor toolbar — now reached via the
        // command palette and keyboard shortcuts, not a markup on-press.
        "save_file",
        "run_quick_open",
        "go_to_symbol",
        "open_snippet_picker",
        "chrome_changed",
        "perf_frame",
        "set_appearance",
        "toast_timer",
        "search_debounce_timer",
        "minimize_window",
        "close_window",
        "open_outline",
        "open_symbol_palette",
        "open_def_hit",
        "open_tab",
        "close_active_tab",
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
        "restore_backup",
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
pub const search_debounce_timer_key: u64 = 0x73656172_63686462;
pub const terminal_process_effect_key: u64 = 0x7465726d_696e616c;
pub const toast_auto_clear_ms: u64 = 3200;
pub const search_debounce_ms: u64 = 220;
pub const max_toast_text: usize = 520;
pub const max_settings_query = 48;

pub const Effects = native_sdk.Effects(Msg);

pub const Model = struct {
    current_view: ViewKind = .launch,
    selected_activity: Activity = .explorer,
    /// Workbench state to restore when leaving a full-page surface (Settings)
    /// via its Back button — returns the user to exactly where they were.
    settings_return_view: ViewKind = .ide,
    settings_return_activity: Activity = .explorer,
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
    output_registry: output_registry.Registry = .{},
    output_count: u32 = 0,
    output_filtered_count: u32 = 0,
    output_channel: OutputChannel = .all,
    output_task_count: u32 = 0,
    output_test_count: u32 = 0,
    output_launch_count: u32 = 0,
    output_git_count: u32 = 0,
    output_system_count: u32 = 0,
    recent_files: [8][240]u8 = undefined,
    recent_file_lens: [8]usize = [_]usize{0} ** 8,
    recent_file_count: u32 = 0,
    show_perf_hud: bool = false,
    safe_mode: bool = false,
    runtime_mode_label: []const u8 = "Core",
    features_registered: u32 = feature_registry.registered_count,
    features_loaded: u32 = feature_registry.countLoaded(&feature_registry.catalog),
    features_enabled: u32 = feature_registry.countEnabled(&feature_registry.catalog),
    process_count: u32 = 0,
    process_leaked: u32 = 0,
    terminal_process_count: u32 = 0,
    lsp_process_count: u32 = 0,
    plugin_process_count: u32 = 0,
    workspace_from_disk: bool = false,
    workspace_node_count: u32 = 0,
    workspace_file_count: u32 = 0,
    workspace_scan_error: []const u8 = "",
    workspace_scan_truncated: bool = false,
    workspace_files_label: []const u8 = "",
    workspace_files_buf: [48]u8 = undefined,
    workspace: ?*workspace_store.WorkspaceBuffers = null,
    /// Runtime Io from process.Init; tests fall back to std.testing.io.
    io: ?std.Io = null,
    hot_exit_persist_failed: bool = false,
    document: canvas.TextBuffer(max_document) = .{},
    document_dirty: bool = false,
    disk_changed: bool = false,
    /// Bounded histories keyed by open tab path.
    tab_histories: ?*tab_history.Store = null,
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
    launch_bufs: ?*launch_profiles.Registry = null,
    workspace_replace_bufs: ?*workspace_replace.WorkspaceReplace = null,
    search_query: canvas.TextBuffer(max_search_query) = .{},
    search_include: canvas.TextBuffer(workspace_search.max_path_pattern) = .{},
    search_exclude: canvas.TextBuffer(workspace_search.max_path_pattern) = .{},
    search_hits: []const SearchHit = &.{},
    search_debounce_armed: bool = false,
    workspace_tasks: []const WorkspaceTask = &.{},
    launch_profiles: []const LaunchProfile = &.{},
    replace_previews: []const ReplacePreview = &.{},
    selected_task_id: u32 = 0,
    selected_launch_profile_id: u32 = 0,
    selected_git_entry_id: u32 = 0,
    task_running: bool = false,
    task_status: []const u8 = "No tasks detected",
    test_status: TestStatus = .idle,
    test_status_label: []const u8 = "idle",
    test_running: bool = false,
    last_test_task_id: u32 = 0,
    replace_status: []const u8 = "Preview changes before applying",
    backup_restore_status: []const u8 = "",
    backup_status_buf: [160]u8 = undefined,
    backup_restore_confirm_tab_id: u32 = 0,
    backup_restore_confirm_hash: u64 = 0,
    close_other_confirm_pending: bool = false,
    close_all_confirm_pending: bool = false,
    task_status_buf: [96]u8 = undefined,
    launch_running: bool = false,
    launch_status: []const u8 = "No run profiles detected",
    launch_status_buf: [120]u8 = undefined,
    active_launch_name: []const u8 = "",
    replace_status_buf: [128]u8 = undefined,
    git_entries: []const GitEntry = &.{},
    git_summary: []const u8 = "not loaded",
    git_branch: []const u8 = "unknown",
    new_file_path: canvas.TextBuffer(max_new_file_path) = .{},
    new_file_field_visible: bool = false,
    explorer_filter: canvas.TextBuffer(64) = .{},
    explorer_collapse: explorer_projection.CollapseStore = .{},
    explorer_projection: explorer_projection.Projection = .{},
    explorer_selected_path_buf: [scanner_mod.max_rel_path_len]u8 = undefined,
    explorer_selected_path_len: u16 = 0,
    explorer_header_buf: [64]u8 = undefined,
    explorer_header_label: []const u8 = "",
    problem_bufs: ?*problems_mod.ProblemBuffers = null,
    matcher_bufs: ?*problem_matchers.MatcherBuffers = null,
    problems: []const Problem = &.{},
    problems_status: []const u8 = "idle",
    problem_severity_filter: problems_mod.SeverityFilter = .all,
    problem_source_filter: problems_mod.SourceFilter = .all,
    problem_filtered_count: u32 = 0,
    problem_total_count: u32 = 0,
    problems_filter_status_buf: [96]u8 = undefined,
    git_diff_text: []const u8 = "",
    git_diff_status: []const u8 = "—",
    diff_review: ?*unified_diff.Review = null,
    diff_lines: []const DiffLine = &.{},
    diff_review_open: bool = false,
    diff_review_title: []const u8 = "Diff Review",
    diff_review_status: []const u8 = "No diff",
    diff_review_is_scm: bool = false,
    diff_staged_available: bool = false,
    diff_unstaged_available: bool = false,
    diff_mode_staged: git_status.DiffMode = .staged,
    diff_mode_unstaged: git_status.DiffMode = .unstaged,
    closed_tabs: [8]ClosedTab = [_]ClosedTab{.{}} ** 8,
    closed_tab_count: u32 = 0,
    closed_path_pool: [8][240]u8 = undefined,
    closed_path_lens: [8]usize = [_]usize{0} ** 8,
    closed_title_pool: [8][64]u8 = undefined,
    closed_title_lens: [8]usize = [_]usize{0} ** 8,
    command_filtered: [64]CommandItem = [_]CommandItem{.{
        .id = "",
        .title = "",
        .hint = "",
        .availability = .available,
        .availability_label = "Available",
    }} ** 64,
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
    search_whole_word: bool = false,
    navigation: navigation_history.History = .{},
    navigation_replaying: bool = false,
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
    snippet_registry: ?*snippets_mod.Registry = null,
    snippets: []const Snippet = &.{},
    snippet_items: []const Snippet = &.{},
    snippet_filtered: [snippets_mod.max_snippets]Snippet = [_]Snippet{.{}} ** snippets_mod.max_snippets,
    snippet_filtered_count: u32 = 0,
    snippet_query: canvas.TextBuffer(64) = .{},
    snippet_picker_open: bool = false,
    snippet_status: []const u8 = "Snippets not loaded",
    snippet_status_buf: [128]u8 = undefined,
    user_snippets_path_buf: [512]u8 = undefined,
    user_snippets_path_len: usize = 0,
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
    notification_store: notification_store.Store = .{},
    notification_count: u32 = 0,
    notifications: []const NotificationItem = &.{},
    notifications_panel_open: bool = false,
    notification_severity_filter: notification_store.SeverityFilter = .all,
    notification_source_filter: notification_store.SourceFilter = .all,
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
    perf_timer: startup_timer.Timer = .{},
    perf_snapshot: perf_model.PerfSnapshot = .{},
    perf_rows: []const PerfRow = &.{},
    perf_row_storage: [18]PerfRow = [_]PerfRow{.{}} ** 18,
    perf_value_storage: [18][64]u8 = undefined,
    perf_value_lens: [18]usize = [_]usize{0} ** 18,
    perf_row_count: usize = 0,
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
    output_channel_all: OutputChannel = .all,
    output_channel_task: OutputChannel = .task,
    output_channel_test: OutputChannel = .@"test",
    output_channel_launch: OutputChannel = .launch,
    output_channel_git: OutputChannel = .git,
    output_channel_system: OutputChannel = .system,
    notification_severity_all: notification_store.SeverityFilter = .all,
    notification_severity_info: notification_store.SeverityFilter = .info,
    notification_severity_warning: notification_store.SeverityFilter = .warning,
    notification_severity_error: notification_store.SeverityFilter = .@"error",
    notification_source_all: notification_store.SourceFilter = .all,
    notification_source_system: notification_store.SourceFilter = .system,
    notification_source_workspace: notification_store.SourceFilter = .workspace,
    notification_source_task: notification_store.SourceFilter = .task,
    notification_source_test: notification_store.SourceFilter = .@"test",
    notification_source_launch: notification_store.SourceFilter = .launch,
    notification_source_git: notification_store.SourceFilter = .git,
    problem_severity_all: problems_mod.SeverityFilter = .all,
    problem_severity_errors: problems_mod.SeverityFilter = .errors,
    problem_severity_warnings: problems_mod.SeverityFilter = .warnings,
    problem_source_all: problems_mod.SourceFilter = .all,
    problem_source_terminal: problems_mod.SourceFilter = .terminal,
    problem_source_marker: problems_mod.SourceFilter = .marker,
    project_acme: []const u8 = "acme-dashboard",

    // Static mock collections exposed for markup `for each=...`
    file_nodes: []const FileNode = &file_tree,
    open_tabs: []const Tab = &tabs,
    tasks: []const AgentTask = &agent_tasks,
    plugins: []const PluginEntry = &plugin_registry,
    recent: []const RecentProject = &recent_projects,
    command_items: []const CommandItem = &commands,
    shortcut_help_items: []const ShortcutHelpItem = &keybinding_registry.help_items,
    term_lines: []const []const u8 = &terminal_lines,

    // Fields/fns used by update/theme/tests but not directly bound in markup.
    pub const view_unbound = .{
        "current_view",
        "selected_activity",
        "settings_return_view",
        "settings_return_activity",
        // Combined "name: value" label fns superseded by the label-left /
        // switch-or-select-right Settings rows.
        "findCaseLabel",
        "trimTrailingLabel",
        "finalNewlineLabel",
        "indentSizeLabel",
        "wordWrapLabel",
        "autoSaveLabel",
        "diskPollIntervalLabel",
        "sidebarLabel",
        "focusModeLabel",
        "terminalPanelLabel",
        "theme_preference",
        "next_task_id",
        "command_query",
        "agent_prompt",
        "appearance",
        "safe_mode",
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
        "project_name",
        "status_agent",
        "perf_timer",
        "perf_snapshot",
        "perf_row_storage",
        "perf_value_storage",
        "perf_value_lens",
        "perf_row_count",
        "show_perf_hud",
        "isIde",
        "isPerf",
        "activeTabTitle",
        "activeTabPath",
        "features_enabled",
        "showPlaceholderPanel",
        "workspace",
        "workspace_from_disk",
        "workspace_scan_error",
        "workspace_scan_truncated",
        "workspace_node_count",
        "workspace_file_count",
        "workspace_files_label",
        "workspace_files_buf",
        "io",
        "hot_exit_persist_failed",
        "document",
        "document_dirty",
        "disk_changed",
        "tab_histories",
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
        "launch_bufs",
        "workspace_replace_bufs",
        "search_query",
        "search_include",
        "search_exclude",
        "search_debounce_armed",
        "search_whole_word",
        "navigation",
        "navigation_replaying",
        "task_running",
        "task_status",
        "launch_running",
        "launch_status",
        "launch_status_buf",
        "active_launch_name",
        "test_status",
        "test_running",
        "last_test_task_id",
        "replace_status",
        "task_status_buf",
        "replace_status_buf",
        "backup_status_buf",
        "backup_restore_confirm_tab_id",
        "backup_restore_confirm_hash",
        "close_other_confirm_pending",
        "close_all_confirm_pending",
        "new_file_path",
        "explorer_filter",
        "explorer_collapse",
        "explorer_projection",
        "explorer_selected_path_buf",
        "explorer_selected_path_len",
        "explorer_header_buf",
        "explorer_header_label",
        "problem_bufs",
        "matcher_bufs",
        "problems_status",
        "problems_filter_status_buf",
        "git_diff_text",
        "diff_review",
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
        "find_whole_word",
        "search_case_sensitive",
        "indent_size",
        "pinned_tab_id",
        "show_terminal",
        "show_find_panel",
        "breadcrumb",
        "breadcrumb_buf",
        "quick_query",
        "quick_bufs",
        "snippet_registry",
        "snippets",
        "snippet_filtered",
        "snippet_filtered_count",
        "snippet_query",
        "snippet_status_buf",
        "user_snippets_path_buf",
        "user_snippets_path_len",
        "diff_mode_staged",
        "diff_mode_unstaged",
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
        "notification_store",
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
        "output_registry",
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
        return model.current_view != .launch and
            !model.diff_review_open and
            !model.snippet_picker_open;
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

    /// The HUD band renders only on the perf view so it never stacks under
    /// full-page views like Settings.
    pub fn showPerfHudPanel(model: *const Model) bool {
        return model.show_perf_hud and model.current_view == .perf;
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

    pub fn snippetQueryText(model: *const Model) []const u8 {
        return model.snippet_query.text();
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

    pub fn searchIncludeText(model: *const Model) []const u8 {
        return model.search_include.text();
    }

    pub fn searchExcludeText(model: *const Model) []const u8 {
        return model.search_exclude.text();
    }

    pub fn newFilePathText(model: *const Model) []const u8 {
        return model.new_file_path.text();
    }

    pub fn explorerFilterText(model: *const Model) []const u8 {
        return model.explorer_filter.text();
    }

    pub fn explorerHeaderLabel(model: *const Model) []const u8 {
        return if (model.explorer_header_label.len > 0) model.explorer_header_label else model.project_name;
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

    pub fn launchStatus(model: *const Model) []const u8 {
        return model.launch_status;
    }

    pub fn diskPollIntervalLabel(model: *const Model) []const u8 {
        return switch (model.disk_poll_interval_ms) {
            500 => "Files: disk poll interval 500 ms",
            1000 => "Files: disk poll interval 1000 ms",
            5000 => "Files: disk poll interval 5000 ms",
            else => "Files: disk poll interval 2000 ms",
        };
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
        return settingsSectionVisible(model, "workspace sidebar terminal agent panel auto save search match case whole word disk poll interval files reload");
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

    /// Value-only labels for the Settings select triggers (label lives to the
    /// left of the control, so the trigger shows just the current value).
    pub fn indentSizeValue(model: *const Model) []const u8 {
        return if (model.indent_size == 4) "4 spaces" else "2 spaces";
    }

    pub fn diskPollValue(model: *const Model) []const u8 {
        return switch (model.disk_poll_interval_ms) {
            500 => "500 ms",
            1000 => "1000 ms",
            5000 => "5000 ms",
            else => "2000 ms",
        };
    }

    /// Whether the integrated terminal panel is the visible bottom panel.
    pub fn terminalPanelShown(model: *const Model) bool {
        return model.bottom_panel_open and model.bottom_panel_tab == .terminal;
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

    pub fn searchWholeWordLabel(model: *const Model) []const u8 {
        return if (model.search_whole_word) "Search whole word: on" else "Search whole word: off";
    }

    pub fn navigationBackLabel(model: *const Model) []const u8 {
        return if (model.navigation.canBack()) "Navigate Back" else "Navigate Back (Unavailable)";
    }

    pub fn navigationForwardLabel(model: *const Model) []const u8 {
        return if (model.navigation.canForward()) "Navigate Forward" else "Navigate Forward (Unavailable)";
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

    pub fn documentDirty(model: *const Model) bool {
        return model.document_dirty;
    }

    pub fn showDiskConflict(model: *const Model) bool {
        return model.disk_changed and model.showIdeChrome();
    }

    pub fn showBackupRestoreStatus(model: *const Model) bool {
        return model.backup_restore_status.len > 0 and model.showIdeChrome();
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

    pub fn deinit(model: *Model) void {
        if (model.tab_histories) |store| {
            store.deinit();
            std.heap.page_allocator.destroy(store);
            model.tab_histories = null;
        }
        if (model.snippet_registry) |registry| {
            std.heap.page_allocator.destroy(registry);
            model.snippet_registry = null;
        }
        if (model.diff_review) |review| {
            std.heap.page_allocator.destroy(review);
            model.diff_review = null;
        }
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

pub const commands = command_registry.palette;

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
    const clock: native_sdk.Clock = .system;
    return initialModelAt(clock, clock.monotonicNanoseconds());
}

pub fn initialModelAt(clock: native_sdk.Clock, boot_ns: u64) Model {
    var model: Model = .{};
    model.perf_timer = startup_timer.Timer.init(clock, boot_ns);
    return model;
}

pub fn setUserSnippetsPath(model: *Model, path: []const u8) void {
    const length = @min(path.len, model.user_snippets_path_buf.len);
    @memcpy(model.user_snippets_path_buf[0..length], path[0..length]);
    model.user_snippets_path_len = length;
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
    if (model.test_running) {
        model.test_running = false;
        model.test_status = switch (status) {
            .cancelled, .killed => .cancelled,
            .exited => if (exit_code == 0) .passed else .failed,
            else => .failed,
        };
        model.test_status_label = @tagName(model.test_status);
    }
    if (model.launch_running) {
        model.launch_running = false;
        model.launch_status = switch (status) {
            .cancelled, .killed => "Launch cancelled",
            .rejected => "Launch rejected",
            .spawn_failed => "Launch spawn failed",
            .signaled => "Launch terminated by signal",
            .exited => std.fmt.bufPrint(
                &model.launch_status_buf,
                "Launch exited with code {d}",
                .{exit_code},
            ) catch "Launch exited",
            .running => "Launch running",
        };
    }
}

fn cancelOwnedEffects(model: *Model, fx: *Effects) void {
    fx.cancelTimer(disk_poll_timer_key);
    fx.cancelTimer(search_debounce_timer_key);
    model.disk_poll_armed = false;
    model.disk_poll_rejected = false;
    model.search_debounce_armed = false;
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
    model.test_running = false;
    model.launch_running = false;
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
    if ((!messageClosesWindow(msg) or model.hot_exit_persist_failed) and model.current_view != .launch) {
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
    const severity: notification_store.Severity =
        if (std.ascii.indexOfIgnoreCase(text, "failed") != null or
        std.ascii.indexOfIgnoreCase(text, "error") != null or
        std.ascii.indexOfIgnoreCase(text, "could not") != null)
            .@"error"
        else if (std.ascii.indexOfIgnoreCase(text, "changed") != null or
        std.ascii.indexOfIgnoreCase(text, "unavailable") != null or
        std.ascii.indexOfIgnoreCase(text, "refused") != null or
        std.ascii.indexOfIgnoreCase(text, "cancel") != null)
            .warning
        else
            .info;
    const source: notification_store.Source = if (model.launch_running or std.mem.startsWith(u8, text, "Launch"))
        .launch
    else if (model.test_running or std.mem.startsWith(u8, text, "Tests"))
        .@"test"
    else if (model.task_running or std.mem.startsWith(u8, text, "Task"))
        .task
    else if (std.mem.indexOf(u8, text, "Git") != null)
        .git
    else if (model.workspace_from_disk)
        .workspace
    else
        .system;
    const action: notification_store.Action =
        if (model.problems.len > 0 or std.mem.indexOf(u8, text, "diagnostic") != null)
            .open_problems
        else if (std.mem.indexOf(u8, text, "changed externally") != null or
        std.mem.indexOf(u8, text, "polling unavailable") != null)
            .reload_workspace
        else
            .none;
    model.notification_store.push(severity, source, text, action);
    syncNotificationView(model);
}

fn syncNotificationView(model: *Model) void {
    model.notifications = model.notification_store.slice();
    model.notification_count = model.notification_store.item_count;
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
    switch (msg) {
        .minimize_window => fx.minimizeWindow("main"),
        .close_window => {
            if (!model.hot_exit_persist_failed) fx.closeWindow("main");
        },
        .run_command => |id| {
            if (std.mem.eql(u8, id, "minimize_window")) fx.minimizeWindow("main");
            if (std.mem.eql(u8, id, "close_window") and !model.hot_exit_persist_failed) {
                fx.closeWindow("main");
            }
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
            model.perf_timer.requestCommandPalette();
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
                enterSettings(model);
            } else if (std.mem.eql(u8, id, "run_perf")) {
                refreshPerformanceMetrics(model);
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
            } else if (std.mem.eql(u8, id, "navigate_back")) {
                navigateHistory(model, false);
            } else if (std.mem.eql(u8, id, "navigate_forward")) {
                navigateHistory(model, true);
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
            } else if (std.mem.eql(u8, id, "restore_backup")) {
                restoreActiveBackup(model);
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
            } else if (std.mem.eql(u8, id, "toggle_search_whole_word")) {
                toggleSearchWholeWord(model);
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
            } else if (std.mem.eql(u8, id, "run_workspace_tests")) {
                runWorkspaceTests(model, fx, false);
            } else if (std.mem.eql(u8, id, "rerun_workspace_tests")) {
                runWorkspaceTests(model, fx, true);
            } else if (std.mem.eql(u8, id, "refresh_tasks")) {
                refreshTasks(model);
            } else if (std.mem.eql(u8, id, "refresh_launch_profiles")) {
                refreshLaunchProfiles(model);
            } else if (std.mem.eql(u8, id, "run_launch_profile")) {
                runLaunchProfile(model, fx);
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
            } else if (std.mem.eql(u8, id, "collapse_all_explorer")) {
                collapseAllExplorer(model);
            } else if (std.mem.eql(u8, id, "expand_all_explorer")) {
                expandAllExplorer(model);
            } else if (std.mem.eql(u8, id, "refresh_disk_sync")) {
                refreshDiskSync(model, true);
            } else if (std.mem.eql(u8, id, "cycle_disk_poll_interval")) {
                cycleDiskPollInterval(model, fx);
            } else if (std.mem.eql(u8, id, "close_saved_tabs")) {
                closeSavedTabs(model);
            } else if (std.mem.eql(u8, id, "compare_with_saved")) {
                compareWithSaved(model);
            } else if (std.mem.eql(u8, id, "append_snippet")) {
                openSnippetPicker(model);
            } else if (std.mem.eql(u8, id, "reload_snippets")) {
                reloadSnippets(model, true);
            } else if (std.mem.eql(u8, id, "open_scm_diff")) {
                openSelectedScmDiff(model, null);
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
                if (!model.bottom_panel_open and model.bottom_panel_tab == .terminal) {
                    model.perf_timer.requestTerminalPanel();
                }
                model.bottom_panel_open = !model.bottom_panel_open;
                model.show_terminal = model.bottom_panel_open and model.bottom_panel_tab == .terminal;
                persistPrefs(model);
            } else if (std.mem.eql(u8, id, "clear_output")) {
                model.output_registry.clearSelected();
                syncOutputView(model);
                model.toast = "Selected output channel cleared";
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
                _ = persistHotExit(model);
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
                parseTerminalDiagnostics(model, true, true);
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
            }
        },
        .select_activity => |activity| {
            switch (activity) {
                .plugins => {
                    model.selected_activity = activity;
                    model.current_view = .plugins;
                },
                .settings => enterSettings(model),
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
                        setExplorerSelectedPath(model, node.path);
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
        .restore_backup => restoreActiveBackup(model),
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
        .toggle_search_whole_word => toggleSearchWholeWord(model),
        .navigate_back => navigateHistory(model, false),
        .navigate_forward => navigateHistory(model, true),
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
        .open_settings => enterSettings(model),
        .close_settings => {
            model.current_view = model.settings_return_view;
            model.selected_activity = model.settings_return_activity;
        },
        .run_perf => {
            refreshPerformanceMetrics(model);
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
        },
        .edit_document => |edit| {
            refreshDiskSync(model, false);
            model.backup_restore_status = "";
            model.backup_restore_confirm_tab_id = 0;
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
            scheduleWorkspaceSearch(model, fx);
        },
        .update_search_include => |edit| {
            model.search_include.apply(edit);
            invalidateWorkspaceReplace(model);
            scheduleWorkspaceSearch(model, fx);
        },
        .update_search_exclude => |edit| {
            model.search_exclude.apply(edit);
            invalidateWorkspaceReplace(model);
            scheduleWorkspaceSearch(model, fx);
        },
        .run_search => {
            cancelSearchDebounce(model, fx);
            runWorkspaceSearch(model);
        },
        .search_debounce_timer => |timer| handleSearchDebounceTimer(model, timer),
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
        .cycle_disk_poll_interval => cycleDiskPollInterval(model, fx),
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
            if (!model.bottom_panel_open and model.bottom_panel_tab == .terminal) {
                model.perf_timer.requestTerminalPanel();
            }
            model.bottom_panel_open = !model.bottom_panel_open;
            model.show_terminal = model.bottom_panel_open and model.bottom_panel_tab == .terminal;
            persistPrefs(model);
        },
        .clear_output => {
            model.output_registry.clearSelected();
            syncOutputView(model);
            model.toast = "Selected output channel cleared";
        },
        .select_output_channel => |channel| {
            model.output_registry.select(channel);
            syncOutputView(model);
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
        .open_snippet_picker => openSnippetPicker(model),
        .close_snippet_picker => closeSnippetPicker(model),
        .update_snippet_query => |edit| {
            model.snippet_query.apply(edit);
            filterSnippets(model);
        },
        .append_snippet => |id| appendSnippet(model, id),
        .reload_snippets => reloadSnippets(model, true),
        .open_scm_diff => openSelectedScmDiff(model, null),
        .open_staged_scm_diff => openSelectedScmDiff(model, .staged),
        .open_unstaged_scm_diff => openSelectedScmDiff(model, .unstaged),
        .close_diff_review => closeDiffReview(model),
        .copy_diff_internal => copyDiffInternal(model),
        .open_git_entry => |id| openGitEntry(model, id),
        .select_git_entry => |id| selectGitEntry(model, id),
        .stage_git_entry => |id| stageGitEntry(model, id),
        .unstage_git_entry => |id| unstageGitEntry(model, id),
        .restore_git_entry => |id| restoreGitEntry(model, id),
        .clear_find => clearFind(model),
        .reopen_last_workspace => reopenLastWorkspace(model),
        .update_new_file_path => |edit| model.new_file_path.apply(edit),
        .toggle_new_file_field => model.new_file_field_visible = !model.new_file_field_visible,
        .create_new_file => {
            createNewFile(model);
            model.new_file_field_visible = false;
        },
        .delete_selected_file => deleteSelectedFile(model),
        .rename_selected_file => renameSelectedFile(model),
        .reveal_in_explorer => revealInExplorer(model),
        .toggle_explorer_folder => |id| toggleExplorerFolder(model, id),
        .collapse_all_explorer => collapseAllExplorer(model),
        .expand_all_explorer => expandAllExplorer(model),
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
        .parse_terminal_diagnostics => parseTerminalDiagnostics(model, true, true),
        .open_problem => |id| openProblem(model, id),
        .set_problem_severity_filter => |filter| setProblemFilters(model, filter, model.problem_source_filter),
        .set_problem_source_filter => |filter| setProblemFilters(model, model.problem_severity_filter, filter),
        .preview_git_diff => |id| previewGitDiff(model, id),
        .terminal_history_older => terminalHistory(model, true),
        .terminal_history_newer => terminalHistory(model, false),
        .refresh_tasks => refreshTasks(model),
        .select_task => |id| selectTask(model, id),
        .run_selected_task => runSelectedTask(model, fx),
        .refresh_launch_profiles => refreshLaunchProfiles(model),
        .select_launch_profile => |id| selectLaunchProfile(model, id),
        .run_launch_profile => runLaunchProfile(model, fx),
        .run_workspace_tests => runWorkspaceTests(model, fx, false),
        .rerun_workspace_tests => runWorkspaceTests(model, fx, true),
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
                mirrorTaskOutput(model, line.line);
            } else |_| {}
        },
        .terminal_exit => |exit| {
            if (!model.terminal_async or exit.key != model.terminal_effect_key) return;
            const was_test = model.test_running;
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
                mirrorTaskOutput(model, exit_msg);
            } else |_| {}
            clearActiveCommand(model, switch (exit.reason) {
                .exited => .exited,
                .cancelled => .cancelled,
                .rejected => .rejected,
                .signaled => .signaled,
                .spawn_failed => .spawn_failed,
            }, exit.code);
            parseTerminalDiagnostics(model, false, !was_test or exit.code != 0 or exit.reason != .exited);
            if (was_test and exit.reason == .exited and exit.code == 0) {
                openBottomPanel(model, .terminal);
            }
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
            model.perf_timer.markChromeCallback();
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
            if (model.show_perf_hud) refreshPerformanceSnapshot(model);
        },
        .perf_frame => |frame| {
            model.perf_timer.observeFrame(.{
                .timestamp_ns = frame.timestamp_ns,
                .first_frame_latency_ns = frame.first_frame_latency_ns,
                .nonblank = frame.nonblank,
            }, model.command_palette_open, model.bottom_panel_open and model.bottom_panel_tab == .terminal);
            if (model.show_perf_hud) refreshPerformanceSnapshot(model);
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
        .close_window => _ = persistHotExit(model),
        .toggle_notifications_panel => {
            model.notifications_panel_open = !model.notifications_panel_open;
        },
        .set_notification_severity_filter => |filter| {
            model.notification_store.setFilters(filter, model.notification_store.source_filter);
            model.notification_severity_filter = filter;
            syncNotificationView(model);
        },
        .set_notification_source_filter => |filter| {
            model.notification_store.setFilters(model.notification_store.severity_filter, filter);
            model.notification_source_filter = filter;
            syncNotificationView(model);
        },
        .run_notification_action => |id| runNotificationAction(model, id),
        .clear_notifications => {
            model.notification_store.clear();
            syncNotificationView(model);
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

fn cycleDiskPollInterval(model: *Model, fx: ?*Effects) void {
    var next = prefs_mod.disk_poll_intervals_ms[0];
    for (prefs_mod.disk_poll_intervals_ms, 0..) |value, index| {
        if (value != model.disk_poll_interval_ms) continue;
        next = prefs_mod.disk_poll_intervals_ms[(index + 1) % prefs_mod.disk_poll_intervals_ms.len];
        break;
    }
    model.disk_poll_interval_ms = next;
    persistPrefs(model);
    if (fx) |effects| {
        if (model.disk_poll_armed) effects.cancelTimer(disk_poll_timer_key);
        model.disk_poll_armed = false;
        model.disk_poll_rejected = false;
        reconcileDiskPoll(model, effects);
    }
    model.toast = Model.diskPollIntervalLabel(model);
}

fn runNotificationAction(model: *Model, id: u32) void {
    const item = model.notification_store.find(id) orelse return;
    switch (item.action) {
        .none => {},
        .open_problems => {
            model.current_view = .ide;
            model.selected_activity = .problems;
            openBottomPanel(model, .problems);
        },
        .reload_workspace => {
            if (!model.workspace_from_disk or model.project_path.len == 0) return;
            var path_buf: [prefs_mod.max_path]u8 = undefined;
            const len = @min(model.project_path.len, path_buf.len);
            @memcpy(path_buf[0..len], model.project_path[0..len]);
            openWorkspacePath(model, path_buf[0..len]);
        },
    }
}

fn persistHotExit(model: *Model) bool {
    model.hot_exit_persist_failed = false;
    const ws = model.workspace orelse return true;
    if (!model.workspace_from_disk or ws.rootPath().len == 0) return true;
    syncActiveTabDirty(model);
    var session_tabs: [hot_exit_store.max_tabs]hot_exit_store.TabInput = undefined;
    const count = @min(ws.tabsSlice().len, session_tabs.len);
    for (ws.tabsSlice()[0..count], 0..) |tab, index| {
        if (tab.dirty and !ws.tab_text_loaded[index]) {
            model.hot_exit_persist_failed = true;
            model.toast = "Hot-exit persistence failed; dirty tab payload was unavailable";
            return false;
        }
        session_tabs[index] = .{
            .path = tab.path,
            .dirty = tab.dirty,
            .dirty_text = if (tab.dirty)
                ws.tab_text_pool[index][0..ws.tab_text_lens[index]]
            else
                "",
        };
    }
    hot_exit_store.persist(modelIo(model), ws.rootPath(), .{
        .root = ws.rootPath(),
        .active_path = ws.editorPath(),
        .tabs = session_tabs[0..count],
    }) catch {
        model.hot_exit_persist_failed = true;
        model.toast = "Hot-exit persistence failed; session was not saved";
        return false;
    };
    return true;
}

const HotExitRestoreSummary = struct {
    restored: u32,
    skipped: u32,
};

fn restoreHotExit(model: *Model, ws: *workspace_store.WorkspaceBuffers) ?HotExitRestoreSummary {
    const state = std.heap.page_allocator.create(hot_exit_store.State) catch return null;
    defer std.heap.page_allocator.destroy(state);
    hot_exit_store.restore(modelIo(model), ws.rootPath(), state) catch return null;
    if (!std.mem.eql(u8, state.root(), ws.rootPath())) return null;

    // Preflight every candidate before touching the default tab opened with the
    // workspace. This guarantees an entirely stale session cannot blank the editor.
    var restorable_ids: [hot_exit_store.max_tabs]u32 = undefined;
    var state_indices: [hot_exit_store.max_tabs]usize = undefined;
    var restorable_count: usize = 0;
    var read_buf: [scanner_mod.max_file_bytes]u8 = undefined;
    var preflight_index: usize = 0;
    while (preflight_index < state.tab_count) : (preflight_index += 1) {
        const node = ws.findNodeByPath(state.tabPath(preflight_index)) orelse continue;
        if (node.is_dir) continue;
        _ = scanner_mod.readTextFile(
            modelIo(model),
            ws.rootPath(),
            state.tabPath(preflight_index),
            &read_buf,
        ) catch continue;
        restorable_ids[restorable_count] = node.id;
        state_indices[restorable_count] = preflight_index;
        restorable_count += 1;
    }
    if (restorable_count == 0) return null;

    while (ws.tab_count > 0) ws.closeTab(ws.tabs[0].id);
    var restored: u32 = 0;
    var i: usize = 0;
    while (i < restorable_count) : (i += 1) {
        const id = restorable_ids[i];
        const state_index = state_indices[i];
        ws.openFileById(modelIo(model), id) catch continue;
        if (state.tab_dirty[state_index]) {
            ws.cacheActiveText(state.dirtyText(state_index));
            ws.setTabDirty(id, true);
        }
        restored += 1;
    }
    if (restored == 0) return null;
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
    return .{
        .restored = restored,
        .skipped = @intCast(state.tab_count - restored),
    };
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

fn ensureSnippetRegistry(model: *Model) !*snippets_mod.Registry {
    if (model.snippet_registry) |registry| return registry;
    const registry = try std.heap.page_allocator.create(snippets_mod.Registry);
    registry.* = .{};
    model.snippet_registry = registry;
    return registry;
}

fn ensureDiffReview(model: *Model) !*unified_diff.Review {
    if (model.diff_review) |review| return review;
    const review = try std.heap.page_allocator.create(unified_diff.Review);
    review.* = .{};
    model.diff_review = review;
    return review;
}

fn ensureTaskBuffers(model: *Model) !*task_detector.TaskDetector {
    if (model.task_bufs) |tasks| return tasks;
    const tasks = try std.heap.page_allocator.create(task_detector.TaskDetector);
    tasks.* = .{};
    model.task_bufs = tasks;
    return tasks;
}

fn ensureLaunchBuffers(model: *Model) !*launch_profiles.Registry {
    if (model.launch_bufs) |profiles| return profiles;
    const profiles = try std.heap.page_allocator.create(launch_profiles.Registry);
    profiles.* = .{};
    model.launch_bufs = profiles;
    return profiles;
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
        model.backup_restore_status = "";
        model.backup_restore_confirm_tab_id = 0;
        model.document.set(ws.editorText());
        model.document_dirty = ws.activeTabDirty();
        model.disk_changed = ws.activeFileChanged(modelIo(model));
        reconcileTabHistories(model);
        _ = ensureActiveHistory(model) catch {};
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
    const history = ensureActiveHistory(model) catch return;
    _ = history.record(model.document.text()) catch {};
}

fn undoLastEdit(model: *Model) void {
    const history = activeHistory(model) orelse {
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
    const history = activeHistory(model) orelse {
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

fn historyPath(model: *const Model) []const u8 {
    const active = Model.activeTabPath(model);
    if (active.len > 0) return active;
    return if (model.workspace_from_disk) "" else "__scratch__";
}

fn ensureHistoryStore(model: *Model) !*tab_history.Store {
    if (model.tab_histories) |store| return store;
    const store = try std.heap.page_allocator.create(tab_history.Store);
    store.* = tab_history.Store.init(std.heap.page_allocator);
    model.tab_histories = store;
    return store;
}

fn ensureActiveHistory(model: *Model) !*undo_stack.UndoStack {
    const path = historyPath(model);
    if (path.len == 0) return error.NoActiveDocument;
    const store = try ensureHistoryStore(model);
    return try store.ensure(path, model.document.text(), .{
        .max_entries = 32,
        .max_bytes = max_document * 16,
    });
}

fn activeHistory(model: *Model) ?*undo_stack.UndoStack {
    const store = model.tab_histories orelse return null;
    return store.get(historyPath(model));
}

fn recordUndoResult(model: *Model) void {
    const history = ensureActiveHistory(model) catch return;
    _ = history.record(model.document.text()) catch {};
}

fn resetActiveHistory(model: *Model) void {
    const path = historyPath(model);
    if (path.len == 0) return;
    const store = ensureHistoryStore(model) catch return;
    store.remove(path);
    _ = ensureActiveHistory(model) catch {};
}

fn reconcileTabHistories(model: *Model) void {
    const store = model.tab_histories orelse return;
    if (!model.workspace_from_disk) return;
    var paths: [workspace_store.max_open_tabs][]const u8 = undefined;
    for (model.open_tabs, 0..) |tab, index| paths[index] = tab.path;
    store.retainPaths(paths[0..model.open_tabs.len]);
}

fn removeTabHistory(model: *Model, ws: *workspace_store.WorkspaceBuffers, id: u32) void {
    const store = model.tab_histories orelse return;
    for (ws.tabsSlice()) |tab| {
        if (tab.id == id) {
            store.remove(tab.path);
            return;
        }
    }
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

fn restoreActiveBackup(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.backup_restore_status = "Open a workspace first";
        model.toast = model.backup_restore_status;
        return;
    }
    const ws = model.workspace orelse {
        model.backup_restore_status = "No workspace";
        model.toast = model.backup_restore_status;
        return;
    };
    if (model.active_tab_id == 0) {
        model.backup_restore_status = "No active file";
        model.toast = model.backup_restore_status;
        return;
    }
    if (model.document_dirty or ws.tabIsDirty(model.active_tab_id)) {
        model.backup_restore_confirm_tab_id = 0;
        model.backup_restore_status = "Save or discard unsaved changes before restoring a backup";
        model.toast = model.backup_restore_status;
        return;
    }

    var preview: [workspace_store.max_editor_bytes]u8 = undefined;
    const backup_len = ws.readActiveBackup(modelIo(model), &preview) catch |err| {
        model.backup_restore_confirm_tab_id = 0;
        model.backup_restore_status = if (err == error.FileNotFound)
            "No backup exists for the active file"
        else
            "Backup could not be read";
        model.toast = model.backup_restore_status;
        return;
    };
    const preview_hash = std.hash.Wyhash.hash(0, preview[0..backup_len]);
    if (model.backup_restore_confirm_tab_id != model.active_tab_id or
        model.backup_restore_confirm_hash != preview_hash)
    {
        model.backup_restore_confirm_tab_id = model.active_tab_id;
        model.backup_restore_confirm_hash = preview_hash;
        const differs = !std.mem.eql(u8, preview[0..backup_len], model.document.text());
        model.backup_restore_status = std.fmt.bufPrint(
            &model.backup_status_buf,
            "Backup preview: {d} bytes ({s}). Restore again to confirm",
            .{ backup_len, if (differs) "different" else "matches current file" },
        ) catch "Backup preview ready. Restore again to confirm";
        model.toast = model.backup_restore_status;
        return;
    }

    ws.restoreActiveBackup(modelIo(model)) catch {
        model.backup_restore_confirm_tab_id = 0;
        model.backup_restore_status = "Backup restore failed; active file was not changed";
        model.toast = model.backup_restore_status;
        return;
    };
    model.open_tabs = ws.tabsSlice();
    model.document.set(ws.editorText());
    model.document_dirty = false;
    model.disk_changed = false;
    model.disk_checker.reset();
    ws.setTabStale(model.active_tab_id, false);
    resetActiveHistory(model);
    refreshDocStats(model);
    refreshBreadcrumb(model);
    refreshOutline(model);
    model.backup_restore_confirm_tab_id = 0;
    model.backup_restore_status = "Backup restored; disk baseline and editor cache refreshed";
    model.toast = model.backup_restore_status;
}

fn applyWorkspaceMeta(model: *Model, ws: *workspace_store.WorkspaceBuffers, meta: workspace_store.Workspace) void {
    model.workspace_from_disk = meta.from_disk;
    model.workspace_node_count = meta.node_count;
    model.workspace_scan_error = meta.scan_error;
    model.workspace_scan_truncated = meta.scan_truncated;
    model.project_name = ws.projectName();
    model.project_path = ws.rootPath();
    model.project_branch = meta.branch;
    model.explorer_collapse.clear();
    model.explorer_selected_path_len = 0;
    if (model.git_bufs) |bufs| bufs.clear();
    model.git_entries = &.{};
    model.git_summary = "not loaded";
    model.git_branch = "unknown";
    model.open_tabs = ws.tabsSlice();
    if (ws.tab_count > 0) {
        model.active_tab_id = ws.tabs[0].id;
        model.selected_file_id = ws.tabs[0].id;
        model.status_language = ws.tabs[0].language;
        setExplorerSelectedPath(model, ws.tabs[0].path);
    }
    syncDocumentFromWorkspace(model);
    refreshWorkspaceFileCount(model);
    refreshExplorerHeader(model);
    applyExplorerFilter(model);
    model.current_view = .ide;
    model.selected_activity = .explorer;
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
    if (model.tab_histories) |store| store.clear();
    model.navigation.clear();
    const meta = ws.openPath(modelIo(model), path) catch {
        model.workspace_scan_error = "Open failed";
        model.toast = "Could not open folder";
        model.current_view = .ide;
        model.selected_activity = .explorer;
        return;
    };
    applyWorkspaceMeta(model, ws, meta);
    const restored = if (meta.scan_error.len == 0) restoreHotExit(model, ws) else null;
    refreshTasks(model);
    refreshLaunchProfiles(model);
    reloadSnippets(model, false);
    if (meta.scan_error.len > 0) {
        model.toast = meta.scan_error;
    } else if (restored) |summary| {
        model.toast = if (summary.skipped == 0)
            "Hot-exit session restored"
        else
            std.fmt.bufPrint(
                &model.action_toast_buf,
                "Hot-exit restored {d}; skipped {d}",
                .{ summary.restored, summary.skipped },
            ) catch "Hot-exit session partially restored";
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
    if (!model.navigation_replaying) {
        const path = Model.activeTabPath(model);
        if (path.len > 0) {
            model.navigation.recordTransition(
                .{ .path = path, .line = currentNavigationLine(model) },
                .{ .path = path, .line = target },
            );
        }
    }
    jumpToDocumentLineUnrecorded(model, target, total);
}

fn jumpToDocumentLineUnrecorded(model: *Model, target: u32, total: u32) void {
    const label = std.fmt.bufPrint(&model.goto_line_buf, "Line {d}/{d}", .{ target, total }) catch "line";
    model.goto_line_label = label;
    model.editor_focus_line = target;
    const fl = std.fmt.bufPrint(&model.editor_focus_buf, "L{d}", .{target}) catch "L?";
    model.editor_focus_label = fl;
    refreshPeek(model);
    model.toast = model.goto_line_label;
}

fn currentNavigationLine(model: *const Model) u32 {
    return @max(model.editor_focus_line, 1);
}

fn recordCrossFileNavigation(model: *Model, from_path: []const u8, from_line: u32, to_path: []const u8, to_line: u32) void {
    if (model.navigation_replaying) return;
    model.navigation.recordTransition(
        .{ .path = from_path, .line = from_line },
        .{ .path = to_path, .line = @max(to_line, 1) },
    );
}

fn navigateHistory(model: *Model, forward: bool) void {
    const previous_cursor = model.navigation.cursor;
    const location = if (forward) model.navigation.forward() else model.navigation.back();
    const target = location orelse {
        model.toast = if (forward) "No forward navigation" else "No back navigation";
        return;
    };
    const ws = model.workspace orelse {
        model.navigation.cursor = previous_cursor;
        model.toast = "No workspace";
        return;
    };
    const node = ws.findNodeByPath(target.path) orelse {
        model.navigation.cursor = previous_cursor;
        model.toast = "Navigation target is no longer in the workspace";
        return;
    };
    model.navigation_replaying = true;
    defer model.navigation_replaying = false;
    if (!openWorkspaceFile(model, ws, node.id)) {
        model.navigation.cursor = previous_cursor;
        return;
    }
    model.selected_file_id = node.id;
    model.active_tab_id = node.id;
    model.open_tabs = ws.tabsSlice();
    model.status_language = workspace_store.scannerLanguage(node.path);
    syncDocumentFromWorkspace(model);
    jumpToDocumentLine(model, target.line);
    model.toast = if (forward) "Navigated forward" else "Navigated back";
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
    appendOutputLabeled(model, .system, "velocity", text);
}

fn appendOutputLabeled(model: *Model, channel: OutputChannel, source: []const u8, text: []const u8) void {
    model.output_registry.append(channel, source, text);
    syncOutputView(model);
}

fn syncOutputView(model: *Model) void {
    model.output_lines = model.output_registry.lines();
    model.output_count = model.output_registry.total_count;
    model.output_filtered_count = model.output_registry.filtered_count;
    model.output_channel = model.output_registry.selected;
    model.output_task_count = model.output_registry.count(.task);
    model.output_test_count = model.output_registry.count(.@"test");
    model.output_launch_count = model.output_registry.count(.launch);
    model.output_git_count = model.output_registry.count(.git);
    model.output_system_count = model.output_registry.count(.system);
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
                var from_path_buf: [scanner_mod.max_rel_path_len]u8 = undefined;
                const current_path = Model.activeTabPath(model);
                const from_path_len = @min(current_path.len, from_path_buf.len);
                @memcpy(from_path_buf[0..from_path_len], current_path[0..from_path_len]);
                const from_line = currentNavigationLine(model);
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
                    recordCrossFileNavigation(model, from_path_buf[0..from_path_len], from_line, hit.path, hit.line);
                    model.navigation_replaying = true;
                    jumpToDocumentLine(model, hit.line);
                    model.navigation_replaying = false;
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
                        var from_path_buf: [scanner_mod.max_rel_path_len]u8 = undefined;
                        const current_path = Model.activeTabPath(model);
                        const from_path_len = @min(current_path.len, from_path_buf.len);
                        @memcpy(from_path_buf[0..from_path_len], current_path[0..from_path_len]);
                        const from_line = currentNavigationLine(model);
                        if (!openWorkspaceFile(model, ws, node.id)) return;
                        model.active_tab_id = node.id;
                        model.open_tabs = ws.tabsSlice();
                        model.status_language = workspace_store.scannerLanguage(node.path);
                        syncDocumentFromWorkspace(model);
                        pushRecentFile(model, node.path);
                        recordCrossFileNavigation(model, from_path_buf[0..from_path_len], from_line, node.path, 1);
                        model.navigation_replaying = true;
                        jumpToDocumentLine(model, 1);
                        model.navigation_replaying = false;
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
        model.perf_timer.requestTerminalPanel();
        openBottomPanel(model, .terminal);
    }
}

fn openBottomPanel(model: *Model, tab: BottomPanelTab) void {
    const terminal_was_present = model.bottom_panel_open and model.bottom_panel_tab == .terminal;
    if (tab == .terminal and !terminal_was_present and model.perf_timer.terminal_pending_ns == null) {
        model.perf_timer.requestTerminalPanel();
    }
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
    runGovernedCommand(model, fx, cmd);
}

fn runGovernedCommand(model: *Model, fx: ?*Effects, cmd: []const u8) void {
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
        if (model.launch_running) "feature.terminal-profiles" else "feature.terminal",
        cmd,
        model.terminal_effect_key,
        .{ .terminal = true, .task = model.task_running or model.test_running or model.launch_running },
    ) catch {
        model.toast = "Terminal process budget is in use; stop the active command and retry";
        if (model.task_running) {
            model.task_running = false;
            model.task_status = "Task refused: process budget in use";
        }
        if (model.launch_running) {
            model.launch_running = false;
            model.launch_status = "Launch refused: process budget in use";
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

        var script_buf: [launch_profiles.max_script_len + 512]u8 = undefined;
        const script = if (cwd.len > 0) blk: {
            // Quote cwd lightly for sh -c; fixture paths are simple.
            break :blk std.fmt.bufPrint(&script_buf, "cd {s} && {s}", .{ cwd, cmd }) catch cmd;
        } else cmd;

        // Keep script alive for the spawn call (copied by effects).
        var script_owned: [launch_profiles.max_script_len + 512]u8 = undefined;
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
    const first_new_line = term.line_count;
    term.runCommand(modelIo(model), cwd, cmd);
    model.term_lines = term.linesSlice();
    for (term.linesSlice()[first_new_line..]) |line| mirrorTaskOutput(model, line);
    const was_test = model.test_running;
    clearActiveCommand(model, .exited, term.last_exit);
    parseTerminalDiagnostics(model, false, !was_test or term.last_exit != 0);
    if (was_test and term.last_exit == 0) openBottomPanel(model, .terminal);
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
            error.FileNotFound => "No supported task files",
            error.PackageTooLarge => "A task source exceeds the detector limit",
            error.InvalidPackage => "package.json is invalid",
            error.InvalidTasks => ".vscode/tasks.json is invalid",
            error.TooManyTasks => "Too many workspace tasks (limit 32)",
            error.NameTooLong => "A workspace task name is too long",
            error.CommandTooLong => "A workspace task command is too long",
            else => "Unable to detect workspace tasks",
        };
        model.toast = model.task_status;
        return;
    };
    model.workspace_tasks = detector.tasksSlice();
    if (count > 0) model.selected_task_id = model.workspace_tasks[0].id;
    model.task_status = std.fmt.bufPrint(
        &model.task_status_buf,
        "{d} workspace tasks detected",
        .{count},
    ) catch "Tasks detected";
    model.toast = model.task_status;
}

fn refreshLaunchProfiles(model: *Model) void {
    model.launch_profiles = &.{};
    model.selected_launch_profile_id = 0;
    if (!model.workspace_from_disk) {
        model.launch_status = "Open a workspace to detect run profiles";
        return;
    }
    const registry = ensureLaunchBuffers(model) catch {
        model.launch_status = "Run profile registry allocation failed";
        model.toast = model.launch_status;
        return;
    };
    const count = registry.load(modelIo(model), model.project_path) catch |err| {
        registry.clear();
        model.launch_status = switch (err) {
            error.FileNotFound => "No .velocity/launch.json",
            error.FileTooLarge => "Run profiles exceed the 16 KiB limit",
            error.UnsupportedVersion => "Unsupported run profile schema version",
            error.DebugConfigurationRejected => "Debug-shaped launch configuration rejected",
            error.UnsafeCwd => "Run profile cwd must stay inside the workspace",
            error.VariablePlaceholderRejected => "Run profile variable placeholders are not supported",
            error.TooManyProfiles => "Too many run profiles (limit 12)",
            error.TooManyEnvironmentVariables => "Too many run profile environment variables",
            error.NameTooLong, error.CommandTooLong, error.CwdTooLong, error.EnvironmentTooLong => "A run profile field exceeds its bound",
            error.InvalidJson, error.InvalidSchema => "Invalid .velocity/launch.json command profile schema",
            else => "Unable to load run profiles",
        };
        if (err != error.FileNotFound) model.toast = model.launch_status;
        return;
    };
    model.launch_profiles = registry.slice();
    if (count > 0) model.selected_launch_profile_id = model.launch_profiles[0].id;
    model.launch_status = std.fmt.bufPrint(
        &model.launch_status_buf,
        "{d} run profiles detected",
        .{count},
    ) catch "Run profiles detected";
}

fn selectLaunchProfile(model: *Model, profile_id: u32) void {
    for (model.launch_profiles) |profile| {
        if (profile.id != profile_id) continue;
        model.selected_launch_profile_id = profile.id;
        model.launch_status = std.fmt.bufPrint(
            &model.launch_status_buf,
            "Selected run profile: {s}",
            .{profile.name},
        ) catch "Run profile selected";
        openBottomPanel(model, .terminal);
        return;
    }
    model.toast = "Run profile not found";
}

fn runLaunchProfile(model: *Model, fx: ?*Effects) void {
    if (model.terminal_async or (model.terminal != null and model.terminal.?.running)) {
        model.toast = "A command is already running; use Stop Terminal/Task before starting a run profile";
        openBottomPanel(model, .terminal);
        return;
    }
    if (model.launch_profiles.len == 0) refreshLaunchProfiles(model);
    var selected: ?LaunchProfile = null;
    for (model.launch_profiles) |profile| {
        if (profile.id == model.selected_launch_profile_id) {
            selected = profile;
            break;
        }
    }
    const profile = selected orelse {
        model.toast = "Select a run profile first";
        openBottomPanel(model, .terminal);
        return;
    };
    var script_buf: [launch_profiles.max_script_len]u8 = undefined;
    const script = launch_profiles.buildScript(profile, ".", &script_buf) catch {
        model.launch_status = "Run profile command exceeds the execution bound";
        model.toast = model.launch_status;
        return;
    };
    model.active_launch_name = profile.name;
    model.launch_running = true;
    model.launch_status = std.fmt.bufPrint(
        &model.launch_status_buf,
        "Running profile: {s}",
        .{profile.name},
    ) catch "Launch running";
    runGovernedCommand(model, fx, script);
}

fn selectTask(model: *Model, task_id: u32) void {
    for (model.workspace_tasks) |task| {
        if (task.id == task_id) {
            model.selected_task_id = task_id;
            model.task_status = std.fmt.bufPrint(
                &model.task_status_buf,
                "Selected {s}: {s}",
                .{ task.source_label, task.name },
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
        model.toast = "Select a workspace task first";
        openBottomPanel(model, .terminal);
        return;
    };

    var command_buf: [max_terminal_command]u8 = undefined;
    var used: usize = 0;
    if (task.source == .npm) {
        const prefix = "npm run -- ";
        @memcpy(command_buf[0..prefix.len], prefix);
        used = prefix.len;
        if (!appendShellQuoted(&command_buf, &used, task.name)) {
            model.toast = "Task name is too long to run safely";
            return;
        }
    } else {
        used = @min(task.command.len, command_buf.len);
        @memcpy(command_buf[0..used], task.command[0..used]);
    }
    model.terminal_command.set(command_buf[0..used]);
    model.task_running = true;
    model.task_status = std.fmt.bufPrint(
        &model.task_status_buf,
        "Running {s}: {s}",
        .{ task.source_label, task.name },
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

fn runWorkspaceTests(model: *Model, fx: ?*Effects, rerun: bool) void {
    if (model.terminal_async or (model.terminal != null and model.terminal.?.running)) {
        model.toast = "A command is already running; use Stop Terminal/Task before starting tests";
        openBottomPanel(model, .terminal);
        return;
    }
    if (model.workspace_tasks.len == 0) refreshTasks(model);
    var test_task: ?WorkspaceTask = null;
    if (rerun and model.last_test_task_id != 0) {
        for (model.workspace_tasks) |task| {
            if (task.id == model.last_test_task_id) {
                test_task = task;
                break;
            }
        }
    } else {
        for (model.workspace_tasks) |task| {
            if (std.mem.eql(u8, task.name, "test")) {
                test_task = task;
                break;
            }
        }
        if (test_task == null) {
            for (model.workspace_tasks) |task| {
                if (std.mem.startsWith(u8, task.name, "test:")) {
                    test_task = task;
                    break;
                }
            }
        }
    }
    const task = test_task orelse {
        model.test_status = .idle;
        model.test_status_label = "idle · no test/test:* task";
        model.toast = if (rerun) "Previous test task is no longer available" else "No test or test:* workspace task detected";
        openBottomPanel(model, .terminal);
        return;
    };
    model.selected_task_id = task.id;
    model.last_test_task_id = task.id;
    model.test_running = true;
    model.test_status = .running;
    model.test_status_label = "running";
    runSelectedTask(model, fx);
    if (!model.task_running and !model.terminal_async and model.test_running) {
        model.test_running = false;
        model.test_status = .failed;
        model.test_status_label = "failed";
    }
}

fn mirrorTaskOutput(model: *Model, line: []const u8) void {
    if (model.launch_running) {
        appendOutputLabeled(model, .launch, model.active_launch_name, line);
        return;
    }
    if (!model.task_running and !model.test_running) return;
    for (model.workspace_tasks) |task| {
        if (task.id != model.selected_task_id) continue;
        appendOutputLabeled(
            model,
            if (model.test_running) .@"test" else .task,
            task.source_label,
            line,
        );
        return;
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
    if (std.mem.trim(u8, model.search_query.text(), " \t").len == 0) {
        bufs.clear();
        bufs.status = "empty query";
        model.search_hits = &.{};
        model.toast = "";
        return;
    }
    bufs.searchScoped(modelIo(model), ws, model.search_query.text(), workspaceSearchOptions(model));
    model.search_hits = bufs.hitsSlice();
    model.toast = bufs.status;
    model.current_view = .ide;
    model.selected_activity = .search;
    model.show_sidebar = true;
}

fn workspaceSearchOptions(model: *const Model) workspace_search.Options {
    return .{
        .case_sensitive = model.search_case_sensitive,
        .whole_word = model.search_whole_word,
        .include = model.search_include.text(),
        .exclude = model.search_exclude.text(),
    };
}

fn cancelSearchDebounce(model: *Model, fx: ?*Effects) void {
    if (fx) |effects| effects.cancelTimer(search_debounce_timer_key);
    model.search_debounce_armed = false;
}

fn scheduleWorkspaceSearch(model: *Model, fx: ?*Effects) void {
    const query = std.mem.trim(u8, model.search_query.text(), " \t");
    if (query.len == 0) {
        cancelSearchDebounce(model, fx);
        if (model.search_bufs) |bufs| {
            bufs.clear();
            bufs.status = "empty query";
        }
        model.search_hits = &.{};
        return;
    }
    const effects = fx orelse return;
    effects.cancelTimer(search_debounce_timer_key);
    model.search_debounce_armed = true;
    effects.startTimer(.{
        .key = search_debounce_timer_key,
        .interval_ms = search_debounce_ms,
        .mode = .one_shot,
        .on_fire = Effects.timerMsg(.search_debounce_timer),
    });
}

pub fn scheduleWorkspaceSearchForTest(model: *Model, fx: *Effects) void {
    scheduleWorkspaceSearch(model, fx);
}

fn handleSearchDebounceTimer(model: *Model, timer: native_sdk.EffectTimer) void {
    if (timer.key != search_debounce_timer_key) return;
    model.search_debounce_armed = false;
    switch (timer.outcome) {
        .fired => {
            if (std.mem.trim(u8, model.search_query.text(), " \t").len > 0) runWorkspaceSearch(model);
        },
        .rejected => model.toast = "Incremental search timer unavailable; press Search to run immediately",
    }
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
        workspaceSearchOptions(model),
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
        workspaceSearchOptions(model),
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
                        var from_path_buf: [scanner_mod.max_rel_path_len]u8 = undefined;
                        const current_path = Model.activeTabPath(model);
                        const from_path_len = @min(current_path.len, from_path_buf.len);
                        @memcpy(from_path_buf[0..from_path_len], current_path[0..from_path_len]);
                        const from_line = currentNavigationLine(model);
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
                        recordCrossFileNavigation(model, from_path_buf[0..from_path_len], from_line, hit.path, hit.line);
                        model.navigation_replaying = true;
                        jumpToDocumentLine(model, hit.line);
                        model.navigation_replaying = false;
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
        model.diff_staged_available = bufs.supportsMode(entry_id, .staged);
        model.diff_unstaged_available = bufs.supportsMode(entry_id, .unstaged);
        model.git_diff_status = if (model.diff_unstaged_available and model.diff_staged_available)
            "Selected · staged and unstaged changes"
        else if (model.diff_staged_available)
            "Selected · staged changes"
        else
            "Selected · unstaged changes";
        model.toast = "Git entry selected";
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
    applyExplorerFilter(model);
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
    model.selected_git_entry_id = entry_id;
    openSelectedScmDiff(model, null);
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
    if (model.diff_review_open) {
        closeDiffReview(model);
        return;
    }
    if (model.snippet_picker_open) {
        closeSnippetPicker(model);
        return;
    }
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
    model.toast = ok_toast;
    if (model.auto_save and model.workspace_from_disk) saveActiveDocument(model);
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

fn parseTerminalDiagnostics(model: *Model, show_when_empty: bool, auto_open: bool) void {
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
    syncProblemView(model, problems);
    appendOutput(model, problems.status);
    if (problems.item_count > 0 and auto_open) {
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
    syncProblemView(model, bufs);
    model.current_view = .ide;
    openBottomPanel(model, .problems);
    model.toast = bufs.status;
}

fn setProblemFilters(
    model: *Model,
    severity: problems_mod.SeverityFilter,
    source: problems_mod.SourceFilter,
) void {
    model.problem_severity_filter = severity;
    model.problem_source_filter = source;
    const bufs = model.problem_bufs orelse {
        model.problem_filtered_count = 0;
        model.problem_total_count = 0;
        return;
    };
    bufs.setFilters(severity, source);
    syncProblemView(model, bufs);
}

fn syncProblemView(model: *Model, bufs: *problems_mod.ProblemBuffers) void {
    bufs.setFilters(model.problem_severity_filter, model.problem_source_filter);
    model.problems = bufs.filteredSlice();
    model.problem_filtered_count = bufs.filtered_count;
    model.problem_total_count = bufs.item_count;
    model.problems_status = std.fmt.bufPrint(
        &model.problems_filter_status_buf,
        "{d}/{d} · {s}",
        .{ bufs.filtered_count, bufs.item_count, bufs.status },
    ) catch bufs.status;
}

fn openProblem(model: *Model, problem_id: u32) void {
    if (model.problem_bufs) |bufs| {
        for (bufs.itemsSlice()) |item| {
            if (item.id == problem_id) {
                if (model.workspace) |ws| {
                    if (ws.findNodeByPath(item.path)) |node| {
                        var from_path_buf: [scanner_mod.max_rel_path_len]u8 = undefined;
                        const current_path = Model.activeTabPath(model);
                        const from_path_len = @min(current_path.len, from_path_buf.len);
                        @memcpy(from_path_buf[0..from_path_len], current_path[0..from_path_len]);
                        const from_line = currentNavigationLine(model);
                        model.selected_file_id = node.id;
                        model.current_view = .ide;
                        model.selected_activity = .explorer;
                        if (!openWorkspaceFile(model, ws, node.id)) return;
                        model.active_tab_id = node.id;
                        model.open_tabs = ws.tabsSlice();
                        model.status_language = workspace_store.scannerLanguage(node.path);
                        syncDocumentFromWorkspace(model);
                        recordCrossFileNavigation(model, from_path_buf[0..from_path_len], from_line, item.path, item.line);
                        model.navigation_replaying = true;
                        jumpToDocumentLine(model, item.line);
                        model.navigation_replaying = false;
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
    syncExplorerScanMeta(model, ws);
    model.selected_file_id = id;
    setExplorerSelectedPath(model, rel);
    model.explorer_collapse.expandAncestors(rel);
    applyExplorerFilter(model);
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
    var confirm_buf: [128]u8 = undefined;
    const confirmation = std.fmt.bufPrint(
        &confirm_buf,
        "Delete {s} #{d}? Del again to confirm",
        .{ if (node.is_dir) "empty folder" else "file", node.id },
    ) catch "Delete selected item? Del again to confirm";
    if (!std.mem.eql(u8, model.toast, confirmation)) {
        const n = @min(confirmation.len, model.action_toast_buf.len);
        @memcpy(model.action_toast_buf[0..n], confirmation[0..n]);
        model.toast = model.action_toast_buf[0..n];
        return;
    }
    syncActiveTabDirty(model);
    const delete_result = if (node.is_dir)
        ws.deleteEmptyFolderById(modelIo(model), id)
    else
        ws.deleteFileById(modelIo(model), id);
    delete_result catch |err| {
        model.toast = if (err == error.DirectoryNotEmpty)
            "Folder is not empty; recursive deletion is refused"
        else
            "Delete failed; nothing was removed";
        return;
    };
    model.file_nodes = ws.fileNodesSlice();
    model.open_tabs = ws.tabsSlice();
    syncExplorerScanMeta(model, ws);
    if (ws.tab_count > 0) {
        const next_id = if (ws.findNodeByPath(ws.editorPath())) |active_node|
            active_node.id
        else
            ws.tabs[0].id;
        model.active_tab_id = next_id;
        model.selected_file_id = next_id;
        if (ws.findNode(next_id)) |next| setExplorerSelectedPath(model, next.path);
        ws.openFileById(modelIo(model), next_id) catch {};
        model.status_language = workspace_store.scannerLanguage(ws.editorPath());
        syncDocumentFromWorkspace(model);
    } else {
        model.document.clear();
        model.document_dirty = false;
        model.selected_file_id = 0;
        model.active_tab_id = 0;
        model.explorer_selected_path_len = 0;
        reconcileTabHistories(model);
    }
    applyExplorerFilter(model);
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
        setExplorerSelectedPath(model, node.path);
        model.explorer_collapse.expandAncestors(node.path);
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
    const source: []const FileNode = if (model.workspace_from_disk)
        if (model.workspace) |ws| ws.fileNodesSlice() else model.file_nodes
    else
        &file_tree;
    model.explorer_collapse.prune(source);
    model.explorer_projection.rebuild(source, &model.explorer_collapse, query, model.git_entries);
    model.file_nodes = model.explorer_projection.slice();
}

fn toggleExplorerFolder(model: *Model, id: u32) void {
    const ws = model.workspace orelse return;
    const node = ws.findNode(id) orelse return;
    if (!node.is_dir) return;
    setExplorerSelectedPath(model, node.path);
    model.selected_file_id = id;
    model.explorer_collapse.toggle(node.path);
    applyExplorerFilter(model);
}

fn collapseAllExplorer(model: *Model) void {
    const source: []const FileNode = if (model.workspace_from_disk)
        if (model.workspace) |ws| ws.fileNodesSlice() else &.{}
    else
        &file_tree;
    model.explorer_collapse.collapseAll(source);
    applyExplorerFilter(model);
    model.toast = "All folders collapsed";
}

fn expandAllExplorer(model: *Model) void {
    model.explorer_collapse.clear();
    applyExplorerFilter(model);
    model.toast = "All folders expanded";
}

fn setExplorerSelectedPath(model: *Model, path: []const u8) void {
    const len = @min(path.len, model.explorer_selected_path_buf.len);
    @memcpy(model.explorer_selected_path_buf[0..len], path[0..len]);
    model.explorer_selected_path_len = @intCast(len);
}

fn explorerSelectedPath(model: *const Model) []const u8 {
    return model.explorer_selected_path_buf[0..model.explorer_selected_path_len];
}

fn restoreExplorerSelection(model: *Model, ws: *workspace_store.WorkspaceBuffers) bool {
    const path = explorerSelectedPath(model);
    if (path.len == 0) return false;
    const node = ws.findNodeByPath(path) orelse return false;
    model.selected_file_id = node.id;
    return true;
}

fn refreshExplorerHeader(model: *Model) void {
    if (model.workspace_scan_truncated) {
        model.explorer_header_label = std.fmt.bufPrint(
            &model.explorer_header_buf,
            "{s} — {d}+ items (scan capped)",
            .{ model.project_name, model.workspace_node_count },
        ) catch "Workspace — scan capped";
    } else {
        model.explorer_header_label = model.project_name;
    }
}

fn syncExplorerScanMeta(model: *Model, ws: *workspace_store.WorkspaceBuffers) void {
    model.workspace_node_count = ws.file_node_count;
    model.workspace_scan_truncated = ws.scan_truncated;
    refreshWorkspaceFileCount(model);
    refreshExplorerHeader(model);
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
    const selected = ws.findNode(model.selected_file_id) orelse {
        model.toast = "No file selected";
        return;
    };
    var old_path_buf: [scanner_mod.max_rel_path_len]u8 = undefined;
    if (selected.path.len > old_path_buf.len) {
        model.toast = "Rename path too long";
        return;
    }
    @memcpy(old_path_buf[0..selected.path.len], selected.path);
    const old_path = old_path_buf[0..selected.path.len];
    syncActiveTabDirty(model);
    const id = ws.renameFileById(modelIo(model), model.selected_file_id, new_rel) catch {
        model.toast = "Rename failed";
        return;
    };
    if (model.tab_histories) |store| store.rename(old_path, new_rel) catch {};
    model.file_nodes = ws.fileNodesSlice();
    model.open_tabs = ws.tabsSlice();
    syncExplorerScanMeta(model, ws);
    setExplorerSelectedPath(model, new_rel);
    model.explorer_collapse.expandAncestors(new_rel);
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
    invalidateWorkspaceReplace(model);
    if (model.search_query.text().len > 0) {
        runWorkspaceSearch(model);
    } else {
        model.toast = if (model.search_case_sensitive) "Search: case sensitive" else "Search: ignore case";
    }
}

fn toggleSearchWholeWord(model: *Model) void {
    model.search_whole_word = !model.search_whole_word;
    persistPrefs(model);
    invalidateWorkspaceReplace(model);
    if (model.search_query.text().len > 0) {
        runWorkspaceSearch(model);
    } else {
        model.toast = if (model.search_whole_word) "Search: whole word" else "Search: substring";
    }
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
    syncExplorerScanMeta(model, ws);
    setExplorerSelectedPath(model, path_buf[0..n]);
    model.explorer_collapse.expandAncestors(path_buf[0..n]);
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
    var recent_paths: [prefs_mod.max_recent_files][]const u8 = undefined;
    var recent_count: usize = 0;
    while (recent_count < model.recent_file_count and recent_count < recent_paths.len) : (recent_count += 1) {
        recent_paths[recent_count] = model.recent_files[recent_count][0..model.recent_file_lens[recent_count]];
    }
    bufs.filterWithRecents(ws, q, recent_paths[0..recent_count]);
    model.quick_items = bufs.itemsSlice();
}

fn openQuickItem(model: *Model, item_id: u32) void {
    if (model.quick_bufs) |bufs| {
        for (bufs.itemsSlice()) |item| {
            if (item.id == item_id) {
                var from_path_buf: [scanner_mod.max_rel_path_len]u8 = undefined;
                const current_path = Model.activeTabPath(model);
                const from_path_len = @min(current_path.len, from_path_buf.len);
                @memcpy(from_path_buf[0..from_path_len], current_path[0..from_path_len]);
                const from_line = currentNavigationLine(model);
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
                    recordCrossFileNavigation(model, from_path_buf[0..from_path_len], from_line, item.path, 1);
                    model.navigation_replaying = true;
                    jumpToDocumentLine(model, 1);
                    model.navigation_replaying = false;
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
    syncActiveTabDirty(model);
    const keep = model.active_tab_id;
    var has_dirty = false;
    for (ws.tabsSlice()) |tab| {
        if (tab.id != keep and tab.dirty) {
            has_dirty = true;
            break;
        }
    }
    if (has_dirty and !model.close_other_confirm_pending) {
        model.close_other_confirm_pending = true;
        model.close_all_confirm_pending = false;
        model.toast = "Close other tabs? Confirm again to discard dirty";
        return;
    }
    model.close_other_confirm_pending = false;
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
        removeTabHistory(model, ws, id);
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
    syncActiveTabDirty(model);
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
        if (!model.close_all_confirm_pending) {
            model.close_all_confirm_pending = true;
            model.close_other_confirm_pending = false;
            model.toast = "Close all? Confirm again to discard dirty";
            return;
        }
        model.close_all_confirm_pending = false;
        model.document_dirty = false;
    } else {
        model.close_all_confirm_pending = false;
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
        removeTabHistory(model, ws, id);
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
        reconcileTabHistories(model);
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
    syncGitModel(model, bufs);
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
    syncGitModel(model, bufs);
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
    syncGitModel(model, bufs);
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
    syncActiveTabDirty(model);
    const ws = model.workspace orelse {
        model.toast = "No workspace";
        return;
    };
    for (ws.tabsSlice()) |tab| {
        if (tab.dirty) {
            model.toast = "Discard refused: an open tab has unsaved changes";
            return;
        }
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
    syncGitModel(model, bufs);
    model.governor.killFeature("feature.scm");
    model.process_count = model.governor.aliveCount();
    model.current_view = .ide;
    model.selected_activity = .scm;
    model.show_sidebar = true;
    // Every open tab was proven clean above. Reload all of them so any tracked
    // path affected by checkout cannot retain a stale background cache.
    if (std.mem.eql(u8, status, "discarded changes")) {
        var open_paths: [workspace_store.max_open_tabs][scanner_mod.max_rel_path_len]u8 = undefined;
        var path_lens: [workspace_store.max_open_tabs]usize = undefined;
        const path_count = ws.tabsSlice().len;
        for (ws.tabsSlice(), 0..) |tab, index| {
            path_lens[index] = tab.path.len;
            @memcpy(open_paths[index][0..tab.path.len], tab.path);
        }
        for (0..path_count) |index| {
            reloadCleanOpenPath(model, open_paths[index][0..path_lens[index]]);
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
    syncExplorerScanMeta(model, ws);
    applyExplorerFilter(model);

    if (new_id != 0) {
        model.active_tab_id = new_id;
        if (!restoreExplorerSelection(model, ws)) {
            model.selected_file_id = new_id;
            if (ws.findNode(new_id)) |active| setExplorerSelectedPath(model, active.path);
        }
        if (ws.findNode(new_id)) |node| {
            model.status_language = workspace_store.scannerLanguage(node.path);
        }
        syncDocumentFromWorkspace(model);
    } else {
        model.document.clear();
        model.document_dirty = false;
        model.active_tab_id = 0;
        if (!restoreExplorerSelection(model, ws)) {
            model.selected_file_id = 0;
            model.explorer_selected_path_len = 0;
        }
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

fn reloadSnippets(model: *Model, announce: bool) void {
    const registry = ensureSnippetRegistry(model) catch {
        model.snippet_status = "Snippet registry allocation failed";
        if (announce) model.toast = model.snippet_status;
        return;
    };
    const user_path = model.user_snippets_path_buf[0..model.user_snippets_path_len];
    const summary = registry.load(modelIo(model), model.project_path, user_path);
    model.snippets = registry.slice();
    filterSnippets(model);
    model.snippet_status = std.fmt.bufPrint(
        &model.snippet_status_buf,
        "{d} snippets loaded{s}",
        .{ summary.loaded, if (summary.rejected > 0) " · rejected invalid entries" else "" },
    ) catch "Snippets loaded";
    if (announce) model.toast = model.snippet_status;
}

fn filterSnippets(model: *Model) void {
    model.snippet_filtered_count = 0;
    const query = model.snippet_query.text();
    for (model.snippets) |snippet| {
        if (query.len > 0 and
            std.ascii.indexOfIgnoreCase(snippet.prefix, query) == null and
            std.ascii.indexOfIgnoreCase(snippet.description, query) == null)
        {
            continue;
        }
        if (model.snippet_filtered_count >= model.snippet_filtered.len) break;
        model.snippet_filtered[model.snippet_filtered_count] = snippet;
        model.snippet_filtered_count += 1;
    }
    model.snippets = if (model.snippet_registry) |registry|
        registry.slice()
    else
        &.{};
    model.snippet_items = model.snippet_filtered[0..model.snippet_filtered_count];
}

fn openSnippetPicker(model: *Model) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace before appending a snippet";
        return;
    }
    if (model.snippet_registry == null) reloadSnippets(model, false);
    model.snippet_query.clear();
    filterSnippets(model);
    model.snippet_picker_open = true;
    model.toast = "";
}

fn closeSnippetPicker(model: *Model) void {
    model.snippet_picker_open = false;
    model.snippet_query.clear();
    model.toast = "";
}

fn appendSnippet(model: *Model, snippet_id: u32) void {
    const registry = model.snippet_registry orelse {
        model.toast = "Reload snippets before appending";
        return;
    };
    var selected: ?Snippet = null;
    for (registry.slice()) |snippet| {
        if (snippet.id == snippet_id) {
            selected = snippet;
            break;
        }
    }
    const snippet = selected orelse {
        model.toast = "Snippet not found";
        return;
    };
    const current = model.document.text();
    if (snippet.body.len > max_document - current.len) {
        model.toast = "Append Snippet refused: document limit exceeded";
        return;
    }
    var output: [max_document]u8 = undefined;
    @memcpy(output[0..current.len], current);
    @memcpy(output[current.len..][0..snippet.body.len], snippet.body);
    model.snippet_picker_open = false;
    model.snippet_query.clear();
    applyDocumentTransform(model, output[0 .. current.len + snippet.body.len], "Snippet appended");
}

fn syncDiffReview(model: *Model, review: *unified_diff.Review, is_scm: bool) void {
    model.diff_lines = review.slice();
    model.diff_review_title = review.title;
    model.diff_review_status = review.status;
    model.diff_review_is_scm = is_scm;
    model.diff_review_open = true;
}

fn openSelectedScmDiff(model: *Model, requested_mode: ?git_status.DiffMode) void {
    if (!model.workspace_from_disk) {
        model.toast = "Open a workspace first";
        return;
    }
    if (model.selected_git_entry_id == 0) {
        model.toast = "Select a Git entry first";
        return;
    }
    const entry = gitEntryById(model, model.selected_git_entry_id) orelse {
        model.toast = "Git entry not found";
        return;
    };
    const buffers = model.git_bufs orelse {
        model.toast = "Refresh Git status first";
        return;
    };
    model.diff_staged_available = buffers.supportsMode(entry.id, .staged);
    model.diff_unstaged_available = buffers.supportsMode(entry.id, .unstaged);
    const mode: git_status.DiffMode = requested_mode orelse if (model.diff_unstaged_available) .unstaged else .staged;
    if (!buffers.supportsMode(entry.id, mode)) {
        model.toast = if (mode == .staged) "No staged diff for selected entry" else "No unstaged diff for selected entry";
        return;
    }
    buffers.loadDiff(modelIo(model), model.project_path, entry.id, mode);
    model.git_diff_text = buffers.diffText();
    model.git_diff_status = buffers.diff_status;
    const review = ensureDiffReview(model) catch {
        model.toast = "Diff review allocation failed";
        return;
    };
    review.parseUnified(buffers.diffText(), entry.path, mode.label(), buffers.diff_truncated);
    syncDiffReview(model, review, true);
    model.toast = "";
}

fn closeDiffReview(model: *Model) void {
    model.diff_review_open = false;
    model.diff_lines = &.{};
    model.toast = "";
}

fn copyDiffInternal(model: *Model) void {
    const review = model.diff_review orelse {
        model.toast = "No diff review to copy";
        return;
    };
    model.path_toast = review.copyText(&model.path_toast_buf);
    model.toast = "Diff copied to internal buffer (OS clipboard unavailable)";
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
    const review = ensureDiffReview(model) catch {
        model.toast = "Diff review allocation failed";
        return;
    };
    review.build(disk_buf[0..disk_len], model.document.text(), rel);
    syncDiffReview(model, review, false);
    model.toast = "";
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
    syncExplorerScanMeta(model, ws);
    model.selected_file_id = id;
    setExplorerSelectedPath(model, rel);
    model.explorer_collapse.expandAncestors(rel);
    applyExplorerFilter(model);
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
        resetActiveHistory(model);
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
    syncExplorerScanMeta(model, ws);
    setExplorerSelectedPath(model, rel);
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
            removeTabHistory(model, ws, id);
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
                reconcileTabHistories(model);
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
    model.search_whole_word = model.prefs.search_whole_word;
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
    model.prefs.search_whole_word = model.search_whole_word;
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
        if (model.git_bufs) |bufs| bufs.clear();
        model.git_entries = &.{};
        model.git_summary = "no workspace";
        applyExplorerFilter(model);
        model.toast = "Open a workspace for git";
        return;
    }
    const bufs = ensureGitBuffers(model) catch {
        model.toast = "Git alloc failed";
        return;
    };
    _ = model.governor.spawn("feature.scm", "git status") catch {};
    bufs.refresh(modelIo(model), model.project_path);
    syncGitModel(model, bufs);
    if (bufs.branch_len > 0) model.project_branch = bufs.branch();
    model.governor.killFeature("feature.scm");
    model.process_count = model.governor.aliveCount();
    appendOutputLabeled(model, .git, "git", bufs.summary);
    model.toast = bufs.summary;
}

fn pathForFile(id: u32) []const u8 {
    for (file_tree) |node| {
        if (node.id == id) return node.path;
    }
    return "";
}

/// Enter the full-page Settings surface, remembering the workbench state so
/// the Settings Back button can restore it exactly.
fn enterSettings(model: *Model) void {
    if (model.current_view != .settings) {
        model.settings_return_view = model.current_view;
        model.settings_return_activity = model.selected_activity;
    }
    model.current_view = .settings;
    model.selected_activity = .settings;
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

fn refreshPerformanceMetrics(model: *Model) void {
    refreshPerformanceSnapshot(model);
    model.show_perf_hud = true;
    model.current_view = .perf;
}

fn refreshPerformanceSnapshot(model: *Model) void {
    model.perf_snapshot = perf_model.snapshot(model.perf_timer.marks, &model.governor);
    model.features_registered = @intCast(model.perf_snapshot.features_registered.value);
    model.features_enabled = @intCast(model.perf_snapshot.features_enabled.value);
    model.features_loaded = @intCast(model.perf_snapshot.features_loaded.value);
    model.process_count = @intCast(model.perf_snapshot.governor_process_total.value);
    model.process_leaked = @intCast(model.perf_snapshot.governor_process_leaked.value);
    model.terminal_process_count = @intCast(model.perf_snapshot.governor_terminal_owned.value);
    model.lsp_process_count = @intCast(model.perf_snapshot.governor_lsp_owned.value);
    model.plugin_process_count = 0;
    model.perf_row_count = 0;
    addPerfRow(model, "External launch to window", model.perf_snapshot.external_launch_to_window_ns, .nanoseconds, "Out-of-process launch timing; not captured by this in-process instrumentation.");
    addPerfRow(model, "Boot to first observed nonblank paint", model.perf_snapshot.boot_to_first_observed_nonblank_ns, .nanoseconds, "In-process boot mark to the first nonblank presented frame observed after SDK installation.");
    addPerfRow(model, "SDK first frame latency", model.perf_snapshot.sdk_first_frame_latency_ns, .nanoseconds, "Native SDK surface creation to its first presented frame.");
    addPerfRow(model, "First chrome callback", model.perf_snapshot.boot_to_first_chrome_callback_ns, .nanoseconds, "In-process boot to first window chrome geometry callback; this does not assert window visibility.");
    addPerfRow(model, "Command palette request to present", model.perf_snapshot.command_palette_request_to_present_ns, .nanoseconds, "Open request to a subsequent presented frame while the palette is visible.");
    addPerfRow(model, "Terminal panel request to present", model.perf_snapshot.terminal_panel_request_to_present_ns, .nanoseconds, "Open request to a subsequent presented frame while the terminal panel is visible.");
    addPerfRow(model, "Terminal process start latency", model.perf_snapshot.terminal_process_start_ns, .nanoseconds, "No process-ready signal is exposed.");
    addPerfRow(model, "Resident memory", model.perf_snapshot.rss_bytes, .bytes, "Portable process RSS is not exposed by the Native SDK.");
    addPerfRow(model, "Plugins loaded", model.perf_snapshot.plugins_loaded, .count, "No plugin runtime loads plugins in this shell.");
    addPerfRow(model, "Features registered", model.perf_snapshot.features_registered, .count, "Entries in the authoritative feature registry.");
    addPerfRow(model, "Features enabled", model.perf_snapshot.features_enabled, .count, "Registry entries configured as enabled; enabled does not mean loaded.");
    addPerfRow(model, "Features loaded", model.perf_snapshot.features_loaded, .count, "Registry entries explicitly marked loaded.");
    addPerfRow(model, "Governor live processes", model.perf_snapshot.governor_process_total, .count, "Live child-process records owned by the Process Governor.");
    addPerfRow(model, "Governor leaked processes", model.perf_snapshot.governor_process_leaked, .count, "Leak records reported by the Process Governor.");
    addPerfRow(model, "Governor terminal-owned processes", model.perf_snapshot.governor_terminal_owned, .count, "Live Governor records with terminal ownership.");
    addPerfRow(model, "Governor task-owned processes", model.perf_snapshot.governor_task_owned, .count, "Live Governor records with task ownership.");
    addPerfRow(model, "Governor LSP-owned processes", model.perf_snapshot.governor_lsp_owned, .count, "Live Governor records with LSP ownership.");
    addPerfRow(model, "Plugin processes", model.perf_snapshot.plugin_process_total, .count, "Plugin process ownership is not represented by the Governor.");
    model.perf_rows = model.perf_row_storage[0..model.perf_row_count];
}

const PerfUnit = enum { nanoseconds, bytes, count };

fn addPerfRow(model: *Model, label: []const u8, metric: perf_model.Metric, unit: PerfUnit, semantics: []const u8) void {
    const index = model.perf_row_count;
    if (index >= model.perf_row_storage.len) return;
    const value = formatPerfValue(&model.perf_value_storage[index], metric, unit);
    model.perf_value_lens[index] = value.len;
    model.perf_row_storage[index] = .{
        .label = label,
        .value = value,
        .semantics = semantics,
        .available = metric.available,
        .status_label = if (metric.available) "measured" else "unavailable",
    };
    model.perf_row_count += 1;
}

/// Human-readable metric values; measurement honesty lives in `status_label`.
fn formatPerfValue(buf: []u8, metric: perf_model.Metric, unit: PerfUnit) []const u8 {
    if (!metric.available) return "n/a";
    return switch (unit) {
        .nanoseconds => blk: {
            const ns = metric.value;
            if (ns >= std.time.ns_per_s) {
                const secs = @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(std.time.ns_per_s));
                break :blk std.fmt.bufPrint(buf, "{d:.2} s", .{secs}) catch "n/a";
            }
            if (ns >= std.time.ns_per_ms) {
                const ms = @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(std.time.ns_per_ms));
                break :blk std.fmt.bufPrint(buf, "{d:.1} ms", .{ms}) catch "n/a";
            }
            break :blk std.fmt.bufPrint(buf, "{d} ns", .{ns}) catch "n/a";
        },
        .bytes => blk: {
            const bytes = metric.value;
            if (bytes >= 1024 * 1024) {
                const mb = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
                break :blk std.fmt.bufPrint(buf, "{d:.1} MB", .{mb}) catch "n/a";
            }
            if (bytes >= 1024) {
                const kb = @as(f64, @floatFromInt(bytes)) / 1024.0;
                break :blk std.fmt.bufPrint(buf, "{d:.1} KB", .{kb}) catch "n/a";
            }
            break :blk std.fmt.bufPrint(buf, "{d} bytes", .{bytes}) catch "n/a";
        },
        .count => std.fmt.bufPrint(buf, "{d}", .{metric.value}) catch "n/a",
    };
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
