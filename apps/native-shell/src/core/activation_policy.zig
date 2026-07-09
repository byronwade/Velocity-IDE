//! Feature activation policy — when code may load.
//! Only shell-critical features may use onStartupCritical.

pub const ActivationKind = enum {
    onStartupCritical,
    onFirstPaintDone,
    onIdle,
    onCommand,
    onViewVisible,
    onPanelVisible,
    onLanguage,
    onFileOpen,
    onWorkspaceOpen,
    onSearch,
    onTerminalOpen,
    onTaskRun,
    onDebugStart,
    onTestRun,
    onAgentStart,
    onPluginInstall,
    never,
};

/// Returns true if this activation may run before first native paint.
pub fn allowedBeforeFirstPaint(kind: ActivationKind) bool {
    return kind == .onStartupCritical;
}

/// Parse a policy string from feature.json activation entries.
pub fn parse(name: []const u8) ActivationKind {
    if (eql(name, "onStartupCritical")) return .onStartupCritical;
    if (eql(name, "onFirstPaintDone")) return .onFirstPaintDone;
    if (eql(name, "onIdle")) return .onIdle;
    if (startsWith(name, "onCommand:")) return .onCommand;
    if (startsWith(name, "onViewVisible:")) return .onViewVisible;
    if (startsWith(name, "onPanelVisible:")) return .onPanelVisible;
    if (eql(name, "onLanguage") or startsWith(name, "onLanguage:")) return .onLanguage;
    if (eql(name, "onFileOpen")) return .onFileOpen;
    if (eql(name, "onWorkspaceOpen")) return .onWorkspaceOpen;
    if (eql(name, "onSearch")) return .onSearch;
    if (eql(name, "onTerminalOpen")) return .onTerminalOpen;
    if (eql(name, "onTaskRun")) return .onTaskRun;
    if (eql(name, "onDebugStart")) return .onDebugStart;
    if (eql(name, "onTestRun")) return .onTestRun;
    if (eql(name, "onAgentStart")) return .onAgentStart;
    if (eql(name, "onPluginInstall")) return .onPluginInstall;
    if (eql(name, "never")) return .never;
    return .onCommand;
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (x != y) return false;
    return true;
}

fn startsWith(hay: []const u8, needle: []const u8) bool {
    if (hay.len < needle.len) return false;
    return eql(hay[0..needle.len], needle);
}
