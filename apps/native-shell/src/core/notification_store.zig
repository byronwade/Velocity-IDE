//! Fixed-capacity structured notifications with deterministic deduplication.

const std = @import("std");

pub const max_items: usize = 16;
pub const max_text_len: usize = 160;

pub const Severity = enum {
    info,
    warning,
    @"error",

    pub fn label(value: Severity) []const u8 {
        return switch (value) {
            .info => "Info",
            .warning => "Warning",
            .@"error" => "Error",
        };
    }
};

pub const Source = enum {
    system,
    workspace,
    task,
    @"test",
    launch,
    git,

    pub fn label(value: Source) []const u8 {
        return switch (value) {
            .system => "System",
            .workspace => "Workspace",
            .task => "Task",
            .@"test" => "Test",
            .launch => "Launch",
            .git => "Git",
        };
    }
};

pub const SeverityFilter = enum { all, info, warning, @"error" };
pub const SourceFilter = enum { all, system, workspace, task, @"test", launch, git };

pub const Action = enum {
    none,
    open_problems,
    reload_workspace,

    pub fn id(value: Action) []const u8 {
        return switch (value) {
            .none => "",
            .open_problems => "open_problems",
            .reload_workspace => "reload_workspace",
        };
    }

    pub fn label(value: Action) []const u8 {
        return switch (value) {
            .none => "",
            .open_problems => "Open Problems",
            .reload_workspace => "Reload Workspace",
        };
    }
};

pub const Item = struct {
    id: u32 = 0,
    severity: Severity = .info,
    severity_label: []const u8 = "Info",
    source: Source = .system,
    source_label: []const u8 = "System",
    text: []const u8 = "",
    count: u32 = 1,
    action: Action = .none,
    action_id: []const u8 = "",
    action_label: []const u8 = "",
    has_action: bool = false,
};

pub const Store = struct {
    items: [max_items]Item = [_]Item{.{}} ** max_items,
    filtered: [max_items]Item = [_]Item{.{}} ** max_items,
    text_pool: [max_items][max_text_len]u8 = undefined,
    text_lens: [max_items]usize = [_]usize{0} ** max_items,
    item_count: u32 = 0,
    filtered_count: u32 = 0,
    next_id: u32 = 1,
    severity_filter: SeverityFilter = .all,
    source_filter: SourceFilter = .all,

    pub fn slice(self: *const Store) []const Item {
        return self.filtered[0..self.filtered_count];
    }

    pub fn push(self: *Store, severity: Severity, source: Source, text: []const u8, action: Action) void {
        if (text.len == 0) return;
        const bounded = text[0..@min(text.len, max_text_len)];
        for (self.items[0..self.item_count]) |*item| {
            if (item.severity == severity and item.source == source and std.mem.eql(u8, item.text, bounded)) {
                item.count +|= 1;
                if (item.action == .none and action != .none) {
                    item.action = action;
                    item.action_id = action.id();
                    item.action_label = action.label();
                    item.has_action = true;
                }
                self.rebuild();
                return;
            }
        }

        var i: usize = max_items - 1;
        while (i > 0) : (i -= 1) {
            if (i - 1 >= self.item_count) continue;
            const len = self.text_lens[i - 1];
            @memcpy(self.text_pool[i][0..len], self.text_pool[i - 1][0..len]);
            self.text_lens[i] = len;
            const previous = self.items[i - 1];
            self.items[i] = previous;
            self.items[i].text = self.text_pool[i][0..len];
        }
        @memcpy(self.text_pool[0][0..bounded.len], bounded);
        self.text_lens[0] = bounded.len;
        self.items[0] = .{
            .id = self.next_id,
            .severity = severity,
            .severity_label = severity.label(),
            .source = source,
            .source_label = source.label(),
            .text = self.text_pool[0][0..bounded.len],
            .action = action,
            .action_id = action.id(),
            .action_label = action.label(),
            .has_action = action != .none,
        };
        self.next_id +%= 1;
        if (self.item_count < max_items) self.item_count += 1;
        self.rebuild();
    }

    pub fn setFilters(self: *Store, severity: SeverityFilter, source: SourceFilter) void {
        self.severity_filter = severity;
        self.source_filter = source;
        self.rebuild();
    }

    pub fn find(self: *const Store, id: u32) ?Item {
        for (self.items[0..self.item_count]) |item| {
            if (item.id == id) return item;
        }
        return null;
    }

    pub fn clear(self: *Store) void {
        self.item_count = 0;
        self.filtered_count = 0;
    }

    fn rebuild(self: *Store) void {
        self.filtered_count = 0;
        for (self.items[0..self.item_count]) |item| {
            if (!matchesSeverity(self.severity_filter, item.severity)) continue;
            if (!matchesSource(self.source_filter, item.source)) continue;
            self.filtered[self.filtered_count] = item;
            self.filtered_count += 1;
        }
    }
};

fn matchesSeverity(filter: SeverityFilter, severity: Severity) bool {
    return filter == .all or switch (severity) {
        .info => filter == .info,
        .warning => filter == .warning,
        .@"error" => filter == .@"error",
    };
}

fn matchesSource(filter: SourceFilter, source: Source) bool {
    return filter == .all or switch (source) {
        .system => filter == .system,
        .workspace => filter == .workspace,
        .task => filter == .task,
        .@"test" => filter == .@"test",
        .launch => filter == .launch,
        .git => filter == .git,
    };
}

test "dedupes and filters structured notifications" {
    var store: Store = .{};
    store.push(.@"error", .@"test", "failed", .open_problems);
    store.push(.@"error", .@"test", "failed", .open_problems);
    try std.testing.expectEqual(@as(u32, 1), store.item_count);
    try std.testing.expectEqual(@as(u32, 2), store.items[0].count);
    store.push(.info, .system, "ready", .none);
    try std.testing.expectEqual(@as(u32, 2), store.item_count);
    store.setFilters(.@"error", .@"test");
    try std.testing.expectEqual(@as(usize, 1), store.slice().len);
    try std.testing.expect(store.slice()[0].has_action);
}
