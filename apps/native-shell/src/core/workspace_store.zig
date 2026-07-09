//! Workspace store stub.
pub const Workspace = struct {
    id: []const u8 = "",
    name: []const u8 = "",
    path: []const u8 = "",
    branch: []const u8 = "main",
    trusted: bool = false,
};
