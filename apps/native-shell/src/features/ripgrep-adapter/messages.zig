//! Messages for feature.ripgrep-adapter.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
