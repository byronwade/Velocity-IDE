//! Core app model note — shell Model remains in model/app_model.zig.
//! This module holds mode / safe-mode flags shared with the feature registry.

pub const RuntimeMode = enum { core, dev, heavy, agent, legacy };

pub const CoreFlags = struct {
    runtime_mode: RuntimeMode = .core,
    safe_mode: bool = false,
    no_extensions: bool = true,
    no_agents: bool = false,
    first_paint_done: bool = false,
};
