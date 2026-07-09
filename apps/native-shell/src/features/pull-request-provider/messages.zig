//! Messages for feature.pull-request-provider.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
