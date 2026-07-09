//! Messages for feature.watch.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
