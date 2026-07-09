//! Process tree tracking stub (parent/child OS pids).
pub const Node = struct { pid: u32 = 0, parent_pid: u32 = 0, children: u32 = 0 };
