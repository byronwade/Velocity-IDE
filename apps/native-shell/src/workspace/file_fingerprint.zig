//! Bounded file fingerprints for safe-save conflict detection.
//! Uses the same editor read cap and performs no background work.

const std = @import("std");
const scanner = @import("scanner.zig");

pub const Fingerprint = struct {
    hash: u64 = 0,
    len: usize = 0,
    valid: bool = false,
};

pub fn ofBytes(bytes: []const u8) Fingerprint {
    var hash: u64 = 14695981039346656037;
    for (bytes) |byte| {
        hash ^= byte;
        hash *%= 1099511628211;
    }
    return .{ .hash = hash, .len = bytes.len, .valid = true };
}

pub fn capture(io: std.Io, root: []const u8, rel: []const u8) !Fingerprint {
    var buf: [scanner.max_file_bytes]u8 = undefined;
    const n = try scanner.readTextFile(io, root, rel, &buf);
    return ofBytes(buf[0..n]);
}

pub fn changed(io: std.Io, root: []const u8, rel: []const u8, baseline: Fingerprint) bool {
    if (!baseline.valid) return false;
    const current = capture(io, root, rel) catch return true;
    return current.len != baseline.len or current.hash != baseline.hash;
}

test "fingerprint detects same-size content changes" {
    const root = "zig-out/test-file-fingerprint";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "one" });
    const baseline = try capture(std.testing.io, root, "a.txt");
    try std.testing.expect(!changed(std.testing.io, root, "a.txt", baseline));
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = root ++ "/a.txt", .data = "two" });
    try std.testing.expect(changed(std.testing.io, root, "a.txt", baseline));
}
