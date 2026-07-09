//! Messages for feature.lsp-broker.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
