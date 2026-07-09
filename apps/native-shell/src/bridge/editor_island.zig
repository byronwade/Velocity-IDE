//! Bounded editor-island protocol.
//! The textarea backend is available today. Monaco/WebView and a native editor
//! are typed targets only; selecting either returns `BackendUnavailable`.

const std = @import("std");

pub const max_path_bytes: usize = 1024;

pub const Backend = enum {
    textarea,
    monaco_webview,
    native_editor,
};

pub const Availability = enum {
    available,
    blocked_by_sdk,
    research_only,
};

pub fn availability(backend: Backend) Availability {
    return switch (backend) {
        .textarea => .available,
        .monaco_webview => .blocked_by_sdk,
        .native_editor => .research_only,
    };
}

pub const Lifecycle = enum {
    detached,
    ready,
    failed,
};

pub const Selection = struct {
    anchor: u32 = 0,
    head: u32 = 0,
};

/// Events emitted by an editor implementation toward the application model.
/// Slice payloads are borrowed for the duration of dispatch.
pub const Event = union(enum) {
    ready: Backend,
    text_changed: struct {
        text: []const u8,
        revision: u64,
    },
    selection_changed: Selection,
    focus_changed: bool,
    save_requested,
    failed: []const u8,
};

/// Commands sent by the application model toward an editor implementation.
/// This boundary does not execute or host a WebView.
pub const Command = union(enum) {
    attach: Backend,
    open_document: struct {
        path: []const u8,
        text: []const u8,
        revision: u64,
    },
    replace_text: struct {
        text: []const u8,
        revision: u64,
    },
    set_selection: Selection,
    focus,
    detach,
};

pub const EditorIsland = struct {
    backend: Backend = .textarea,
    lifecycle: Lifecycle = .detached,
    path_storage: [max_path_bytes]u8 = undefined,
    path_len: usize = 0,
    revision: u64 = 0,
    selection: Selection = .{},
    focused: bool = false,

    pub fn activePath(self: *const EditorIsland) []const u8 {
        return self.path_storage[0..self.path_len];
    }

    pub fn dispatch(self: *EditorIsland, event: Event) !void {
        switch (event) {
            .ready => |backend| {
                try requireAvailable(backend);
                if (backend != self.backend) return error.BackendMismatch;
                self.lifecycle = .ready;
            },
            .text_changed => |change| {
                if (self.lifecycle != .ready) return error.EditorNotReady;
                if (change.revision <= self.revision) return error.StaleRevision;
                self.revision = change.revision;
            },
            .selection_changed => |selection| self.selection = selection,
            .focus_changed => |focused| self.focused = focused,
            .save_requested => {},
            .failed => self.lifecycle = .failed,
        }
    }

    pub fn apply(self: *EditorIsland, command: Command) !void {
        switch (command) {
            .attach => |backend| {
                try requireAvailable(backend);
                self.backend = backend;
                self.lifecycle = .detached;
            },
            .open_document => |document| {
                if (document.path.len > max_path_bytes) return error.PathTooLong;
                @memcpy(self.path_storage[0..document.path.len], document.path);
                self.path_len = document.path.len;
                self.revision = document.revision;
                self.selection = .{};
                _ = document.text;
            },
            .replace_text => |replacement| {
                if (replacement.revision <= self.revision) return error.StaleRevision;
                self.revision = replacement.revision;
                _ = replacement.text;
            },
            .set_selection => |selection| self.selection = selection,
            .focus => self.focused = true,
            .detach => {
                self.lifecycle = .detached;
                self.focused = false;
            },
        }
    }
};

fn requireAvailable(backend: Backend) !void {
    if (availability(backend) != .available) return error.BackendUnavailable;
}

test "textarea backend follows typed state protocol" {
    var island: EditorIsland = .{};
    try island.apply(.{ .attach = .textarea });
    try island.apply(.{ .open_document = .{
        .path = "src/main.zig",
        .text = "const value = 1;",
        .revision = 4,
    } });
    try island.dispatch(.{ .ready = .textarea });
    try island.dispatch(.{ .text_changed = .{ .text = "const value = 2;", .revision = 5 } });
    try island.dispatch(.{ .selection_changed = .{ .anchor = 3, .head = 8 } });

    try std.testing.expectEqual(Lifecycle.ready, island.lifecycle);
    try std.testing.expectEqualStrings("src/main.zig", island.activePath());
    try std.testing.expectEqual(@as(u64, 5), island.revision);
    try std.testing.expectEqual(@as(u32, 8), island.selection.head);
}

test "future backends remain explicitly unavailable" {
    var island: EditorIsland = .{};
    try std.testing.expectEqual(Availability.blocked_by_sdk, availability(.monaco_webview));
    try std.testing.expectError(error.BackendUnavailable, island.apply(.{ .attach = .monaco_webview }));
    try std.testing.expectEqual(Backend.textarea, island.backend);
}

test "editor protocol rejects stale revisions and oversized paths" {
    var island: EditorIsland = .{};
    try island.apply(.{ .open_document = .{ .path = "a", .text = "", .revision = 2 } });
    try std.testing.expectError(
        error.StaleRevision,
        island.apply(.{ .replace_text = .{ .text = "old", .revision = 2 } }),
    );
    const too_long = [_]u8{'x'} ** (max_path_bytes + 1);
    try std.testing.expectError(
        error.PathTooLong,
        island.apply(.{ .open_document = .{ .path = &too_long, .text = "", .revision = 3 } }),
    );
}
