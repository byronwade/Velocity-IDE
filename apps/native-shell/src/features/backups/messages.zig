//! Messages for feature.backups.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
