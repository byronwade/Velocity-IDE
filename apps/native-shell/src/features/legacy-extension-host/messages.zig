//! Messages for feature.legacy-extension-host.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
