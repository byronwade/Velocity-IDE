//! Messages for feature.startup-flamegraph.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
