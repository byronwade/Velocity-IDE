//! Bounded workspace directory scanner (Zig 0.16 Io.Dir).
//! Skips heavy/vendor dirs by default. No file watchers. No indexing.
//! Activation: onWorkspaceOpen only — never before first paint.

const std = @import("std");
const Io = std.Io;

pub const max_nodes: usize = 256;
pub const max_depth: u8 = 8;
pub const max_name_len: usize = 64;
pub const max_rel_path_len: usize = 240;
pub const max_root_path_len: usize = 512;
pub const max_file_bytes: usize = 16 * 1024;

pub const SkipSet = struct {
    pub fn shouldSkipName(name: []const u8) bool {
        const skipped = [_][]const u8{
            ".git",         "node_modules", "vendor",   "dist",
            "build",        ".next",        "target",   "__pycache__",
            ".turbo",       ".cache",       "zig-out",  ".native",
            ".zig-cache",   ".DS_Store",
        };
        for (skipped) |s| {
            if (std.mem.eql(u8, name, s)) return true;
        }
        return false;
    }

    pub fn shouldSkipDir(name: []const u8) bool {
        if (shouldSkipName(name)) return true;
        return name.len > 0 and name[0] == '.';
    }
};

pub const ScanNode = struct {
    id: u32 = 0,
    name_off: u32 = 0,
    name_len: u8 = 0,
    path_off: u32 = 0,
    path_len: u16 = 0,
    depth: u8 = 0,
    is_dir: bool = false,
};

pub const ScanBuffers = struct {
    nodes: []ScanNode,
    name_pool: []u8,
    path_pool: []u8,
    node_count: u32 = 0,
    name_used: u32 = 0,
    path_used: u32 = 0,
};

pub const ScanError = error{
    NotDir,
    AccessDenied,
    TooManyNodes,
    PathTooLong,
    NameTooLong,
    PoolExhausted,
    BinaryFile,
};

fn pushName(bufs: *ScanBuffers, name: []const u8) ScanError!struct { off: u32, len: u8 } {
    if (name.len > max_name_len) return error.NameTooLong;
    if (bufs.name_used + name.len > bufs.name_pool.len) return error.PoolExhausted;
    const off = bufs.name_used;
    @memcpy(bufs.name_pool[off..][0..name.len], name);
    bufs.name_used += @intCast(name.len);
    return .{ .off = off, .len = @intCast(name.len) };
}

fn pushPath(bufs: *ScanBuffers, path: []const u8) ScanError!struct { off: u32, len: u16 } {
    if (path.len > max_rel_path_len) return error.PathTooLong;
    if (bufs.path_used + path.len > bufs.path_pool.len) return error.PoolExhausted;
    const off = bufs.path_used;
    @memcpy(bufs.path_pool[off..][0..path.len], path);
    bufs.path_used += @intCast(path.len);
    return .{ .off = off, .len = @intCast(path.len) };
}

fn addNode(bufs: *ScanBuffers, name: []const u8, rel_path: []const u8, depth: u8, is_dir: bool) ScanError!void {
    if (bufs.node_count >= bufs.nodes.len) return error.TooManyNodes;
    const n = try pushName(bufs, name);
    const p = try pushPath(bufs, rel_path);
    bufs.nodes[bufs.node_count] = .{
        .id = bufs.node_count + 1,
        .name_off = n.off,
        .name_len = n.len,
        .path_off = p.off,
        .path_len = p.len,
        .depth = depth,
        .is_dir = is_dir,
    };
    bufs.node_count += 1;
}

const Entry = struct {
    name: []const u8,
    is_dir: bool,
};

fn collectEntries(io: Io, dir: Io.Dir, scratch: []Entry, name_scratch: []u8, name_used: *usize) ![]Entry {
    var it = dir.iterate();
    var count: usize = 0;
    while (try it.next(io)) |entry| {
        if (count >= scratch.len) break;
        const is_dir = entry.kind == .directory;
        if (is_dir) {
            if (SkipSet.shouldSkipDir(entry.name)) continue;
        } else {
            if (SkipSet.shouldSkipName(entry.name)) continue;
            if (entry.name.len > 0 and entry.name[0] == '.' and
                !std.mem.eql(u8, entry.name, ".gitignore") and
                !std.mem.eql(u8, entry.name, ".env")) continue;
        }
        if (name_used.* + entry.name.len > name_scratch.len) break;
        const off = name_used.*;
        @memcpy(name_scratch[off..][0..entry.name.len], entry.name);
        name_used.* += entry.name.len;
        scratch[count] = .{ .name = name_scratch[off..][0..entry.name.len], .is_dir = is_dir };
        count += 1;
    }
    std.mem.sort(Entry, scratch[0..count], {}, struct {
        fn less(_: void, a: Entry, b: Entry) bool {
            if (a.is_dir != b.is_dir) return a.is_dir and !b.is_dir;
            return std.ascii.lessThanIgnoreCase(a.name, b.name);
        }
    }.less);
    return scratch[0..count];
}

fn walk(
    io: Io,
    parent: Io.Dir,
    rel: []const u8,
    depth: u8,
    bufs: *ScanBuffers,
) ScanError!void {
    if (depth > max_depth) return;
    var entry_scratch: [128]Entry = undefined;
    var name_scratch: [4096]u8 = undefined;
    var name_used: usize = 0;
    const entries = collectEntries(io, parent, entry_scratch[0..], name_scratch[0..], &name_used) catch return error.AccessDenied;

    // Copy entry names we will recurse into before opening children (names live in scratch).
    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        const entry = entries[i];
        var child_rel_buf: [max_rel_path_len]u8 = undefined;
        const child_rel = if (rel.len == 0) blk: {
            if (entry.name.len > child_rel_buf.len) return error.PathTooLong;
            @memcpy(child_rel_buf[0..entry.name.len], entry.name);
            break :blk child_rel_buf[0..entry.name.len];
        } else blk: {
            const need = rel.len + 1 + entry.name.len;
            if (need > child_rel_buf.len) return error.PathTooLong;
            @memcpy(child_rel_buf[0..rel.len], rel);
            child_rel_buf[rel.len] = '/';
            @memcpy(child_rel_buf[rel.len + 1 ..][0..entry.name.len], entry.name);
            break :blk child_rel_buf[0..need];
        };

        try addNode(bufs, entry.name, child_rel, depth, entry.is_dir);

        if (entry.is_dir) {
            var child = parent.openDir(io, entry.name, .{ .iterate = true }) catch continue;
            defer child.close(io);
            try walk(io, child, child_rel, depth + 1, bufs);
        }
    }
}

/// Scan `root_path` into `bufs`. Returns node count.
pub fn scanWorkspace(io: Io, root_path: []const u8, bufs: *ScanBuffers) ScanError!u32 {
    bufs.node_count = 0;
    bufs.name_used = 0;
    bufs.path_used = 0;

    var root = Io.Dir.cwd().openDir(io, root_path, .{ .iterate = true }) catch |err| {
        return switch (err) {
            error.FileNotFound, error.NotDir => error.NotDir,
            error.AccessDenied, error.PermissionDenied => error.AccessDenied,
            else => error.AccessDenied,
        };
    };
    defer root.close(io);

    try walk(io, root, "", 0, bufs);
    return bufs.node_count;
}

pub fn nodeName(bufs: *const ScanBuffers, node: ScanNode) []const u8 {
    return bufs.name_pool[node.name_off..][0..node.name_len];
}

pub fn nodePath(bufs: *const ScanBuffers, node: ScanNode) []const u8 {
    return bufs.path_pool[node.path_off..][0..node.path_len];
}

pub fn readTextFile(io: Io, root_path: []const u8, rel_path: []const u8, out: []u8) !usize {
    var root = try Io.Dir.cwd().openDir(io, root_path, .{});
    defer root.close(io);
    const slice = root.readFile(io, rel_path, out) catch |err| {
        return switch (err) {
            error.FileNotFound => error.FileNotFound,
            error.AccessDenied, error.PermissionDenied => error.AccessDenied,
            else => error.AccessDenied,
        };
    };
    const check_len = @min(slice.len, @as(usize, 512));
    if (std.mem.indexOfScalar(u8, slice[0..check_len], 0) != null) return error.BinaryFile;
    return slice.len;
}

pub fn writeTextFile(io: Io, root_path: []const u8, rel_path: []const u8, data: []const u8) !void {
    if (rel_path.len == 0 or data.len > max_file_bytes) return error.AccessDenied;
    var root = try Io.Dir.cwd().openDir(io, root_path, .{});
    defer root.close(io);
    if (std.fs.path.dirname(rel_path)) |parent| {
        root.createDirPath(io, parent) catch {};
    }
    root.writeFile(io, .{ .sub_path = rel_path, .data = data }) catch return error.AccessDenied;
}

pub fn deleteRelFile(io: Io, root_path: []const u8, rel_path: []const u8) !void {
    if (rel_path.len == 0) return error.AccessDenied;
    var root = try Io.Dir.cwd().openDir(io, root_path, .{});
    defer root.close(io);
    root.deleteFile(io, rel_path) catch return error.AccessDenied;
}

pub fn renameRelFile(io: Io, root_path: []const u8, old_rel: []const u8, new_rel: []const u8) !void {
    if (old_rel.len == 0 or new_rel.len == 0) return error.AccessDenied;
    var root = try Io.Dir.cwd().openDir(io, root_path, .{});
    defer root.close(io);
    if (std.fs.path.dirname(new_rel)) |parent| {
        root.createDirPath(io, parent) catch {};
    }
    root.rename(old_rel, root, new_rel, io) catch return error.AccessDenied;
}

/// Join root + relative path into `out`. Returns joined slice.
pub fn joinRootRel(root: []const u8, rel: []const u8, out: []u8) ![]const u8 {
    if (root.len == 0) {
        if (rel.len > out.len) return error.PathTooLong;
        @memcpy(out[0..rel.len], rel);
        return out[0..rel.len];
    }
    const need = root.len + 1 + rel.len;
    if (need > out.len) return error.PathTooLong;
    @memcpy(out[0..root.len], root);
    out[root.len] = '/';
    @memcpy(out[root.len + 1 ..][0..rel.len], rel);
    return out[0..need];
}

pub fn languageForPath(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".tsx")) return "TypeScript React";
    if (std.mem.endsWith(u8, path, ".ts")) return "TypeScript";
    if (std.mem.endsWith(u8, path, ".jsx")) return "JavaScript React";
    if (std.mem.endsWith(u8, path, ".js")) return "JavaScript";
    if (std.mem.endsWith(u8, path, ".json")) return "JSON";
    if (std.mem.endsWith(u8, path, ".md")) return "Markdown";
    if (std.mem.endsWith(u8, path, ".css")) return "CSS";
    if (std.mem.endsWith(u8, path, ".html")) return "HTML";
    if (std.mem.endsWith(u8, path, ".zig")) return "Zig";
    if (std.mem.endsWith(u8, path, ".rs")) return "Rust";
    if (std.mem.endsWith(u8, path, ".py")) return "Python";
    if (std.mem.endsWith(u8, path, ".go")) return "Go";
    return "Plain Text";
}

pub fn baseName(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |i| return path[i + 1 ..];
    return path;
}

test "skip set hides node_modules and git" {
    try std.testing.expect(SkipSet.shouldSkipDir("node_modules"));
    try std.testing.expect(SkipSet.shouldSkipDir(".git"));
    try std.testing.expect(!SkipSet.shouldSkipDir("src"));
}

test "scan fixture with testing.io" {
    var nodes: [max_nodes]ScanNode = undefined;
    var name_pool: [16 * 1024]u8 = undefined;
    var path_pool: [48 * 1024]u8 = undefined;
    var bufs = ScanBuffers{ .nodes = nodes[0..], .name_pool = name_pool[0..], .path_pool = path_pool[0..] };
    const count = try scanWorkspace(std.testing.io, "fixtures/acme-dashboard", &bufs);
    try std.testing.expect(count > 0);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const name = nodeName(&bufs, bufs.nodes[i]);
        try std.testing.expect(!std.mem.eql(u8, name, "node_modules"));
    }
}
