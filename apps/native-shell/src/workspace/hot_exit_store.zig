//! Bounded hot-exit session encoding with owned restore buffers.

const std = @import("std");
const scanner = @import("scanner.zig");

pub const max_tabs: usize = 8;
pub const max_root_bytes = scanner.max_root_path_len;
pub const max_path_bytes = scanner.max_rel_path_len;
pub const max_dirty_text_bytes = scanner.max_file_bytes;
pub const session_rel_path = ".velocity/hot-exit.bin";
pub const max_serialized_bytes =
    4 + 2 + max_root_bytes + 2 + max_path_bytes + 1 +
    max_tabs * (2 + max_path_bytes + 1 + 4 + max_dirty_text_bytes);

const magic = "VHX1";

pub const TabInput = struct {
    path: []const u8,
    dirty: bool = false,
    dirty_text: []const u8 = "",
};

pub const Input = struct {
    root: []const u8,
    active_path: []const u8 = "",
    tabs: []const TabInput = &.{},
};

pub const State = struct {
    root_buf: [max_root_bytes]u8 = undefined,
    root_len: usize = 0,
    active_path_buf: [max_path_bytes]u8 = undefined,
    active_path_len: usize = 0,
    tab_path_bufs: [max_tabs][max_path_bytes]u8 = undefined,
    tab_path_lens: [max_tabs]usize = [_]usize{0} ** max_tabs,
    tab_dirty: [max_tabs]bool = [_]bool{false} ** max_tabs,
    tab_text_bufs: [max_tabs][max_dirty_text_bytes]u8 = undefined,
    tab_text_lens: [max_tabs]usize = [_]usize{0} ** max_tabs,
    tab_count: usize = 0,

    pub fn root(self: *const State) []const u8 {
        return self.root_buf[0..self.root_len];
    }

    pub fn activePath(self: *const State) []const u8 {
        return self.active_path_buf[0..self.active_path_len];
    }

    pub fn tabPath(self: *const State, index: usize) []const u8 {
        return self.tab_path_bufs[index][0..self.tab_path_lens[index]];
    }

    pub fn dirtyText(self: *const State, index: usize) []const u8 {
        return self.tab_text_bufs[index][0..self.tab_text_lens[index]];
    }
};

fn encodedLen(input: Input) !usize {
    if (input.root.len > max_root_bytes) return error.RootTooLong;
    if (input.active_path.len > max_path_bytes) return error.PathTooLong;
    if (input.tabs.len > max_tabs) return error.TooManyTabs;

    var len: usize = 4 + 2 + input.root.len + 2 + input.active_path.len + 1;
    for (input.tabs) |tab| {
        if (tab.path.len > max_path_bytes) return error.PathTooLong;
        if (tab.dirty and tab.dirty_text.len > max_dirty_text_bytes) return error.DirtyTextTooLong;
        const text_len = if (tab.dirty) tab.dirty_text.len else 0;
        len += 2 + tab.path.len + 1 + 4 + text_len;
    }
    return len;
}

const Encoder = struct {
    out: []u8,
    pos: usize = 0,

    fn bytes(self: *Encoder, value: []const u8) void {
        @memcpy(self.out[self.pos..][0..value.len], value);
        self.pos += value.len;
    }

    fn u8Value(self: *Encoder, value: u8) void {
        self.out[self.pos] = value;
        self.pos += 1;
    }

    fn u16Value(self: *Encoder, value: usize) void {
        self.u8Value(@intCast(value & 0xff));
        self.u8Value(@intCast((value >> 8) & 0xff));
    }

    fn u32Value(self: *Encoder, value: usize) void {
        self.u8Value(@intCast(value & 0xff));
        self.u8Value(@intCast((value >> 8) & 0xff));
        self.u8Value(@intCast((value >> 16) & 0xff));
        self.u8Value(@intCast((value >> 24) & 0xff));
    }
};

/// Serialize a complete restorable session into caller-owned bounded storage.
pub fn serialize(input: Input, out: []u8) !usize {
    const needed = try encodedLen(input);
    if (needed > out.len) return error.BufferTooSmall;

    var enc = Encoder{ .out = out };
    enc.bytes(magic);
    enc.u16Value(input.root.len);
    enc.bytes(input.root);
    enc.u16Value(input.active_path.len);
    enc.bytes(input.active_path);
    enc.u8Value(@intCast(input.tabs.len));
    for (input.tabs) |tab| {
        enc.u16Value(tab.path.len);
        enc.bytes(tab.path);
        enc.u8Value(@intFromBool(tab.dirty));
        const text = if (tab.dirty) tab.dirty_text else "";
        enc.u32Value(text.len);
        enc.bytes(text);
    }
    return enc.pos;
}

const Decoder = struct {
    data: []const u8,
    pos: usize = 0,

    fn bytes(self: *Decoder, len: usize) ![]const u8 {
        if (len > self.data.len -| self.pos) return error.InvalidEncoding;
        const value = self.data[self.pos..][0..len];
        self.pos += len;
        return value;
    }

    fn u8Value(self: *Decoder) !u8 {
        return (try self.bytes(1))[0];
    }

    fn u16Value(self: *Decoder) !usize {
        const value = try self.bytes(2);
        return @as(usize, value[0]) | (@as(usize, value[1]) << 8);
    }

    fn u32Value(self: *Decoder) !usize {
        const value = try self.bytes(4);
        return @as(usize, value[0]) |
            (@as(usize, value[1]) << 8) |
            (@as(usize, value[2]) << 16) |
            (@as(usize, value[3]) << 24);
    }
};

fn decode(data: []const u8, output: ?*State) !void {
    var dec = Decoder{ .data = data };
    if (!std.mem.eql(u8, try dec.bytes(magic.len), magic)) return error.InvalidEncoding;

    const root = try dec.bytes(try dec.u16Value());
    if (root.len > max_root_bytes) return error.RootTooLong;
    const active_path = try dec.bytes(try dec.u16Value());
    if (active_path.len > max_path_bytes) return error.PathTooLong;
    const tab_count = try dec.u8Value();
    if (tab_count > max_tabs) return error.TooManyTabs;

    if (output) |state| {
        state.* = .{};
        @memcpy(state.root_buf[0..root.len], root);
        state.root_len = root.len;
        @memcpy(state.active_path_buf[0..active_path.len], active_path);
        state.active_path_len = active_path.len;
        state.tab_count = tab_count;
    }

    var i: usize = 0;
    while (i < tab_count) : (i += 1) {
        const path = try dec.bytes(try dec.u16Value());
        if (path.len > max_path_bytes) return error.PathTooLong;
        const dirty_byte = try dec.u8Value();
        if (dirty_byte > 1) return error.InvalidEncoding;
        const dirty = dirty_byte == 1;
        const text = try dec.bytes(try dec.u32Value());
        if (text.len > max_dirty_text_bytes) return error.DirtyTextTooLong;
        if (!dirty and text.len != 0) return error.InvalidEncoding;

        if (output) |state| {
            @memcpy(state.tab_path_bufs[i][0..path.len], path);
            state.tab_path_lens[i] = path.len;
            state.tab_dirty[i] = dirty;
            @memcpy(state.tab_text_bufs[i][0..text.len], text);
            state.tab_text_lens[i] = text.len;
        }
    }
    if (dec.pos != data.len) return error.InvalidEncoding;
}

/// Validate and deserialize into owned fixed-capacity buffers.
pub fn deserialize(data: []const u8, output: *State) !void {
    // Validate first so malformed data cannot leave a partially restored state.
    try decode(data, null);
    try decode(data, output);
}

/// Persist a bounded session inside its workspace.
pub fn persist(io: std.Io, root_path: []const u8, input: Input) !void {
    const encoded = try std.heap.page_allocator.alloc(u8, max_serialized_bytes);
    defer std.heap.page_allocator.free(encoded);
    const len = try serialize(input, encoded);
    try scanner.writeFileAtomic(
        io,
        root_path,
        session_rel_path,
        encoded[0..len],
        max_serialized_bytes,
    );
}

/// Load and validate a workspace session into caller-owned state.
pub fn restore(io: std.Io, root_path: []const u8, state: *State) !void {
    const encoded = try std.heap.page_allocator.alloc(u8, max_serialized_bytes);
    defer std.heap.page_allocator.free(encoded);
    var root = try std.Io.Dir.cwd().openDir(io, root_path, .{});
    defer root.close(io);
    const data = try root.readFile(io, session_rel_path, encoded);
    try deserialize(data, state);
}

test "hot exit roundtrip preserves root active tab and dirty text" {
    const tabs = [_]TabInput{
        .{ .path = "src/a.zig" },
        .{ .path = "src/b.zig", .dirty = true, .dirty_text = "unsaved\ntext\n" },
    };
    var encoded: [max_serialized_bytes]u8 = undefined;
    const len = try serialize(.{
        .root = "/work/project",
        .active_path = "src/b.zig",
        .tabs = &tabs,
    }, &encoded);

    const state = try std.testing.allocator.create(State);
    defer std.testing.allocator.destroy(state);
    try deserialize(encoded[0..len], state);
    try std.testing.expectEqualStrings("/work/project", state.root());
    try std.testing.expectEqualStrings("src/b.zig", state.activePath());
    try std.testing.expectEqual(@as(usize, 2), state.tab_count);
    try std.testing.expectEqualStrings("src/a.zig", state.tabPath(0));
    try std.testing.expect(!state.tab_dirty[0]);
    try std.testing.expectEqual(@as(usize, 0), state.dirtyText(0).len);
    try std.testing.expectEqualStrings("src/b.zig", state.tabPath(1));
    try std.testing.expect(state.tab_dirty[1]);
    try std.testing.expectEqualStrings("unsaved\ntext\n", state.dirtyText(1));
}

test "hot exit serialization enforces tab and dirty text bounds" {
    var too_many: [max_tabs + 1]TabInput = [_]TabInput{.{ .path = "a" }} ** (max_tabs + 1);
    var encoded: [64]u8 = undefined;
    try std.testing.expectError(
        error.TooManyTabs,
        serialize(.{ .root = "root", .tabs = &too_many }, &encoded),
    );

    var oversized: [max_dirty_text_bytes + 1]u8 = undefined;
    const tab = [_]TabInput{.{ .path = "a", .dirty = true, .dirty_text = &oversized }};
    try std.testing.expectError(
        error.DirtyTextTooLong,
        serialize(.{ .root = "root", .tabs = &tab }, &encoded),
    );
}

test "hot exit rejects truncated data without changing output" {
    const tab = [_]TabInput{.{ .path = "a", .dirty = true, .dirty_text = "edit" }};
    var encoded: [128]u8 = undefined;
    const len = try serialize(.{ .root = "root", .tabs = &tab }, &encoded);
    const state = try std.testing.allocator.create(State);
    defer std.testing.allocator.destroy(state);
    state.* = .{};
    @memcpy(state.root_buf[0..4], "keep");
    state.root_len = 4;

    try std.testing.expectError(error.InvalidEncoding, deserialize(encoded[0 .. len - 1], state));
    try std.testing.expectEqualStrings("keep", state.root());
}
