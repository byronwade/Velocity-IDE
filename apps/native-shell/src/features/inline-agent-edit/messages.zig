//! Messages for feature.inline-agent-edit.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
