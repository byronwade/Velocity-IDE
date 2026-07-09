//! Bounded on-disk backups used immediately before an explicit overwrite.

const std = @import("std");
const scanner = @import("scanner.zig");

pub const max_backup_bytes = scanner.max_file_bytes;
pub const backup_prefix = ".velocity/backups/";
pub const backup_suffix = ".bak";
pub const backup_generations: usize = 3;
pub const max_backup_path_len = backup_prefix.len + scanner.max_rel_path_len + backup_suffix.len + 2;

fn validateRelativePath(path: []const u8) !void {
    scanner.validateRelativePath(path) catch return error.InvalidPath;
}

/// Build the stable backup path for a workspace-relative file.
pub fn pathFor(original_path: []const u8, out: []u8) ![]const u8 {
    return try pathForGeneration(original_path, 0, out);
}

pub fn pathForGeneration(original_path: []const u8, generation: usize, out: []u8) ![]const u8 {
    try validateRelativePath(original_path);
    if (generation >= backup_generations) return error.InvalidGeneration;
    const generation_suffix = switch (generation) {
        0 => "",
        1 => ".1",
        2 => ".2",
        else => unreachable,
    };
    const needed = backup_prefix.len + original_path.len + backup_suffix.len + generation_suffix.len;
    if (needed > out.len) return error.PathTooLong;
    @memcpy(out[0..backup_prefix.len], backup_prefix);
    @memcpy(out[backup_prefix.len..][0..original_path.len], original_path);
    @memcpy(out[backup_prefix.len + original_path.len ..][0..backup_suffix.len], backup_suffix);
    @memcpy(out[backup_prefix.len + original_path.len + backup_suffix.len ..][0..generation_suffix.len], generation_suffix);
    return out[0..needed];
}

fn rotate(io: std.Io, root_path: []const u8, original_path: []const u8) !void {
    var paths: [backup_generations][max_backup_path_len]u8 = undefined;
    var lens: [backup_generations]usize = undefined;
    for (0..backup_generations) |generation| {
        lens[generation] = (try pathForGeneration(original_path, generation, &paths[generation])).len;
    }
    var root = try std.Io.Dir.cwd().openDir(io, root_path, .{});
    defer root.close(io);

    root.deleteFile(io, paths[backup_generations - 1][0..lens[backup_generations - 1]]) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
    var generation = backup_generations - 1;
    while (generation > 0) : (generation -= 1) {
        const source = paths[generation - 1][0..lens[generation - 1]];
        const destination = paths[generation][0..lens[generation]];
        root.rename(source, root, destination, io) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }
}

/// Copy the current file into the bounded backup store.
/// Oversized files are rejected before the backup destination is opened.
pub fn backupBeforeOverwrite(io: std.Io, root_path: []const u8, original_path: []const u8) !void {
    var bytes: [max_backup_bytes]u8 = undefined;
    const len = try scanner.readTextFile(io, root_path, original_path, &bytes);
    var path_buf: [max_backup_path_len]u8 = undefined;
    const backup_path = try pathFor(original_path, &path_buf);
    try rotate(io, root_path, original_path);
    try scanner.writeFileAtomic(io, root_path, backup_path, bytes[0..len], max_backup_bytes);
}

/// Read the newest available stable generation into caller-owned memory.
pub fn read(io: std.Io, root_path: []const u8, original_path: []const u8, out: []u8) !usize {
    var path_buf: [max_backup_path_len]u8 = undefined;
    for (0..backup_generations) |generation| {
        const backup_path = try pathForGeneration(original_path, generation, &path_buf);
        return scanner.readTextFile(io, root_path, backup_path, out) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
    }
    return error.FileNotFound;
}

/// Replace a file with its stable backup. The backup remains available.
pub fn restore(io: std.Io, root_path: []const u8, original_path: []const u8) !void {
    var bytes: [max_backup_bytes]u8 = undefined;
    const len = try read(io, root_path, original_path, &bytes);
    try scanner.writeTextFile(io, root_path, original_path, bytes[0..len]);
}

/// Back up the current contents, then replace the original with `new_data`.
pub fn overwrite(io: std.Io, root_path: []const u8, original_path: []const u8, new_data: []const u8) !void {
    if (new_data.len > scanner.max_file_bytes) return error.FileTooLarge;
    try backupBeforeOverwrite(io, root_path, original_path);
    try scanner.writeTextFile(io, root_path, original_path, new_data);
}

test "overwrite retains bounded previous contents" {
    const root = "zig-out/test-backup-overwrite";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root ++ "/src");
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = root ++ "/src/a.txt",
        .data = "before",
    });

    try overwrite(std.testing.io, root, "src/a.txt", "after");

    var out: [64]u8 = undefined;
    const current = try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/src/a.txt", &out);
    try std.testing.expectEqualStrings("after", current);
    const backup = try std.Io.Dir.cwd().readFile(
        std.testing.io,
        root ++ "/.velocity/backups/src/a.txt.bak",
        &out,
    );
    try std.testing.expectEqualStrings("before", backup);
}

test "oversized original is rejected before backup or overwrite" {
    const root = "zig-out/test-backup-oversized";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    var oversized: [max_backup_bytes + 1]u8 = undefined;
    @memset(&oversized, 'x');
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = root ++ "/large.txt",
        .data = &oversized,
    });

    try std.testing.expectError(
        error.FileTooLarge,
        overwrite(std.testing.io, root, "large.txt", "replacement"),
    );
    const stat = try std.Io.Dir.cwd().statFile(std.testing.io, root ++ "/large.txt", .{});
    try std.testing.expectEqual(@as(u64, max_backup_bytes + 1), stat.size);
    try std.testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().statFile(std.testing.io, root ++ "/.velocity/backups/large.txt.bak", .{}),
    );
}

test "backup paths cannot escape the workspace store" {
    var out: [max_backup_path_len]u8 = undefined;
    try std.testing.expectError(error.InvalidPath, pathFor("../outside.txt", &out));
    try std.testing.expectError(error.InvalidPath, pathFor("/absolute.txt", &out));
}

test "restore roundtrips stable backup without consuming it" {
    const root = "zig-out/test-backup-restore";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = root ++ "/a.txt",
        .data = "before",
    });

    try overwrite(std.testing.io, root, "a.txt", "after");
    try restore(std.testing.io, root, "a.txt");

    var out: [32]u8 = undefined;
    const current = try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/a.txt", &out);
    try std.testing.expectEqualStrings("before", current);
    try std.testing.expectEqual(
        @as(usize, "before".len),
        try read(std.testing.io, root, "a.txt", &out),
    );
}

test "overwrite rotates three bounded backup generations" {
    const root = "zig-out/test-backup-generations";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "v0" });

    try overwrite(std.testing.io, root, "a.txt", "v1");
    try overwrite(std.testing.io, root, "a.txt", "v2");
    try overwrite(std.testing.io, root, "a.txt", "v3");
    try overwrite(std.testing.io, root, "a.txt", "v4");

    var out: [8]u8 = undefined;
    try std.testing.expectEqualStrings(
        "v3",
        try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/.velocity/backups/a.txt.bak", &out),
    );
    try std.testing.expectEqualStrings(
        "v2",
        try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/.velocity/backups/a.txt.bak.1", &out),
    );
    try std.testing.expectEqualStrings(
        "v1",
        try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/.velocity/backups/a.txt.bak.2", &out),
    );
    try restore(std.testing.io, root, "a.txt");
    try std.testing.expectEqualStrings(
        "v3",
        try std.Io.Dir.cwd().readFile(std.testing.io, root ++ "/a.txt", &out),
    );
}

test "read chooses newest available backup generation" {
    const root = "zig-out/test-backup-newest-available";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root ++ "/.velocity/backups");
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = root ++ "/.velocity/backups/a.txt.bak.1",
        .data = "second-newest",
    });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = root ++ "/.velocity/backups/a.txt.bak.2",
        .data = "oldest",
    });

    var out: [32]u8 = undefined;
    const len = try read(std.testing.io, root, "a.txt", &out);
    try std.testing.expectEqualStrings("second-newest", out[0..len]);
}
