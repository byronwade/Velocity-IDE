//! Messages for feature.lsp-process-manager.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
