//! Messages for feature.voice.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
