//! Messages for feature.ram-budget-dashboard.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
