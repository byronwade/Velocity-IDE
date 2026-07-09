//! Messages for feature.git-provider.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
