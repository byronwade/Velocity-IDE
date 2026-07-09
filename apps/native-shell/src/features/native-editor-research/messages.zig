//! Messages for feature.native-editor-research.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
