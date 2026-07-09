//! Messages for feature.bracket-pair-colorization.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
