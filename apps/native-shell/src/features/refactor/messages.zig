//! Messages for feature.refactor.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
