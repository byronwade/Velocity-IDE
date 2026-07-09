//! Messages for feature.integrated-browser.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
