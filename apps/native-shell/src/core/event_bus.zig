//! Lightweight in-process event bus stub.
pub const EventKind = enum {
    first_paint_done,
    workspace_opened,
    workspace_closed,
    feature_loaded,
    feature_unloaded,
    process_spawned,
    process_exited,
    process_leaked,
};
