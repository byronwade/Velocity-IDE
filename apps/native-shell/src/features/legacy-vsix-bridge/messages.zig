//! Messages for feature.legacy-vsix-bridge.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
