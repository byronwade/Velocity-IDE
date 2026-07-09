//! Messages for feature.settings-sync.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
