//! Messages for feature.keybindings.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
