//! Messages for feature.find-replace.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
