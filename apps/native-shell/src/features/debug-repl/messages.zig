//! Messages for feature.debug-repl.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
