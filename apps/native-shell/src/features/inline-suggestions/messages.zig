//! Messages for feature.inline-suggestions.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
