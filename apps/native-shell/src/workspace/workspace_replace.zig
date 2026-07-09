//! Bounded literal replacement across files already discovered in a workspace.
//! Preview validates every matching file before apply performs disk writes.

const std = @import("std");
const scanner = @import("scanner.zig");
const workspace_store = @import("workspace_store.zig");

pub const max_files: usize = 64;
pub const max_needle_len: usize = 128;
pub const max_replacement_len: usize = 256;

pub const FilePreview = struct {
    id: u32 = 0,
    path: []const u8 = "",
    replacements: u32 = 0,
    bytes_before: usize = 0,
    bytes_after: usize = 0,
};

pub const PreviewSummary = struct {
    files: u32 = 0,
    replacements: u32 = 0,
    bytes_before: usize = 0,
    bytes_after: usize = 0,
};

pub const ApplySummary = struct {
    files: u32 = 0,
    replacements: u32 = 0,
};

pub const ReplaceError = error{
    EmptyNeedle,
    NeedleTooLong,
    ReplacementTooLong,
    WorkspaceUnavailable,
    AccessDenied,
    FileTooLarge,
    OutputTooLarge,
    TooManyFiles,
    CountOverflow,
    WriteFailed,
};

pub const WorkspaceReplace = struct {
    previews: [max_files]FilePreview = [_]FilePreview{.{}} ** max_files,
    preview_count: u32 = 0,
    path_pool: [max_files][scanner.max_rel_path_len]u8 = undefined,
    path_lens: [max_files]usize = [_]usize{0} ** max_files,

    pub fn previewsSlice(self: *const WorkspaceReplace) []const FilePreview {
        return self.previews[0..self.preview_count];
    }

    pub fn clear(self: *WorkspaceReplace) void {
        self.preview_count = 0;
    }

    /// Calculate bounded literal replacements without changing disk contents.
    pub fn preview(
        self: *WorkspaceReplace,
        io: std.Io,
        workspace: *workspace_store.WorkspaceBuffers,
        needle: []const u8,
        replacement: []const u8,
        case_sensitive: bool,
    ) ReplaceError!PreviewSummary {
        self.clear();
        errdefer self.clear();
        try validateTerms(needle, replacement);
        if (workspace.rootPath().len == 0) return error.WorkspaceUnavailable;

        var root = std.Io.Dir.cwd().openDir(io, workspace.rootPath(), .{}) catch return error.WorkspaceUnavailable;
        defer root.close(io);

        var summary: PreviewSummary = .{};
        var file_buf: [scanner.max_file_bytes + 1]u8 = undefined;
        for (workspace.fileNodesSlice()) |node| {
            if (node.is_dir) continue;
            const text = (try readBoundedText(root, io, node.path, file_buf[0..])) orelse continue;
            const count = countLiteral(text, needle, case_sensitive);
            if (count == 0) continue;
            const bytes_after = try projectedSize(text.len, count, needle.len, replacement.len);
            try self.pushPreview(node.path, count, text.len, bytes_after);
            summary.files = try addU32(summary.files, 1);
            summary.replacements = try addU32(summary.replacements, count);
            summary.bytes_before = try addUsize(summary.bytes_before, text.len);
            summary.bytes_after = try addUsize(summary.bytes_after, bytes_after);
        }
        return summary;
    }

    /// Validate the full preview first, then apply replacements to matching disk files.
    /// Callers must separately resolve dirty in-memory editor buffers before invoking this.
    pub fn apply(
        self: *WorkspaceReplace,
        io: std.Io,
        workspace: *workspace_store.WorkspaceBuffers,
        needle: []const u8,
        replacement: []const u8,
        case_sensitive: bool,
    ) ReplaceError!ApplySummary {
        _ = try self.preview(io, workspace, needle, replacement, case_sensitive);
        if (self.preview_count == 0) return .{};

        var root = std.Io.Dir.cwd().openDir(io, workspace.rootPath(), .{}) catch return error.WorkspaceUnavailable;
        defer root.close(io);

        var summary: ApplySummary = .{};
        var file_buf: [scanner.max_file_bytes + 1]u8 = undefined;
        var output_buf: [scanner.max_file_bytes]u8 = undefined;
        for (self.previewsSlice()) |item| {
            // Re-read and revalidate so a changed file can never overflow the output pool.
            const text = (try readBoundedText(root, io, item.path, file_buf[0..])) orelse continue;
            const count = countLiteral(text, needle, case_sensitive);
            if (count == 0) continue;
            _ = try projectedSize(text.len, count, needle.len, replacement.len);
            const result = replaceLiteral(text, needle, replacement, case_sensitive, output_buf[0..]) orelse return error.OutputTooLarge;
            root.writeFile(io, .{
                .sub_path = item.path,
                .data = output_buf[0..result.out_len],
            }) catch return error.WriteFailed;
            summary.files = try addU32(summary.files, 1);
            summary.replacements = try addU32(summary.replacements, result.count);
        }
        return summary;
    }

    fn pushPreview(
        self: *WorkspaceReplace,
        path: []const u8,
        count: usize,
        bytes_before: usize,
        bytes_after: usize,
    ) ReplaceError!void {
        if (self.preview_count >= max_files) return error.TooManyFiles;
        if (path.len > scanner.max_rel_path_len) return error.AccessDenied;
        if (count > std.math.maxInt(u32)) return error.CountOverflow;
        const index: usize = self.preview_count;
        @memcpy(self.path_pool[index][0..path.len], path);
        self.path_lens[index] = path.len;
        self.previews[index] = .{
            .id = self.preview_count + 1,
            .path = self.path_pool[index][0..path.len],
            .replacements = @intCast(count),
            .bytes_before = bytes_before,
            .bytes_after = bytes_after,
        };
        self.preview_count += 1;
    }
};

fn validateTerms(needle: []const u8, replacement: []const u8) ReplaceError!void {
    if (needle.len == 0) return error.EmptyNeedle;
    if (needle.len > max_needle_len) return error.NeedleTooLong;
    if (replacement.len > max_replacement_len) return error.ReplacementTooLong;
}

fn readBoundedText(
    root: std.Io.Dir,
    io: std.Io,
    path: []const u8,
    out: []u8,
) ReplaceError!?[]const u8 {
    const text = root.readFile(io, path, out) catch |err| {
        return switch (err) {
            error.AccessDenied, error.PermissionDenied => error.AccessDenied,
            else => error.AccessDenied,
        };
    };
    if (text.len > scanner.max_file_bytes) return error.FileTooLarge;
    const check_len = @min(text.len, @as(usize, 512));
    if (std.mem.indexOfScalar(u8, text[0..check_len], 0) != null) return null;
    return text;
}

fn countLiteral(text: []const u8, needle: []const u8, case_sensitive: bool) usize {
    var count: usize = 0;
    var offset: usize = 0;
    while (offset < text.len) {
        const relative = indexLiteral(text[offset..], needle, case_sensitive) orelse break;
        count += 1;
        offset += relative + needle.len;
    }
    return count;
}

const ReplaceResult = struct {
    out_len: usize,
    count: u32,
};

fn replaceLiteral(
    text: []const u8,
    needle: []const u8,
    replacement: []const u8,
    case_sensitive: bool,
    out: []u8,
) ?ReplaceResult {
    var source_offset: usize = 0;
    var output_offset: usize = 0;
    var count: u32 = 0;
    while (source_offset < text.len) {
        const relative = indexLiteral(text[source_offset..], needle, case_sensitive) orelse break;
        const match_start = source_offset + relative;
        const prefix_len = match_start - source_offset;
        if (output_offset + prefix_len + replacement.len > out.len) return null;
        @memcpy(out[output_offset..][0..prefix_len], text[source_offset..match_start]);
        output_offset += prefix_len;
        @memcpy(out[output_offset..][0..replacement.len], replacement);
        output_offset += replacement.len;
        source_offset = match_start + needle.len;
        count += 1;
    }
    const tail = text[source_offset..];
    if (output_offset + tail.len > out.len) return null;
    @memcpy(out[output_offset..][0..tail.len], tail);
    return .{ .out_len = output_offset + tail.len, .count = count };
}

fn indexLiteral(text: []const u8, needle: []const u8, case_sensitive: bool) ?usize {
    return if (case_sensitive)
        std.mem.indexOf(u8, text, needle)
    else
        std.ascii.indexOfIgnoreCase(text, needle);
}

fn projectedSize(
    bytes_before: usize,
    count: usize,
    needle_len: usize,
    replacement_len: usize,
) ReplaceError!usize {
    const removed = count * needle_len;
    const retained = bytes_before - removed;
    if (replacement_len != 0 and count > (std.math.maxInt(usize) - retained) / replacement_len) {
        return error.OutputTooLarge;
    }
    const bytes_after = retained + count * replacement_len;
    if (bytes_after > scanner.max_file_bytes) return error.OutputTooLarge;
    return bytes_after;
}

fn addU32(left: u32, right: usize) ReplaceError!u32 {
    if (right > std.math.maxInt(u32) - left) return error.CountOverflow;
    return left + @as(u32, @intCast(right));
}

fn addUsize(left: usize, right: usize) ReplaceError!usize {
    if (right > std.math.maxInt(usize) - left) return error.CountOverflow;
    return left + right;
}

test "previews literal replacements in fixture without writing" {
    const workspace = try std.testing.allocator.create(workspace_store.WorkspaceBuffers);
    defer std.testing.allocator.destroy(workspace);
    workspace.* = .{};
    _ = try workspace.openPath(std.testing.io, "fixtures/acme-dashboard");

    var workflow: WorkspaceReplace = .{};
    const summary = try workflow.preview(
        std.testing.io,
        workspace,
        "createSession",
        "openSession",
        true,
    );
    try std.testing.expect(summary.files > 0);
    try std.testing.expect(summary.replacements > 0);
    try std.testing.expect(std.mem.indexOf(u8, workflow.previewsSlice()[0].path, "auth.ts") != null);

    var disk_buf: [scanner.max_file_bytes + 1]u8 = undefined;
    const disk = try std.Io.Dir.cwd().readFile(
        std.testing.io,
        "fixtures/acme-dashboard/src/server/auth.ts",
        disk_buf[0..],
    );
    try std.testing.expect(std.mem.indexOf(u8, disk, "createSession") != null);
}

test "applies bounded literal replacements across workspace files" {
    const root_path = "zig-out/test-workspace-replace";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root_path) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root_path) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root_path);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = root_path ++ "/a.txt",
        .data = "foo one foo\n",
    });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = root_path ++ "/b.txt",
        .data = "two foo\n",
    });
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = root_path ++ "/binary.bin",
        .data = "foo\x00foo",
    });

    const workspace = try std.testing.allocator.create(workspace_store.WorkspaceBuffers);
    defer std.testing.allocator.destroy(workspace);
    workspace.* = .{};
    _ = try workspace.openPath(std.testing.io, root_path);

    var workflow: WorkspaceReplace = .{};
    const preview_summary = try workflow.preview(std.testing.io, workspace, "foo", "longer", true);
    try std.testing.expectEqual(@as(u32, 2), preview_summary.files);
    try std.testing.expectEqual(@as(u32, 3), preview_summary.replacements);
    const apply_summary = try workflow.apply(std.testing.io, workspace, "foo", "longer", true);
    try std.testing.expectEqual(@as(u32, 2), apply_summary.files);
    try std.testing.expectEqual(@as(u32, 3), apply_summary.replacements);

    var disk_buf: [64]u8 = undefined;
    const a_disk = try std.Io.Dir.cwd().readFile(
        std.testing.io,
        root_path ++ "/a.txt",
        disk_buf[0..],
    );
    try std.testing.expectEqualStrings("longer one longer\n", a_disk);
    const b_disk = try std.Io.Dir.cwd().readFile(
        std.testing.io,
        root_path ++ "/b.txt",
        disk_buf[0..],
    );
    try std.testing.expectEqualStrings("two longer\n", b_disk);
}

test "case insensitive preview and apply use identical match semantics" {
    const root_path = "zig-out/test-workspace-replace-ignore-case";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root_path) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root_path) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root_path);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = root_path ++ "/a.txt",
        .data = "Alpha alpha ALPHA\n",
    });

    const workspace = try std.testing.allocator.create(workspace_store.WorkspaceBuffers);
    defer std.testing.allocator.destroy(workspace);
    workspace.* = .{};
    _ = try workspace.openPath(std.testing.io, root_path);

    var workflow: WorkspaceReplace = .{};
    const preview_summary = try workflow.preview(std.testing.io, workspace, "alpha", "beta", false);
    try std.testing.expectEqual(@as(u32, 3), preview_summary.replacements);
    const apply_summary = try workflow.apply(std.testing.io, workspace, "alpha", "beta", false);
    try std.testing.expectEqual(preview_summary.files, apply_summary.files);
    try std.testing.expectEqual(preview_summary.replacements, apply_summary.replacements);

    var disk_buf: [32]u8 = undefined;
    const disk = try std.Io.Dir.cwd().readFile(
        std.testing.io,
        root_path ++ "/a.txt",
        disk_buf[0..],
    );
    try std.testing.expectEqualStrings("beta beta beta\n", disk);
}

test "rejects oversized replacement output before changing disk" {
    const root_path = "zig-out/test-workspace-replace-oversized";
    std.Io.Dir.cwd().deleteTree(std.testing.io, root_path) catch {};
    defer std.Io.Dir.cwd().deleteTree(std.testing.io, root_path) catch {};
    try std.Io.Dir.cwd().createDirPath(std.testing.io, root_path);
    var source: [9000]u8 = undefined;
    @memset(source[0..], 'a');
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = root_path ++ "/large.txt",
        .data = source[0..],
    });

    const workspace = try std.testing.allocator.create(workspace_store.WorkspaceBuffers);
    defer std.testing.allocator.destroy(workspace);
    workspace.* = .{};
    _ = try workspace.openPath(std.testing.io, root_path);

    var workflow: WorkspaceReplace = .{};
    try std.testing.expectError(
        error.OutputTooLarge,
        workflow.apply(std.testing.io, workspace, "a", "aa", true),
    );
    try std.testing.expectEqual(@as(u32, 0), workflow.preview_count);

    var disk_buf: [9001]u8 = undefined;
    const disk = try std.Io.Dir.cwd().readFile(
        std.testing.io,
        root_path ++ "/large.txt",
        disk_buf[0..],
    );
    try std.testing.expectEqual(@as(usize, source.len), disk.len);
    try std.testing.expectEqualSlices(u8, source[0..], disk);
}
