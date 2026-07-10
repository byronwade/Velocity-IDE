//! Bounded `.velocity/launch.json` command profiles.
//! This is intentionally not compatible with VS Code Debug Adapter Protocol
//! launch configurations: profiles only describe governed shell commands.

const std = @import("std");
const scanner = @import("scanner.zig");

pub const rel_path = ".velocity/launch.json";
pub const schema_version: u32 = 1;
pub const max_profiles: usize = 12;
pub const max_env: usize = 12;
pub const max_name_len: usize = 64;
pub const max_command_len: usize = 256;
pub const max_cwd_len: usize = 160;
pub const max_env_key_len: usize = 48;
pub const max_env_value_len: usize = 128;
pub const max_file_bytes: usize = 16 * 1024;
pub const max_script_len: usize = 2048;
const json_scratch_bytes = max_file_bytes * 2;

pub const Env = struct {
    key: []const u8 = "",
    value: []const u8 = "",
};

pub const Profile = struct {
    id: u32 = 0,
    name: []const u8 = "",
    command: []const u8 = "",
    cwd: []const u8 = "",
    env: []const Env = &.{},
};

pub const LoadError = error{
    FileNotFound,
    AccessDenied,
    FileTooLarge,
    InvalidJson,
    UnsupportedVersion,
    InvalidSchema,
    DebugConfigurationRejected,
    TooManyProfiles,
    TooManyEnvironmentVariables,
    NameTooLong,
    CommandTooLong,
    CwdTooLong,
    EnvironmentTooLong,
    UnsafeCwd,
    VariablePlaceholderRejected,
    ScriptTooLong,
};

pub const Registry = struct {
    profiles: [max_profiles]Profile = [_]Profile{.{}} ** max_profiles,
    profile_count: u32 = 0,
    name_pool: [max_profiles][max_name_len]u8 = undefined,
    name_lens: [max_profiles]usize = [_]usize{0} ** max_profiles,
    command_pool: [max_profiles][max_command_len]u8 = undefined,
    command_lens: [max_profiles]usize = [_]usize{0} ** max_profiles,
    cwd_pool: [max_profiles][max_cwd_len]u8 = undefined,
    cwd_lens: [max_profiles]usize = [_]usize{0} ** max_profiles,
    env_storage: [max_profiles][max_env]Env = [_][max_env]Env{[_]Env{.{}} ** max_env} ** max_profiles,
    env_counts: [max_profiles]usize = [_]usize{0} ** max_profiles,
    env_key_pool: [max_profiles][max_env][max_env_key_len]u8 = undefined,
    env_key_lens: [max_profiles][max_env]usize = [_][max_env]usize{[_]usize{0} ** max_env} ** max_profiles,
    env_value_pool: [max_profiles][max_env][max_env_value_len]u8 = undefined,
    env_value_lens: [max_profiles][max_env]usize = [_][max_env]usize{[_]usize{0} ** max_env} ** max_profiles,

    pub fn slice(self: *const Registry) []const Profile {
        return self.profiles[0..self.profile_count];
    }

    pub fn clear(self: *Registry) void {
        self.profile_count = 0;
    }

    pub fn load(self: *Registry, io: std.Io, root_path: []const u8) LoadError!u32 {
        self.clear();
        errdefer self.clear();
        var root = std.Io.Dir.cwd().openDir(io, root_path, .{}) catch |err| {
            return switch (err) {
                error.FileNotFound, error.NotDir => error.FileNotFound,
                else => error.AccessDenied,
            };
        };
        defer root.close(io);
        var file_buf: [max_file_bytes + 1]u8 = undefined;
        const data = root.readFile(io, rel_path, &file_buf) catch |err| {
            return switch (err) {
                error.FileNotFound, error.NotDir => error.FileNotFound,
                error.FileTooBig => error.FileTooLarge,
                else => error.AccessDenied,
            };
        };
        if (data.len > max_file_bytes) return error.FileTooLarge;
        return self.parse(data);
    }

    pub fn parse(self: *Registry, data: []const u8) LoadError!u32 {
        self.clear();
        errdefer self.clear();
        if (data.len > max_file_bytes) return error.FileTooLarge;
        var scratch: [json_scratch_bytes]u8 = undefined;
        var fixed = std.heap.FixedBufferAllocator.init(&scratch);
        const allocator = fixed.allocator();
        var json = std.json.Scanner.initCompleteInput(allocator, data);
        defer json.deinit();
        if ((next(&json, allocator, max_file_bytes) catch return error.InvalidJson) != .object_begin) return error.InvalidJson;

        var saw_version = false;
        var saw_profiles = false;
        while (true) {
            const key_token = next(&json, allocator, max_file_bytes) catch return error.InvalidJson;
            if (key_token == .object_end) break;
            const key = tokenString(key_token) orelse return error.InvalidJson;
            if (isDebugKey(key)) return error.DebugConfigurationRejected;
            if (std.mem.eql(u8, key, "version")) {
                if (saw_version) return error.InvalidSchema;
                saw_version = true;
                const value = next(&json, allocator, 8) catch return error.InvalidJson;
                const raw = tokenNumber(value) orelse return error.InvalidSchema;
                const version = std.fmt.parseInt(u32, raw, 10) catch return error.InvalidSchema;
                if (version != schema_version) return error.UnsupportedVersion;
            } else if (std.mem.eql(u8, key, "profiles")) {
                if (saw_profiles) return error.InvalidSchema;
                saw_profiles = true;
                try self.parseProfiles(&json, allocator);
            } else {
                return error.InvalidSchema;
            }
        }
        if (!saw_version or !saw_profiles) return error.InvalidSchema;
        if ((next(&json, allocator, max_file_bytes) catch return error.InvalidJson) != .end_of_document) return error.InvalidJson;
        return self.profile_count;
    }

    fn parseProfiles(self: *Registry, json: *std.json.Scanner, allocator: std.mem.Allocator) LoadError!void {
        if ((next(json, allocator, max_file_bytes) catch return error.InvalidJson) != .array_begin) return error.InvalidSchema;
        while (true) {
            const token = next(json, allocator, max_file_bytes) catch return error.InvalidJson;
            if (token == .array_end) break;
            if (token != .object_begin) return error.InvalidSchema;
            if (self.profile_count >= max_profiles) return error.TooManyProfiles;
            try self.parseProfile(json, allocator, self.profile_count);
            self.profile_count += 1;
        }
    }

    fn parseProfile(
        self: *Registry,
        json: *std.json.Scanner,
        allocator: std.mem.Allocator,
        index: usize,
    ) LoadError!void {
        var name: []const u8 = "";
        var command: []const u8 = "";
        var cwd: []const u8 = "";
        var saw_env = false;
        while (true) {
            const key_token = next(json, allocator, max_file_bytes) catch return error.InvalidJson;
            if (key_token == .object_end) break;
            const key = tokenString(key_token) orelse return error.InvalidJson;
            if (isDebugKey(key)) return error.DebugConfigurationRejected;
            if (std.mem.eql(u8, key, "name")) {
                name = try readString(json, allocator, max_name_len, error.NameTooLong);
            } else if (std.mem.eql(u8, key, "command")) {
                command = try readString(json, allocator, max_command_len, error.CommandTooLong);
            } else if (std.mem.eql(u8, key, "cwd")) {
                cwd = try readString(json, allocator, max_cwd_len, error.CwdTooLong);
            } else if (std.mem.eql(u8, key, "env")) {
                if (saw_env) return error.InvalidSchema;
                saw_env = true;
                try self.parseEnv(json, allocator, index);
            } else {
                return error.InvalidSchema;
            }
        }
        if (name.len == 0 or command.len == 0) return error.InvalidSchema;
        if (hasPlaceholder(name) or hasPlaceholder(command) or hasPlaceholder(cwd)) return error.VariablePlaceholderRejected;
        if (!safeRelativeCwd(cwd)) return error.UnsafeCwd;
        for (self.profiles[0..index]) |profile| {
            if (std.mem.eql(u8, profile.name, name)) return error.InvalidSchema;
        }
        copyInto(&self.name_pool[index], &self.name_lens[index], name);
        copyInto(&self.command_pool[index], &self.command_lens[index], command);
        copyInto(&self.cwd_pool[index], &self.cwd_lens[index], cwd);
        self.profiles[index] = .{
            .id = @intCast(index + 1),
            .name = self.name_pool[index][0..self.name_lens[index]],
            .command = self.command_pool[index][0..self.command_lens[index]],
            .cwd = self.cwd_pool[index][0..self.cwd_lens[index]],
            .env = self.env_storage[index][0..self.env_counts[index]],
        };
    }

    fn parseEnv(
        self: *Registry,
        json: *std.json.Scanner,
        allocator: std.mem.Allocator,
        profile_index: usize,
    ) LoadError!void {
        if ((next(json, allocator, max_file_bytes) catch return error.InvalidJson) != .object_begin) return error.InvalidSchema;
        while (true) {
            const key_token = next(json, allocator, max_env_key_len) catch |err| {
                return if (err == error.ValueTooLong) error.EnvironmentTooLong else error.InvalidJson;
            };
            if (key_token == .object_end) break;
            const key = tokenString(key_token) orelse return error.InvalidSchema;
            if (!validEnvKey(key)) return error.InvalidSchema;
            const value = try readString(json, allocator, max_env_value_len, error.EnvironmentTooLong);
            if (hasPlaceholder(value)) return error.VariablePlaceholderRejected;
            const env_index = self.env_counts[profile_index];
            if (env_index >= max_env) return error.TooManyEnvironmentVariables;
            copyInto(&self.env_key_pool[profile_index][env_index], &self.env_key_lens[profile_index][env_index], key);
            copyInto(&self.env_value_pool[profile_index][env_index], &self.env_value_lens[profile_index][env_index], value);
            self.env_storage[profile_index][env_index] = .{
                .key = self.env_key_pool[profile_index][env_index][0..self.env_key_lens[profile_index][env_index]],
                .value = self.env_value_pool[profile_index][env_index][0..self.env_value_lens[profile_index][env_index]],
            };
            self.env_counts[profile_index] += 1;
        }
    }
};

pub fn buildScript(profile: Profile, workspace_root: []const u8, out: []u8) LoadError![]const u8 {
    var used: usize = 0;
    try append(out, &used, "cd ");
    try appendQuoted(out, &used, workspace_root);
    if (profile.cwd.len > 0) {
        try append(out, &used, "/");
        try appendQuoted(out, &used, profile.cwd);
    }
    try append(out, &used, " && env");
    for (profile.env) |item| {
        try append(out, &used, " ");
        try append(out, &used, item.key);
        try append(out, &used, "=");
        try appendQuoted(out, &used, item.value);
    }
    try append(out, &used, " /bin/sh -c ");
    try appendQuoted(out, &used, profile.command);
    return out[0..used];
}

fn next(json: *std.json.Scanner, allocator: std.mem.Allocator, limit: usize) !std.json.Token {
    return json.nextAllocMax(allocator, .alloc_if_needed, limit);
}

fn readString(
    json: *std.json.Scanner,
    allocator: std.mem.Allocator,
    limit: usize,
    too_long: LoadError,
) LoadError![]const u8 {
    const token = next(json, allocator, limit) catch |err| {
        return if (err == error.ValueTooLong) too_long else error.InvalidJson;
    };
    return tokenString(token) orelse error.InvalidSchema;
}

fn tokenString(token: std.json.Token) ?[]const u8 {
    return switch (token) {
        .string, .allocated_string => |value| value,
        else => null,
    };
}

fn tokenNumber(token: std.json.Token) ?[]const u8 {
    return switch (token) {
        .number, .allocated_number => |value| value,
        else => null,
    };
}

fn copyInto(out: []u8, len: *usize, value: []const u8) void {
    @memcpy(out[0..value.len], value);
    len.* = value.len;
}

fn safeRelativeCwd(cwd: []const u8) bool {
    if (cwd.len == 0 or std.mem.eql(u8, cwd, ".")) return true;
    if (cwd[0] == '/' or cwd[0] == '\\' or (cwd.len >= 2 and std.ascii.isAlphabetic(cwd[0]) and cwd[1] == ':')) return false;
    var parts = std.mem.tokenizeAny(u8, cwd, "/\\");
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, "..")) return false;
    }
    return true;
}

fn hasPlaceholder(value: []const u8) bool {
    return std.mem.indexOf(u8, value, "${") != null or
        std.mem.indexOf(u8, value, "$env:") != null or
        std.mem.indexOf(u8, value, "$workspace") != null or
        std.mem.indexOf(u8, value, "{{") != null;
}

fn validEnvKey(key: []const u8) bool {
    if (key.len == 0 or key.len > max_env_key_len) return false;
    if (!std.ascii.isAlphabetic(key[0]) and key[0] != '_') return false;
    for (key[1..]) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    }
    return true;
}

fn isDebugKey(key: []const u8) bool {
    const debug_keys = [_][]const u8{
        "configurations", "type",          "request",       "program",     "args",        "runtimeExecutable",
        "runtimeArgs",    "preLaunchTask", "postDebugTask", "debugServer", "stopOnEntry",
    };
    for (debug_keys) |debug_key| {
        if (std.mem.eql(u8, key, debug_key)) return true;
    }
    return false;
}

fn append(out: []u8, used: *usize, value: []const u8) LoadError!void {
    if (used.* + value.len > out.len) return error.ScriptTooLong;
    @memcpy(out[used.*..][0..value.len], value);
    used.* += value.len;
}

fn appendQuoted(out: []u8, used: *usize, value: []const u8) LoadError!void {
    try append(out, used, "'");
    for (value) |byte| {
        if (byte == '\'') {
            try append(out, used, "'\\''");
        } else {
            if (used.* >= out.len) return error.ScriptTooLong;
            out[used.*] = byte;
            used.* += 1;
        }
    }
    try append(out, used, "'");
}

test "parses bounded command profiles and builds quoted script" {
    var registry: Registry = .{};
    const count = try registry.parse(
        \\{"version":1,"profiles":[{"name":"Web","command":"npm run dev","cwd":"apps/web","env":{"PORT":"3100"}}]}
    );
    try std.testing.expectEqual(@as(u32, 1), count);
    try std.testing.expectEqualStrings("Web", registry.slice()[0].name);
    var script: [max_script_len]u8 = undefined;
    const built = try buildScript(registry.slice()[0], "fixtures/acme dashboard", &script);
    try std.testing.expectEqualStrings("cd 'fixtures/acme dashboard'/'apps/web' && env PORT='3100' /bin/sh -c 'npm run dev'", built);
}

test "rejects debug shape unsafe cwd and placeholders" {
    var registry: Registry = .{};
    try std.testing.expectError(error.DebugConfigurationRejected, registry.parse(
        \\{"version":1,"profiles":[{"name":"Debug","type":"node","command":"node app.js"}]}
    ));
    try std.testing.expectError(error.UnsafeCwd, registry.parse(
        \\{"version":1,"profiles":[{"name":"Escape","command":"echo ok","cwd":"../outside"}]}
    ));
    try std.testing.expectError(error.VariablePlaceholderRejected, registry.parse(
        \\{"version":1,"profiles":[{"name":"Vars","command":"echo ${workspaceFolder}"}]}
    ));
}
