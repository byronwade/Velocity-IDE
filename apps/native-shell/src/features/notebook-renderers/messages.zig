//! Messages for feature.notebook-renderers.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
