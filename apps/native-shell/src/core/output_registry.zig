//! Fixed-capacity, channel-aware Output registry.

const std = @import("std");

pub const max_lines: usize = 48;
pub const max_text_len: usize = 120;
pub const max_source_len: usize = 32;

pub const Channel = enum {
    all,
    task,
    @"test",
    launch,
    git,
    system,

    pub fn label(channel: Channel) []const u8 {
        return switch (channel) {
            .all => "All",
            .task => "Task",
            .@"test" => "Test",
            .launch => "Launch",
            .git => "Git",
            .system => "System",
        };
    }
};

pub const Line = struct {
    id: u32 = 0,
    channel: Channel = .system,
    channel_label: []const u8 = "System",
    source_label: []const u8 = "velocity",
    text: []const u8 = "",
};

pub const Registry = struct {
    storage: [max_lines]Line = [_]Line{.{}} ** max_lines,
    filtered: [max_lines]Line = [_]Line{.{}} ** max_lines,
    text_pool: [max_lines][max_text_len]u8 = undefined,
    text_lens: [max_lines]usize = [_]usize{0} ** max_lines,
    source_pool: [max_lines][max_source_len]u8 = undefined,
    source_lens: [max_lines]usize = [_]usize{0} ** max_lines,
    total_count: u32 = 0,
    filtered_count: u32 = 0,
    next_id: u32 = 1,
    selected: Channel = .all,

    pub fn lines(self: *const Registry) []const Line {
        return self.filtered[0..self.filtered_count];
    }

    pub fn append(self: *Registry, channel: Channel, source: []const u8, text: []const u8) void {
        if (text.len == 0) return;
        var i: usize = max_lines - 1;
        while (i > 0) : (i -= 1) {
            if (i - 1 >= self.total_count) continue;
            const text_len = self.text_lens[i - 1];
            @memcpy(self.text_pool[i][0..text_len], self.text_pool[i - 1][0..text_len]);
            self.text_lens[i] = text_len;
            const source_len = self.source_lens[i - 1];
            @memcpy(self.source_pool[i][0..source_len], self.source_pool[i - 1][0..source_len]);
            self.source_lens[i] = source_len;
            self.storage[i] = .{
                .id = self.storage[i - 1].id,
                .channel = self.storage[i - 1].channel,
                .channel_label = self.storage[i - 1].channel_label,
                .source_label = self.source_pool[i][0..source_len],
                .text = self.text_pool[i][0..text_len],
            };
        }
        const text_len = @min(text.len, max_text_len);
        @memcpy(self.text_pool[0][0..text_len], text[0..text_len]);
        self.text_lens[0] = text_len;
        const source_len = @min(source.len, max_source_len);
        @memcpy(self.source_pool[0][0..source_len], source[0..source_len]);
        self.source_lens[0] = source_len;
        self.storage[0] = .{
            .id = self.next_id,
            .channel = channel,
            .channel_label = channel.label(),
            .source_label = self.source_pool[0][0..source_len],
            .text = self.text_pool[0][0..text_len],
        };
        self.next_id +%= 1;
        if (self.total_count < max_lines) self.total_count += 1;
        self.rebuild();
    }

    pub fn select(self: *Registry, channel: Channel) void {
        self.selected = channel;
        self.rebuild();
    }

    pub fn clearSelected(self: *Registry) void {
        if (self.selected == .all) {
            self.total_count = 0;
            self.filtered_count = 0;
            return;
        }
        var write: usize = 0;
        var read: usize = 0;
        while (read < self.total_count) : (read += 1) {
            if (self.storage[read].channel == self.selected) continue;
            if (write != read) self.copySlot(write, read);
            write += 1;
        }
        self.total_count = @intCast(write);
        self.rebuild();
    }

    pub fn count(self: *const Registry, channel: Channel) u32 {
        if (channel == .all) return self.total_count;
        var result: u32 = 0;
        for (self.storage[0..self.total_count]) |line| {
            if (line.channel == channel) result += 1;
        }
        return result;
    }

    fn copySlot(self: *Registry, dst: usize, src: usize) void {
        const text_len = self.text_lens[src];
        @memcpy(self.text_pool[dst][0..text_len], self.text_pool[src][0..text_len]);
        self.text_lens[dst] = text_len;
        const source_len = self.source_lens[src];
        @memcpy(self.source_pool[dst][0..source_len], self.source_pool[src][0..source_len]);
        self.source_lens[dst] = source_len;
        self.storage[dst] = .{
            .id = self.storage[src].id,
            .channel = self.storage[src].channel,
            .channel_label = self.storage[src].channel_label,
            .source_label = self.source_pool[dst][0..source_len],
            .text = self.text_pool[dst][0..text_len],
        };
    }

    fn rebuild(self: *Registry) void {
        self.filtered_count = 0;
        for (self.storage[0..self.total_count]) |line| {
            if (self.selected != .all and line.channel != self.selected) continue;
            self.filtered[self.filtered_count] = line;
            self.filtered_count += 1;
        }
    }
};

test "filters counts and clears one bounded channel" {
    var registry: Registry = .{};
    registry.append(.task, "npm", "task line");
    registry.append(.@"test", "npm", "test line");
    registry.append(.task, "Makefile", "other task");
    try std.testing.expectEqual(@as(u32, 3), registry.count(.all));
    try std.testing.expectEqual(@as(u32, 2), registry.count(.task));
    registry.select(.task);
    try std.testing.expectEqual(@as(usize, 2), registry.lines().len);
    try std.testing.expectEqualStrings("Makefile", registry.lines()[0].source_label);
    registry.clearSelected();
    try std.testing.expectEqual(@as(u32, 1), registry.count(.all));
    try std.testing.expectEqual(Channel.@"test", registry.storage[0].channel);
}
