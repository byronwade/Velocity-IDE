//! Future: spawn/supervise language server processes with workspace scope.

pub const ServerProcess = struct {
    id: []const u8 = "",
    command: []const u8 = "",
    pid: u32 = 0,
};
