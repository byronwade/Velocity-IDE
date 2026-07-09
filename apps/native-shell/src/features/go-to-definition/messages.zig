//! Messages for feature.go-to-definition.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
