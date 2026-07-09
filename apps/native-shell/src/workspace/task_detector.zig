//! Bounded discovery of runnable npm scripts from a workspace package.json.

const std = @import("std");
const scanner = @import("scanner.zig");

pub const max_tasks: usize = 32;
pub const max_name_len: usize = 64;
pub const max_command_len: usize = 256;
pub const max_package_bytes: usize = scanner.max_file_bytes;
const json_scratch_bytes: usize = max_package_bytes * 2;

pub const Task = struct {
    id: u32 = 0,
    name: []const u8 = "",
    command: []const u8 = "",
};

pub const DetectError = error{
    FileNotFound,
    AccessDenied,
    PackageTooLarge,
    InvalidPackage,
    TooManyTasks,
    NameTooLong,
    CommandTooLong,
};

pub const TaskDetector = struct {
    tasks: [max_tasks]Task = [_]Task{.{}} ** max_tasks,
    task_count: u32 = 0,
    name_pool: [max_tasks][max_name_len]u8 = undefined,
    name_lens: [max_tasks]usize = [_]usize{0} ** max_tasks,
    command_pool: [max_tasks][max_command_len]u8 = undefined,
    command_lens: [max_tasks]usize = [_]usize{0} ** max_tasks,

    pub fn tasksSlice(self: *const TaskDetector) []const Task {
        return self.tasks[0..self.task_count];
    }

    pub fn clear(self: *TaskDetector) void {
        self.task_count = 0;
    }

    /// Read and parse the root package.json without allocating from the caller.
    pub fn discover(self: *TaskDetector, io: std.Io, root_path: []const u8) DetectError!u32 {
        var root = std.Io.Dir.cwd().openDir(io, root_path, .{}) catch |err| {
            return switch (err) {
                error.FileNotFound, error.NotDir => error.FileNotFound,
                else => error.AccessDenied,
            };
        };
        defer root.close(io);

        // The extra byte makes an exact max-sized file unambiguous.
        var package_buf: [max_package_bytes + 1]u8 = undefined;
        const package = root.readFile(io, "package.json", package_buf[0..]) catch |err| {
            return switch (err) {
                error.FileNotFound => error.FileNotFound,
                else => error.AccessDenied,
            };
        };
        if (package.len > max_package_bytes) return error.PackageTooLarge;
        return self.parse(package);
    }

    /// Parse package.json bytes and retain only bounded copies of script names and commands.
    pub fn parse(self: *TaskDetector, package: []const u8) DetectError!u32 {
        self.clear();
        errdefer self.clear();
        if (package.len > max_package_bytes) return error.PackageTooLarge;

        var json_scratch: [json_scratch_bytes]u8 = undefined;
        var fixed = std.heap.FixedBufferAllocator.init(json_scratch[0..]);
        const allocator = fixed.allocator();
        var json = std.json.Scanner.initCompleteInput(allocator, package);
        defer json.deinit();

        const first = json.nextAllocMax(allocator, .alloc_if_needed, max_package_bytes) catch return error.InvalidPackage;
        if (first != .object_begin) return error.InvalidPackage;

        var found_scripts = false;
        while (true) {
            const key_token = json.nextAllocMax(allocator, .alloc_if_needed, max_package_bytes) catch
                return error.InvalidPackage;
            if (key_token == .object_end) break;
            const key = tokenString(key_token) orelse return error.InvalidPackage;
            if (std.mem.eql(u8, key, "scripts")) {
                if (found_scripts) return error.InvalidPackage;
                found_scripts = true;
                try self.parseScripts(&json, allocator);
            } else {
                json.skipValue() catch return error.InvalidPackage;
            }
        }

        const last = json.nextAllocMax(allocator, .alloc_if_needed, max_package_bytes) catch return error.InvalidPackage;
        if (last != .end_of_document) return error.InvalidPackage;
        return self.task_count;
    }

    fn parseScripts(
        self: *TaskDetector,
        json: *std.json.Scanner,
        allocator: std.mem.Allocator,
    ) DetectError!void {
        const begin = json.nextAllocMax(allocator, .alloc_if_needed, max_name_len) catch return error.InvalidPackage;
        if (begin != .object_begin) return error.InvalidPackage;

        while (true) {
            const name_token = json.nextAllocMax(allocator, .alloc_if_needed, max_name_len) catch |err| {
                return switch (err) {
                    error.ValueTooLong => error.NameTooLong,
                    else => error.InvalidPackage,
                };
            };
            if (name_token == .object_end) break;
            const name = tokenString(name_token) orelse return error.InvalidPackage;
            if (name.len == 0) return error.InvalidPackage;

            const command_token = json.nextAllocMax(allocator, .alloc_if_needed, max_command_len) catch |err| {
                return switch (err) {
                    error.ValueTooLong => error.CommandTooLong,
                    else => error.InvalidPackage,
                };
            };
            const command = tokenString(command_token) orelse return error.InvalidPackage;
            try self.push(name, command);
        }
    }

    fn push(self: *TaskDetector, name: []const u8, command: []const u8) DetectError!void {
        if (self.task_count >= max_tasks) return error.TooManyTasks;
        if (name.len > max_name_len) return error.NameTooLong;
        if (command.len > max_command_len) return error.CommandTooLong;

        const index: usize = self.task_count;
        @memcpy(self.name_pool[index][0..name.len], name);
        self.name_lens[index] = name.len;
        @memcpy(self.command_pool[index][0..command.len], command);
        self.command_lens[index] = command.len;
        self.tasks[index] = .{
            .id = self.task_count + 1,
            .name = self.name_pool[index][0..name.len],
            .command = self.command_pool[index][0..command.len],
        };
        self.task_count += 1;
    }
};

fn tokenString(token: std.json.Token) ?[]const u8 {
    return switch (token) {
        .string, .allocated_string => |value| value,
        else => null,
    };
}

test "discovers package scripts from fixture" {
    var detector: TaskDetector = .{};
    const count = try detector.discover(std.testing.io, "fixtures/acme-dashboard");
    try std.testing.expectEqual(@as(u32, 3), count);
    try std.testing.expectEqualStrings("dev", detector.tasksSlice()[0].name);
    try std.testing.expectEqualStrings("next dev", detector.tasksSlice()[0].command);
    try std.testing.expectEqualStrings("test", detector.tasksSlice()[1].name);
    try std.testing.expectEqualStrings("vitest", detector.tasksSlice()[1].command);
    try std.testing.expectEqualStrings("task-smoke", detector.tasksSlice()[2].name);
}

test "decodes escaped script strings into owned bounded pools" {
    var detector: TaskDetector = .{};
    const count = try detector.parse(
        \\{"name":"fixture","scripts":{"check":"echo \"ok\"","path\\name":"run"}}
    );
    try std.testing.expectEqual(@as(u32, 2), count);
    try std.testing.expectEqualStrings("echo \"ok\"", detector.tasksSlice()[0].command);
    try std.testing.expectEqualStrings("path\\name", detector.tasksSlice()[1].name);
}

test "rejects more scripts than the bounded task pool" {
    var package_buf: [max_package_bytes]u8 = undefined;
    var writer: std.Io.Writer = .fixed(package_buf[0..]);
    try writer.writeAll("{\"scripts\":{");
    var index: usize = 0;
    while (index <= max_tasks) : (index += 1) {
        if (index != 0) try writer.writeByte(',');
        try writer.print("\"task-{d}\":\"run\"", .{index});
    }
    try writer.writeAll("}}");

    var detector: TaskDetector = .{};
    try std.testing.expectError(error.TooManyTasks, detector.parse(writer.buffered()));
    try std.testing.expectEqual(@as(u32, 0), detector.task_count);
}
