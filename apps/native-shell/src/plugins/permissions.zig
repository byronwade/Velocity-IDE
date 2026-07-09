//! Plugin permissions — default deny.

pub const Permission = enum {
    filesystem_read,
    filesystem_write,
    network,
    terminal,
    shell,
    credentials,
    clipboard,
    environment,
    workspace_scan,
    webview,
    native_binary,
    ai_tools,
};

pub fn permissionId(p: Permission) []const u8 {
    return switch (p) {
        .filesystem_read => "filesystem.read",
        .filesystem_write => "filesystem.write",
        .network => "network",
        .terminal => "terminal",
        .shell => "shell",
        .credentials => "credentials",
        .clipboard => "clipboard",
        .environment => "environment",
        .workspace_scan => "workspace.scan",
        .webview => "webview",
        .native_binary => "nativeBinary",
        .ai_tools => "aiTools",
    };
}

/// Milestone 1: everything denied unless explicitly granted later.
pub fn isAllowed(_: Permission) bool {
    return false;
}
