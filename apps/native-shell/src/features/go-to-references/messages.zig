//! Messages for feature.go-to-references.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
