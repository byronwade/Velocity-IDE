//! Bounded discovery of runnable workspace tasks.
//! Precedence is deterministic: npm scripts, VS Code tasks, then Make targets.

const std = @import("std");
const scanner = @import("scanner.zig");

pub const max_tasks: usize = 32;
pub const max_name_len: usize = 64;
pub const max_command_len: usize = 256;
pub const max_package_bytes: usize = scanner.max_file_bytes;
const json_scratch_bytes: usize = max_package_bytes * 2;

pub const Source = enum { npm, vscode, make };

pub const Task = struct {
    id: u32 = 0,
    name: []const u8 = "",
    command: []const u8 = "",
    source: Source = .npm,
    source_label: []const u8 = "npm",
    display_label: []const u8 = "",
};

pub const DetectError = error{
    FileNotFound,
    AccessDenied,
    PackageTooLarge,
    InvalidPackage,
    InvalidTasks,
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
    display_pool: [max_tasks][max_name_len + 16]u8 = undefined,

    pub fn tasksSlice(self: *const TaskDetector) []const Task {
        return self.tasks[0..self.task_count];
    }

    pub fn clear(self: *TaskDetector) void {
        self.task_count = 0;
    }

    /// Read supported root task files without allocating from the caller.
    pub fn discover(self: *TaskDetector, io: std.Io, root_path: []const u8) DetectError!u32 {
        self.clear();
        errdefer self.clear();
        var root = std.Io.Dir.cwd().openDir(io, root_path, .{}) catch |err| {
            return switch (err) {
                error.FileNotFound, error.NotDir => error.FileNotFound,
                else => error.AccessDenied,
            };
        };
        defer root.close(io);

        var found_source = false;
        var file_buf: [max_package_bytes + 1]u8 = undefined;
        if (root.readFile(io, "package.json", file_buf[0..])) |package| {
            found_source = true;
            if (package.len > max_package_bytes) return error.PackageTooLarge;
            try self.parsePackageInto(package);
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => return error.AccessDenied,
        }

        if (root.readFile(io, ".vscode/tasks.json", file_buf[0..])) |tasks_json| {
            found_source = true;
            if (tasks_json.len > max_package_bytes) return error.PackageTooLarge;
            try self.parseTasksJsonInto(tasks_json);
        } else |err| switch (err) {
            error.FileNotFound, error.NotDir => {},
            else => return error.AccessDenied,
        }

        if (root.readFile(io, "Makefile", file_buf[0..])) |makefile| {
            found_source = true;
            if (makefile.len > max_package_bytes) return error.PackageTooLarge;
            try self.parseMakefileInto(makefile);
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => return error.AccessDenied,
        }
        if (!found_source) return error.FileNotFound;
        return self.task_count;
    }

    /// Parse package.json bytes and retain only bounded copies of script names and commands.
    pub fn parse(self: *TaskDetector, package: []const u8) DetectError!u32 {
        self.clear();
        errdefer self.clear();
        try self.parsePackageInto(package);
        return self.task_count;
    }

    fn parsePackageInto(self: *TaskDetector, package: []const u8) DetectError!void {
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
            try self.push(name, command, .npm);
        }
    }

    pub fn parseTasksJson(self: *TaskDetector, tasks_json: []const u8) DetectError!u32 {
        self.clear();
        errdefer self.clear();
        try self.parseTasksJsonInto(tasks_json);
        return self.task_count;
    }

    fn parseTasksJsonInto(self: *TaskDetector, tasks_json: []const u8) DetectError!void {
        if (tasks_json.len > max_package_bytes) return error.PackageTooLarge;
        var json_scratch: [json_scratch_bytes]u8 = undefined;
        var fixed = std.heap.FixedBufferAllocator.init(json_scratch[0..]);
        const allocator = fixed.allocator();
        var json = std.json.Scanner.initCompleteInput(allocator, tasks_json);
        defer json.deinit();

        if ((json.nextAllocMax(allocator, .alloc_if_needed, max_package_bytes) catch return error.InvalidTasks) != .object_begin) {
            return error.InvalidTasks;
        }
        var found_tasks = false;
        while (true) {
            const key_token = json.nextAllocMax(allocator, .alloc_if_needed, max_package_bytes) catch return error.InvalidTasks;
            if (key_token == .object_end) break;
            const key = tokenString(key_token) orelse return error.InvalidTasks;
            if (std.mem.eql(u8, key, "tasks")) {
                if (found_tasks) return error.InvalidTasks;
                found_tasks = true;
                try self.parseTasksArray(&json, allocator);
            } else {
                json.skipValue() catch return error.InvalidTasks;
            }
        }
        if ((json.nextAllocMax(allocator, .alloc_if_needed, max_package_bytes) catch return error.InvalidTasks) != .end_of_document) {
            return error.InvalidTasks;
        }
    }

    fn parseTasksArray(
        self: *TaskDetector,
        json: *std.json.Scanner,
        allocator: std.mem.Allocator,
    ) DetectError!void {
        if ((json.nextAllocMax(allocator, .alloc_if_needed, max_package_bytes) catch return error.InvalidTasks) != .array_begin) {
            return error.InvalidTasks;
        }
        while (true) {
            const token = json.nextAllocMax(allocator, .alloc_if_needed, max_package_bytes) catch return error.InvalidTasks;
            if (token == .array_end) break;
            if (token != .object_begin) return error.InvalidTasks;
            try self.parseTaskObject(json, allocator);
        }
    }

    fn parseTaskObject(
        self: *TaskDetector,
        json: *std.json.Scanner,
        allocator: std.mem.Allocator,
    ) DetectError!void {
        var name: []const u8 = "";
        var command: []const u8 = "";
        var kind: []const u8 = "";
        var args_buf: [max_command_len]u8 = undefined;
        var args_len: usize = 0;
        while (true) {
            const key_token = json.nextAllocMax(allocator, .alloc_if_needed, max_package_bytes) catch return error.InvalidTasks;
            if (key_token == .object_end) break;
            const key = tokenString(key_token) orelse return error.InvalidTasks;
            if (std.mem.eql(u8, key, "label")) {
                name = tokenString(json.nextAllocMax(allocator, .alloc_if_needed, max_name_len) catch |err| {
                    return if (err == error.ValueTooLong) error.NameTooLong else error.InvalidTasks;
                }) orelse return error.InvalidTasks;
            } else if (std.mem.eql(u8, key, "command")) {
                command = tokenString(json.nextAllocMax(allocator, .alloc_if_needed, max_command_len) catch |err| {
                    return if (err == error.ValueTooLong) error.CommandTooLong else error.InvalidTasks;
                }) orelse return error.InvalidTasks;
            } else if (std.mem.eql(u8, key, "type")) {
                kind = tokenString(json.nextAllocMax(allocator, .alloc_if_needed, 16) catch return error.InvalidTasks) orelse
                    return error.InvalidTasks;
            } else if (std.mem.eql(u8, key, "args")) {
                args_len = try parseArgs(json, allocator, &args_buf);
            } else {
                json.skipValue() catch return error.InvalidTasks;
            }
        }
        if (name.len == 0 or command.len == 0) return;
        if (!std.mem.eql(u8, kind, "shell") and !std.mem.eql(u8, kind, "process")) return;
        var full: [max_command_len]u8 = undefined;
        var used: usize = 0;
        if (std.mem.eql(u8, kind, "process")) {
            if (!appendShellQuoted(&full, &used, command)) return error.CommandTooLong;
        } else {
            if (command.len > full.len) return error.CommandTooLong;
            @memcpy(full[0..command.len], command);
            used = command.len;
        }
        if (used + args_len > full.len) return error.CommandTooLong;
        @memcpy(full[used..][0..args_len], args_buf[0..args_len]);
        used += args_len;
        try self.push(name, full[0..used], .vscode);
    }

    pub fn parseMakefile(self: *TaskDetector, makefile: []const u8) DetectError!u32 {
        self.clear();
        errdefer self.clear();
        try self.parseMakefileInto(makefile);
        return self.task_count;
    }

    fn parseMakefileInto(self: *TaskDetector, makefile: []const u8) DetectError!void {
        if (makefile.len > max_package_bytes) return error.PackageTooLarge;
        var lines = std.mem.splitScalar(u8, makefile, '\n');
        while (lines.next()) |raw| {
            const line = std.mem.trimEnd(u8, raw, " \t\r");
            if (line.len == 0 or std.ascii.isWhitespace(line[0]) or line[0] == '#' or line[0] == '.') continue;
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            if (colon == 0 or (colon + 1 < line.len and line[colon + 1] == '=')) continue;
            const name = std.mem.trim(u8, line[0..colon], " \t");
            if (!isSimpleMakeTarget(name)) continue;
            var command: [max_command_len]u8 = undefined;
            var used: usize = 0;
            const prefix = "make -- ";
            @memcpy(command[0..prefix.len], prefix);
            used = prefix.len;
            if (!appendShellQuoted(&command, &used, name)) return error.CommandTooLong;
            try self.push(name, command[0..used], .make);
        }
    }

    fn push(self: *TaskDetector, name: []const u8, command: []const u8, source: Source) DetectError!void {
        for (self.tasksSlice()) |existing| {
            if (std.mem.eql(u8, existing.name, name)) return;
        }
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
            .source = source,
            .source_label = sourceLabel(source),
            .display_label = std.fmt.bufPrint(
                &self.display_pool[index],
                "{s} · {s}",
                .{ sourceLabel(source), self.name_pool[index][0..name.len] },
            ) catch self.name_pool[index][0..name.len],
        };
        self.task_count += 1;
    }
};

fn sourceLabel(source: Source) []const u8 {
    return switch (source) {
        .npm => "npm",
        .vscode => "tasks.json",
        .make => "Makefile",
    };
}

fn parseArgs(
    json: *std.json.Scanner,
    allocator: std.mem.Allocator,
    out: []u8,
) DetectError!usize {
    if ((json.nextAllocMax(allocator, .alloc_if_needed, max_command_len) catch return error.InvalidTasks) != .array_begin) {
        return error.InvalidTasks;
    }
    var used: usize = 0;
    while (true) {
        const token = json.nextAllocMax(allocator, .alloc_if_needed, max_command_len) catch |err| {
            return if (err == error.ValueTooLong) error.CommandTooLong else error.InvalidTasks;
        };
        if (token == .array_end) break;
        const arg = tokenString(token) orelse return error.InvalidTasks;
        if (used >= out.len) return error.CommandTooLong;
        out[used] = ' ';
        used += 1;
        if (!appendShellQuoted(out, &used, arg)) return error.CommandTooLong;
    }
    return used;
}

fn appendShellQuoted(out: []u8, used: *usize, value: []const u8) bool {
    if (used.* >= out.len) return false;
    out[used.*] = '\'';
    used.* += 1;
    for (value) |byte| {
        if (byte == '\'') {
            const escaped = "'\\''";
            if (used.* + escaped.len > out.len) return false;
            @memcpy(out[used.*..][0..escaped.len], escaped);
            used.* += escaped.len;
        } else {
            if (used.* >= out.len) return false;
            out[used.*] = byte;
            used.* += 1;
        }
    }
    if (used.* >= out.len) return false;
    out[used.*] = '\'';
    used.* += 1;
    return true;
}

fn isSimpleMakeTarget(name: []const u8) bool {
    if (name.len == 0 or name.len > max_name_len or std.mem.indexOfAny(u8, name, " \t%$") != null) return false;
    for (name) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '-' and byte != '.' and byte != '/') return false;
    }
    return true;
}

fn tokenString(token: std.json.Token) ?[]const u8 {
    return switch (token) {
        .string, .allocated_string => |value| value,
        else => null,
    };
}

test "discovers package scripts from fixture" {
    var detector: TaskDetector = .{};
    const count = try detector.discover(std.testing.io, "fixtures/acme-dashboard");
    try std.testing.expectEqual(@as(u32, 5), count);
    try std.testing.expectEqualStrings("dev", detector.tasksSlice()[0].name);
    try std.testing.expectEqualStrings("next dev", detector.tasksSlice()[0].command);
    try std.testing.expectEqualStrings("npm", detector.tasksSlice()[0].source_label);
    try std.testing.expectEqualStrings("test", detector.tasksSlice()[1].name);
    try std.testing.expect(std.mem.indexOf(u8, detector.tasksSlice()[1].command, "velocity-test-smoke-pass") != null);
    try std.testing.expectEqualStrings("task-smoke", detector.tasksSlice()[2].name);
}

test "tasks json accepts bounded shell and process tasks" {
    var detector: TaskDetector = .{};
    const count = try detector.parseTasksJson(
        \\{"version":"2.0.0","tasks":[
        \\{"label":"check","type":"shell","command":"zig build test"},
        \\{"label":"test:unit","type":"process","command":"node","args":["smoke test.js","it's-ok"]},
        \\{"label":"ignored","type":"custom","command":"nope"}
        \\]}
    );
    try std.testing.expectEqual(@as(u32, 2), count);
    try std.testing.expectEqualStrings("tasks.json", detector.tasksSlice()[0].source_label);
    try std.testing.expectEqualStrings("'node' 'smoke test.js' 'it'\\''s-ok'", detector.tasksSlice()[1].command);
}

test "makefile keeps only simple public targets" {
    var detector: TaskDetector = .{};
    const count = try detector.parseMakefile(
        \\# comment
        \\.PHONY: test
        \\NAME := value
        \\test: setup
        \\    echo ok
        \\test-fast:
        \\pattern%:
    );
    try std.testing.expectEqual(@as(u32, 2), count);
    try std.testing.expectEqualStrings("make -- 'test'", detector.tasksSlice()[0].command);
    try std.testing.expectEqualStrings("Makefile", detector.tasksSlice()[0].source_label);
}

test "source precedence is first name wins" {
    var detector: TaskDetector = .{};
    _ = try detector.parse(
        \\{"scripts":{"test":"npm test"}}
    );
    try detector.parseTasksJsonInto(
        \\{"tasks":[{"label":"test","type":"shell","command":"vscode test"},{"label":"build","type":"shell","command":"build"}]}
    );
    try detector.parseMakefileInto("test:\nbuild:\nrelease:\n");
    try std.testing.expectEqual(@as(u32, 3), detector.task_count);
    try std.testing.expectEqual(Source.npm, detector.tasksSlice()[0].source);
    try std.testing.expectEqual(Source.vscode, detector.tasksSlice()[1].source);
    try std.testing.expectEqual(Source.make, detector.tasksSlice()[2].source);
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
