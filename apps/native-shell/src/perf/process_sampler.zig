//! Live process counts sourced exclusively from the Process Governor.

const process_governor = @import("../processes/process_governor.zig");

pub const Sample = struct {
    total: u32 = 0,
    leaked: u32 = 0,
    terminal_owned: u32 = 0,
    task_owned: u32 = 0,
    lsp_owned: u32 = 0,
};

pub fn sample(governor: *const process_governor.Governor) Sample {
    const ownership = governor.aliveOwnershipCounts();
    return .{
        .total = governor.aliveCount(),
        .leaked = governor.leak_count,
        .terminal_owned = ownership.terminal,
        .task_owned = ownership.task,
        .lsp_owned = ownership.lsp,
    };
}
