//! Messages for feature.rename-symbol.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
