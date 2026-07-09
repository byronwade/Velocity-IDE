//! Messages for feature.command-journal.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
