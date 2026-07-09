//! Workspace store re-export for core/ layout.
pub const store = @import("../workspace/workspace_store.zig");
pub const Workspace = store.Workspace;
pub const WorkspaceBuffers = store.WorkspaceBuffers;
