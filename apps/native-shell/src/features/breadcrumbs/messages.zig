//! Messages for feature.breadcrumbs.
pub const Msg = union(enum) {
    enable,
    disable,
    activate: []const u8,
};
