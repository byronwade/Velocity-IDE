//! Messages for feature.native-plugin-runtime.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
