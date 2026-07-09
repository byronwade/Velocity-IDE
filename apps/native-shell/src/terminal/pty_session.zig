//! Bounded terminal session protocol and ring buffer.
//! PTY transport is deliberately unavailable until the Native SDK exposes a
//! supported interactive process/PTY lifecycle. This module spawns nothing.

const std = @import("std");

pub const max_scrollback_lines: usize = 2000;
pub const max_line_bytes: usize = 512;
pub const max_input_bytes: usize = 4096;
pub const max_columns: u16 = 1000;
pub const max_rows: u16 = 1000;

pub const TransportAvailability = enum {
    unavailable,
};

pub fn transportAvailability() TransportAvailability {
    return .unavailable;
}

pub const Size = struct {
    columns: u16 = 80,
    rows: u16 = 24,
};

/// Commands for a future PTY transport. Slice data is borrowed during dispatch.
pub const Command = union(enum) {
    start: struct {
        cwd: []const u8,
        shell: []const u8,
    },
    input: []const u8,
    resize: Size,
    close,
};

/// Events accepted from a future PTY transport.
pub const Event = union(enum) {
    started: u64,
    output: []const u8,
    exited: i32,
    transport_failed: []const u8,
};

pub const State = enum {
    unavailable,
    starting,
    running,
    exited,
    failed,
};

pub const LineRing = struct {
    storage: [max_scrollback_lines][max_line_bytes]u8 = undefined,
    lengths: [max_scrollback_lines]u16 = [_]u16{0} ** max_scrollback_lines,
    start: usize = 0,
    count: usize = 0,

    pub fn push(self: *LineRing, text: []const u8) void {
        const slot = if (self.count < max_scrollback_lines)
            (self.start + self.count) % max_scrollback_lines
        else blk: {
            const oldest = self.start;
            self.start = (self.start + 1) % max_scrollback_lines;
            break :blk oldest;
        };
        if (self.count < max_scrollback_lines) self.count += 1;
        const length = @min(text.len, max_line_bytes);
        @memcpy(self.storage[slot][0..length], text[0..length]);
        self.lengths[slot] = @intCast(length);
    }

    pub fn line(self: *const LineRing, logical_index: usize) ?[]const u8 {
        if (logical_index >= self.count) return null;
        const slot = (self.start + logical_index) % max_scrollback_lines;
        return self.storage[slot][0..self.lengths[slot]];
    }

    pub fn clear(self: *LineRing) void {
        self.start = 0;
        self.count = 0;
    }
};

pub const PtySession = struct {
    state: State = .unavailable,
    transport_id: ?u64 = null,
    size: Size = .{},
    lines: LineRing = .{},
    partial_line: [max_line_bytes]u8 = undefined,
    partial_len: usize = 0,
    input_storage: [max_input_bytes]u8 = undefined,
    input_len: usize = 0,
    exit_code: ?i32 = null,

    pub fn queueCommand(self: *PtySession, command: Command) !void {
        switch (command) {
            .start => return error.TransportUnavailable,
            .input => |bytes| try self.queueInput(bytes),
            .resize => |size| try self.resize(size),
            .close => {
                self.input_len = 0;
                self.transport_id = null;
                self.state = .exited;
            },
        }
    }

    pub fn accept(self: *PtySession, event: Event) void {
        switch (event) {
            .started => |transport_id| {
                self.transport_id = transport_id;
                self.state = .running;
            },
            .output => |bytes| self.appendOutput(bytes),
            .exited => |code| {
                self.flushPartial();
                self.exit_code = code;
                self.state = .exited;
                self.transport_id = null;
            },
            .transport_failed => {
                self.flushPartial();
                self.state = .failed;
                self.transport_id = null;
            },
        }
    }

    pub fn queuedInput(self: *const PtySession) []const u8 {
        return self.input_storage[0..self.input_len];
    }

    pub fn consumeInput(self: *PtySession, count: usize) void {
        const consumed = @min(count, self.input_len);
        const remaining = self.input_len - consumed;
        std.mem.copyForwards(u8, self.input_storage[0..remaining], self.input_storage[consumed..self.input_len]);
        self.input_len = remaining;
    }

    fn queueInput(self: *PtySession, bytes: []const u8) !void {
        const new_len = std.math.add(usize, self.input_len, bytes.len) catch return error.InputBufferFull;
        if (new_len > max_input_bytes) return error.InputBufferFull;
        @memcpy(self.input_storage[self.input_len..new_len], bytes);
        self.input_len = new_len;
    }

    fn resize(self: *PtySession, size: Size) !void {
        if (size.columns == 0 or size.rows == 0 or
            size.columns > max_columns or size.rows > max_rows)
        {
            return error.InvalidTerminalSize;
        }
        self.size = size;
    }

    fn appendOutput(self: *PtySession, bytes: []const u8) void {
        for (bytes) |byte| {
            if (byte == '\n') {
                self.lines.push(self.partial_line[0..self.partial_len]);
                self.partial_len = 0;
            } else if (byte != '\r') {
                if (self.partial_len < max_line_bytes) {
                    self.partial_line[self.partial_len] = byte;
                    self.partial_len += 1;
                }
            }
        }
    }

    fn flushPartial(self: *PtySession) void {
        if (self.partial_len == 0) return;
        self.lines.push(self.partial_line[0..self.partial_len]);
        self.partial_len = 0;
    }
};

test "PTY protocol explicitly refuses start without transport" {
    var session: PtySession = .{};
    try std.testing.expectEqual(TransportAvailability.unavailable, transportAvailability());
    try std.testing.expectError(
        error.TransportUnavailable,
        session.queueCommand(.{ .start = .{ .cwd = "/workspace", .shell = "/bin/sh" } }),
    );
    try std.testing.expectEqual(State.unavailable, session.state);
}

test "terminal output forms bounded ordered ring lines" {
    var ring: LineRing = .{};
    var index: usize = 0;
    while (index <= max_scrollback_lines) : (index += 1) {
        var buffer: [32]u8 = undefined;
        const text = try std.fmt.bufPrint(&buffer, "line-{d}", .{index});
        ring.push(text);
    }
    try std.testing.expectEqual(max_scrollback_lines, ring.count);
    try std.testing.expectEqualStrings("line-1", ring.line(0).?);

    var session: PtySession = .{};
    session.accept(.{ .output = "partial" });
    session.accept(.{ .output = " line\nnext" });
    session.accept(.{ .exited = 0 });
    try std.testing.expectEqualStrings("partial line", session.lines.line(0).?);
    try std.testing.expectEqualStrings("next", session.lines.line(1).?);
}

test "terminal input and resize commands are bounded" {
    var session: PtySession = .{};
    try session.queueCommand(.{ .input = "echo ok\n" });
    try std.testing.expectEqualStrings("echo ok\n", session.queuedInput());
    session.consumeInput(5);
    try std.testing.expectEqualStrings("ok\n", session.queuedInput());

    try session.queueCommand(.{ .resize = .{ .columns = 120, .rows = 40 } });
    try std.testing.expectEqual(@as(u16, 120), session.size.columns);
    try std.testing.expectError(
        error.InvalidTerminalSize,
        session.queueCommand(.{ .resize = .{ .columns = 0, .rows = 40 } }),
    );

    const too_much = [_]u8{'x'} ** max_input_bytes;
    try std.testing.expectError(error.InputBufferFull, session.queueCommand(.{ .input = &too_much }));
}
