//! Messages for feature.dirty-state.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
