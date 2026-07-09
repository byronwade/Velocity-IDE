//! Quick Open — deterministic bounded fuzzy/path ranking.

const std = @import("std");
const workspace_store = @import("workspace_store.zig");
const scanner = @import("scanner.zig");

pub const max_results: usize = 48;
pub const max_query: usize = 64;

pub const QuickItem = struct {
    id: u32 = 0,
    file_id: u32 = 0,
    name: []const u8 = "",
    path: []const u8 = "",
};

pub const QuickOpenBuffers = struct {
    items: [max_results]QuickItem = [_]QuickItem{.{}} ** max_results,
    item_count: u32 = 0,
    name_pool: [max_results][scanner.max_name_len]u8 = undefined,
    path_pool: [max_results][scanner.max_rel_path_len]u8 = undefined,
    name_lens: [max_results]usize = [_]usize{0} ** max_results,
    path_lens: [max_results]usize = [_]usize{0} ** max_results,
    status: []const u8 = "idle",

    pub fn itemsSlice(self: *QuickOpenBuffers) []const QuickItem {
        return self.items[0..self.item_count];
    }

    pub fn clear(self: *QuickOpenBuffers) void {
        self.item_count = 0;
        self.status = "idle";
    }

    pub fn filter(self: *QuickOpenBuffers, ws: *workspace_store.WorkspaceBuffers, query: []const u8) void {
        self.filterWithRecents(ws, query, &.{});
    }

    pub fn filterWithRecents(
        self: *QuickOpenBuffers,
        ws: *workspace_store.WorkspaceBuffers,
        query: []const u8,
        recent_paths: []const []const u8,
    ) void {
        self.clear();
        const q = std.mem.trim(u8, query, " \t");
        if (q.len == 0) {
            self.status = "no query";
            return;
        }
        var ranked: [max_results]RankedItem = undefined;
        var ranked_count: usize = 0;
        var i: u32 = 0;
        while (i < ws.file_node_count) : (i += 1) {
            const node = ws.file_nodes[i];
            if (node.is_dir) continue;
            const score = scorePath(node.name, node.path, q) orelse continue;
            const candidate: RankedItem = .{
                .file_id = node.id,
                .name = node.name,
                .path = node.path,
                .score = score,
                .recent_rank = recentRank(recent_paths, node.path),
            };
            insertRanked(&ranked, &ranked_count, candidate);
        }
        for (ranked[0..ranked_count]) |item| {
            self.push(item.file_id, item.name, item.path);
        }
        self.status = if (self.item_count == 0) "no files" else "done";
    }

    pub fn push(self: *QuickOpenBuffers, file_id: u32, name: []const u8, path: []const u8) void {
        const idx = self.item_count;
        const nlen = @min(name.len, self.name_pool[idx].len);
        @memcpy(self.name_pool[idx][0..nlen], name[0..nlen]);
        self.name_lens[idx] = nlen;
        const plen = @min(path.len, self.path_pool[idx].len);
        @memcpy(self.path_pool[idx][0..plen], path[0..plen]);
        self.path_lens[idx] = plen;
        self.items[idx] = .{
            .id = idx + 1,
            .file_id = file_id,
            .name = self.name_pool[idx][0..nlen],
            .path = self.path_pool[idx][0..plen],
        };
        self.item_count += 1;
    }
};

const MatchScore = struct {
    category: u8,
    detail: u16,
};

const RankedItem = struct {
    file_id: u32,
    name: []const u8,
    path: []const u8,
    score: MatchScore,
    recent_rank: u16,
};

fn scorePath(name: []const u8, path: []const u8, query: []const u8) ?MatchScore {
    if (std.ascii.eqlIgnoreCase(name, query)) return .{ .category = 0, .detail = 0 };
    if (startsWithIgnoreCase(name, query)) return .{ .category = 1, .detail = @intCast(name.len - query.len) };
    if (segmentPrefix(path, query)) |remainder| return .{ .category = 2, .detail = remainder };
    if (orderedFuzzy(path, query)) |gap| {
        // Contiguous matches deliberately use the lower-priority substring
        // class; fuzzy is for ordered, non-contiguous path characters.
        if (std.ascii.indexOfIgnoreCase(path, query) == null) return .{ .category = 3, .detail = gap };
    }
    if (std.ascii.indexOfIgnoreCase(path, query)) |index| {
        return .{ .category = 4, .detail = @intCast(@min(index, std.math.maxInt(u16))) };
    }
    return null;
}

fn startsWithIgnoreCase(text: []const u8, prefix: []const u8) bool {
    return text.len >= prefix.len and std.ascii.eqlIgnoreCase(text[0..prefix.len], prefix);
}

fn segmentPrefix(path: []const u8, query: []const u8) ?u16 {
    var start: usize = 0;
    var i: usize = 0;
    while (i <= path.len) : (i += 1) {
        if (i == path.len or path[i] == '/' or path[i] == '\\') {
            const segment = path[start..i];
            if (startsWithIgnoreCase(segment, query)) {
                return @intCast(@min(segment.len - query.len, std.math.maxInt(u16)));
            }
            start = i + 1;
        }
    }
    return null;
}

fn orderedFuzzy(path: []const u8, query: []const u8) ?u16 {
    var path_index: usize = 0;
    var first: ?usize = null;
    var last: usize = 0;
    for (query) |query_char| {
        var found = false;
        while (path_index < path.len) : (path_index += 1) {
            if (std.ascii.toLower(path[path_index]) == std.ascii.toLower(query_char)) {
                if (first == null) first = path_index;
                last = path_index;
                path_index += 1;
                found = true;
                break;
            }
        }
        if (!found) return null;
    }
    const span = last - first.? + 1;
    return @intCast(@min(span - query.len, std.math.maxInt(u16)));
}

fn recentRank(recent_paths: []const []const u8, path: []const u8) u16 {
    for (recent_paths, 0..) |recent, index| {
        if (std.mem.eql(u8, recent, path)) return @intCast(@min(index, std.math.maxInt(u16) - 1));
    }
    return std.math.maxInt(u16);
}

fn lessThan(left: RankedItem, right: RankedItem) bool {
    if (left.score.category != right.score.category) return left.score.category < right.score.category;
    if (left.score.detail != right.score.detail) return left.score.detail < right.score.detail;
    if (left.recent_rank != right.recent_rank) return left.recent_rank < right.recent_rank;
    const insensitive = std.ascii.orderIgnoreCase(left.path, right.path);
    if (insensitive != .eq) return insensitive == .lt;
    return std.mem.order(u8, left.path, right.path) == .lt;
}

fn insertRanked(items: *[max_results]RankedItem, count: *usize, candidate: RankedItem) void {
    var insert_at: usize = 0;
    while (insert_at < count.* and !lessThan(candidate, items[insert_at])) : (insert_at += 1) {}
    if (insert_at >= max_results) return;
    if (count.* < max_results) count.* += 1;
    var index = count.* - 1;
    while (index > insert_at) : (index -= 1) items[index] = items[index - 1];
    items[insert_at] = candidate;
}

test "quick open filters by name" {
    const ws = try std.testing.allocator.create(workspace_store.WorkspaceBuffers);
    defer std.testing.allocator.destroy(ws);
    ws.* = .{};
    _ = try ws.openPath(std.testing.io, "fixtures/acme-dashboard");
    var q: QuickOpenBuffers = .{};
    q.filter(ws, "auth");
    try std.testing.expect(q.item_count > 0);
    try std.testing.expect(std.mem.indexOf(u8, q.items[0].path, "auth") != null);
}

test "quick open ranking is stable and recent breaks score ties" {
    const ws = try std.testing.allocator.create(workspace_store.WorkspaceBuffers);
    defer std.testing.allocator.destroy(ws);
    ws.* = .{};
    _ = try ws.openPath(std.testing.io, "fixtures/acme-dashboard");
    var q: QuickOpenBuffers = .{};
    q.filterWithRecents(ws, "auth.ts", &.{"src/server/auth.ts"});
    try std.testing.expect(q.item_count > 0);
    try std.testing.expectEqualStrings("auth.ts", q.items[0].name);
    q.filter(ws, "srva");
    try std.testing.expect(q.item_count > 0);
    try std.testing.expect(std.mem.indexOf(u8, q.items[0].path, "server") != null);
}
