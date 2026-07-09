//! Messages for feature.column-selection.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
