//! Bounded on-disk backups used immediately before an explicit overwrite.

const std = @import("std");
const scanner = @import("scanner.zig");

pub const max_backup_bytes = scanner.max_file_bytes;
pub const backup_prefix = ".velocity/backups/";
pub const backup_suffix = ".bak";
pub const max_backup_path_len = backup_prefix.len + scanner.max_rel_path_len + backup_suffix.len;

fn validateRelativePath(path: []const u8) !void {
    if (path.len == 0 or path.len > scanner.max_rel_path_len) return error.InvalidPath;
    if (path[0] == '/' or std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidPath;
    if (std.mem.indexOfScalar(u8, path, '\\') != null) return error.InvalidPath;

    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or
            std.mem.eql(u8, part, ".") or
            std.mem.eql(u8, part, "..")) return error.InvalidPath;
    }
}

/// Build the stable backup path for a workspace-relative file.
pub fn pathFor(original_path: []const u8, out: []u8) ![]const u8 {
    try validateRelativePath(original_path);
    const needed = backup_prefix.len + original_path.len + backup_suffix.len;
    if (needed > out.len) return error.PathTooLong;
    @memcpy(out[0..backup_prefix.len], backup_prefix);
    @memcpy(out[backup_prefix.len..][0..original_path.len], original_path);
    @memcpy(out[backup_prefix.len + original_path.len ..][0..backup_suffix.len], backup_suffix);
    return out[0..needed];
}

/// Copy the current file into the bounded backup store.
/// Oversized files are rejected before the backup destination is opened.
pub fn backupBeforeOverwrite(io: std.Io, root_path: []const u8, original_path: []const u8) !void {
    var bytes: [max_backup_bytes]u8 = undefined;
    const len = try scanner.readTextFile(io, root_path, original_path, &bytes);
    var path_buf: [max_backup_path_len]u8 = undefined;
    const backup_path = try pathFor(original_path, &path_buf);
    try scanner.writeTextFile(io, root_path, backup_path, bytes[0..len]);
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
