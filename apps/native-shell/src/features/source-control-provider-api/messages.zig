//! Messages for feature.source-control-provider-api.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
