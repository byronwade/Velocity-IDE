//! Messages for feature.plugin-scorecard.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
