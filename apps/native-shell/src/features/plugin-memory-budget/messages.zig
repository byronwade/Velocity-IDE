//! Messages for feature.plugin-memory-budget.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
