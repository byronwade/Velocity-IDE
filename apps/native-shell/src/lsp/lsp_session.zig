//! App-side LSP session runtime: the bounded, pure wiring seams between
//! `broker_transport.zig` (the proven transport state machine) and the
//! app model's effects (Governor spawn, fetch POSTs, heartbeat timer).
//!
//! Everything here is deterministic and I/O-free except `probe`, which
//! takes the runtime `std.Io` plus the PATH string as parameters so the
//! availability check stays honest (no process is spawned before a
//! supported file opens AND the binaries exist).
//!
//! v1 scope: one broker, one language server (typescript-language-server),
//! one open document, publishDiagnostics into the Problems panel.

const std = @import("std");
const transport_mod = @import("broker_transport.zig");
const language_registry = @import("../core/language_registry.zig");

pub const server_command = "typescript-language-server";
pub const broker_binary_name = "velocity-lsp-broker";
/// Where the (not-yet-app-built) broker lands when built via
/// `scripts/build-lsp-broker.sh`, relative to the app's cwd.
pub const broker_build_rel_path = "zig-out/bin/velocity-lsp-broker";

pub const heartbeat_interval_ms: u64 = 10_000;
pub const hb_window_ms_arg = "--hb-window-ms=30000";
pub const max_broker_line_bytes: usize = transport_mod.max_line_bytes;
pub const max_out_queue: usize = 8;
/// Outgoing payload slot: bounded didOpen/didChange with the whole
/// document (<= 256 KiB) JSON-escaped, plus envelope headroom. Documents
/// whose escaped form exceeds this are skipped honestly (never split).
pub const max_out_slot_bytes: usize = 768 * 1024;
pub const max_path_bytes: usize = 512;

// -------------------------------------------------------------- status

/// Honest, user-visible session state ("LSP: <label>" in the Problems
/// panel header).
pub const Status = enum {
    off,
    unavailable_broker,
    unavailable_server,
    starting,
    running,
    stopped,
    failed,

    pub fn label(self: Status) []const u8 {
        return switch (self) {
            .off => "off",
            .unavailable_broker, .unavailable_server => "unavailable",
            .starting => "starting",
            .running => "running",
            .stopped => "stopped",
            .failed => "failed",
        };
    }

    pub fn detail(self: Status) []const u8 {
        return switch (self) {
            .unavailable_broker => "LSP broker binary not built; run scripts/build-lsp-broker.sh",
            .unavailable_server => "typescript-language-server not found on PATH",
            else => self.label(),
        };
    }
};

// --------------------------------------------------------- activation

/// The LSP languageId when `path` is served by typescript-language-server
/// in this slice (ts/tsx/js/jsx/mjs/cjs), else null.
pub fn languageIdForTsServer(path: []const u8) ?[]const u8 {
    if (path.len == 0) return null;
    const spec = language_registry.specForPath(path);
    for (spec.server_candidates) |candidate| {
        if (std.mem.eql(u8, candidate, server_command)) return spec.id;
    }
    return null;
}

/// Pure activation decision: toggle on AND workspace open AND a supported
/// file focused AND no earlier attempt this episode (honest unavailable
/// states persist instead of re-probing every message).
pub fn shouldActivate(
    enabled: bool,
    workspace_open: bool,
    already_attempted: bool,
    active_path: []const u8,
) bool {
    if (!enabled or !workspace_open or already_attempted) return false;
    return languageIdForTsServer(active_path) != null;
}

// -------------------------------------------------------- availability

pub const Availability = union(enum) {
    available: struct { broker: []const u8, server: []const u8 },
    no_broker,
    no_server,
};

/// Discover the broker binary (local build output first, then PATH) and
/// the language server (PATH). No spawning, only existence checks.
pub fn probe(io: std.Io, path_env: []const u8, broker_buf: []u8, server_buf: []u8) Availability {
    const broker = findBroker(io, path_env, broker_buf) orelse return .no_broker;
    const server = findInPath(io, path_env, server_command, server_buf) orelse return .no_server;
    return .{ .available = .{ .broker = broker, .server = server } };
}

fn findBroker(io: std.Io, path_env: []const u8, buf: []u8) ?[]const u8 {
    if (std.Io.Dir.cwd().access(io, broker_build_rel_path, .{})) |_| {
        const n = std.Io.Dir.cwd().realPathFile(io, broker_build_rel_path, buf) catch {
            if (broker_build_rel_path.len <= buf.len) {
                @memcpy(buf[0..broker_build_rel_path.len], broker_build_rel_path);
                return buf[0..broker_build_rel_path.len];
            }
            return null;
        };
        return buf[0..n];
    } else |_| {}
    return findInPath(io, path_env, broker_binary_name, buf);
}

pub fn findInPath(io: std.Io, path_env: []const u8, name: []const u8, buf: []u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, path_env, ':');
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        const full = std.fmt.bufPrint(buf, "{s}/{s}", .{ std.mem.trimEnd(u8, dir, "/"), name }) catch continue;
        std.Io.Dir.cwd().access(io, full, .{ .execute = true }) catch continue;
        return full;
    }
    return null;
}

// ---------------------------------------------------------------- URIs

/// Percent-encode `abs_root` into a `file://` root URI (RFC 3986
/// unreserved set plus `/`), mirroring `broker_transport.buildFileUri`.
pub fn buildRootUri(out: []u8, abs_root: []const u8) ?[]const u8 {
    if (abs_root.len == 0 or abs_root[0] != '/') return null;
    const root = std.mem.trimEnd(u8, abs_root, "/");
    var len: usize = 0;
    const prefix = "file://";
    if (prefix.len > out.len) return null;
    @memcpy(out[0..prefix.len], prefix);
    len = prefix.len;
    for (root) |c| {
        const unreserved = std.ascii.isAlphanumeric(c) or
            c == '-' or c == '.' or c == '_' or c == '~' or c == '/';
        if (unreserved) {
            if (len >= out.len) return null;
            out[len] = c;
            len += 1;
        } else {
            if (len + 3 > out.len) return null;
            _ = std.fmt.bufPrint(out[len..][0..3], "%{X:0>2}", .{c}) catch return null;
            len += 3;
        }
    }
    if (len > transport_mod.max_uri_bytes) return null;
    return out[0..len];
}

/// Decode a `file://` URI and strip the workspace root, yielding the
/// workspace-relative path the Problems panel uses. Falls back to the
/// decoded absolute path for out-of-workspace files; null for non-file
/// URIs or undecodable input.
pub fn uriToWorkspaceRel(uri: []const u8, root_abs: []const u8, out: []u8) ?[]const u8 {
    const prefix = "file://";
    if (!std.mem.startsWith(u8, uri, prefix)) return null;
    const encoded = uri[prefix.len..];
    var n: usize = 0;
    var i: usize = 0;
    while (i < encoded.len) : (i += 1) {
        var c = encoded[i];
        if (c == '%') {
            if (i + 2 >= encoded.len) return null;
            const hi = std.fmt.charToDigit(encoded[i + 1], 16) catch return null;
            const lo = std.fmt.charToDigit(encoded[i + 2], 16) catch return null;
            c = @intCast(hi * 16 + lo);
            i += 2;
        }
        if (n >= out.len) return null;
        out[n] = c;
        n += 1;
    }
    const abs = out[0..n];
    const root = std.mem.trimEnd(u8, root_abs, "/");
    if (root.len > 0 and abs.len > root.len + 1 and
        std.mem.startsWith(u8, abs, root) and abs[root.len] == '/')
    {
        return abs[root.len + 1 ..];
    }
    return abs;
}

// -------------------------------------------------------------- runtime

/// Heap-resident per-session state (several MiB of fixed buffers; the
/// app model allocates exactly one while a session is live and frees it
/// on teardown — nothing exists before a supported file opens).
pub const Runtime = struct {
    transport: transport_mod.Transport = undefined,
    reassembly_buf: [transport_mod.max_message_bytes]u8 = undefined,
    scratch: [transport_mod.recommended_scratch_bytes]u8 = undefined,

    // Outbound send queue: strictly serial POSTs (one chunk assembly at
    // a time per broker). Slots hold complete LSP payloads.
    slots: [max_out_queue][max_out_slot_bytes]u8 = undefined,
    slot_lens: [max_out_queue]usize = [_]usize{0} ** max_out_queue,
    head: usize = 0,
    count: usize = 0,
    plan: ?transport_mod.SendPlan = null,
    awaiting_ack: bool = false,
    /// Sends dropped because the queue was full or the payload did not
    /// fit a slot. Honest counter, surfaced via logs/tests.
    dropped_sends: u32 = 0,
    send_seq: u32 = 0,
    current_send_key: u64 = 0,
    hb_seq: u32 = 0,
    current_hb_key: u64 = 0,

    // Single open document (v1: the active editor tab).
    open_uri: [transport_mod.max_uri_bytes]u8 = undefined,
    open_uri_len: usize = 0,
    open_rel: [max_path_bytes]u8 = undefined,
    open_rel_len: usize = 0,
    /// Static slice from the comptime language registry.
    language_id: []const u8 = "",
    doc_version: i64 = 0,
    change_pending: bool = false,
    save_pending: bool = false,

    // Monotonic session clock, advanced by the heartbeat timer (time is
    // a parameter to the transport's deadline APIs).
    now_ms: u64 = 0,
    hb_in_flight: bool = false,
    hb_fail_count: u32 = 0,
    line_error_count: u32 = 0,

    root_abs: [max_path_bytes]u8 = undefined,
    root_abs_len: usize = 0,
    root_uri: [transport_mod.max_uri_bytes]u8 = undefined,
    root_uri_len: usize = 0,

    /// Staging area for one publishDiagnostics extraction.
    diags: transport_mod.DiagnosticsPage = .{},

    /// In-place (re)initialization; the struct is far too large for
    /// by-value moves, so callers heap-allocate and then reset.
    pub fn reset(self: *Runtime) void {
        self.transport = transport_mod.Transport.init(&self.reassembly_buf);
        self.slot_lens = [_]usize{0} ** max_out_queue;
        self.head = 0;
        self.count = 0;
        self.plan = null;
        self.awaiting_ack = false;
        self.dropped_sends = 0;
        self.send_seq = 0;
        self.current_send_key = 0;
        self.hb_seq = 0;
        self.current_hb_key = 0;
        self.open_uri_len = 0;
        self.open_rel_len = 0;
        self.language_id = "";
        self.doc_version = 0;
        self.change_pending = false;
        self.save_pending = false;
        self.now_ms = 0;
        self.hb_in_flight = false;
        self.hb_fail_count = 0;
        self.line_error_count = 0;
        self.root_abs_len = 0;
        self.root_uri_len = 0;
        self.diags = .{};
    }

    pub fn setRoot(self: *Runtime, abs_root: []const u8) bool {
        if (abs_root.len == 0 or abs_root.len > self.root_abs.len) return false;
        @memcpy(self.root_abs[0..abs_root.len], abs_root);
        self.root_abs_len = abs_root.len;
        const uri = buildRootUri(&self.root_uri, self.rootAbs()) orelse {
            self.root_abs_len = 0;
            return false;
        };
        self.root_uri_len = uri.len;
        return true;
    }

    pub fn rootAbs(self: *const Runtime) []const u8 {
        return self.root_abs[0..self.root_abs_len];
    }

    pub fn rootUri(self: *const Runtime) []const u8 {
        return self.root_uri[0..self.root_uri_len];
    }

    pub fn openRel(self: *const Runtime) []const u8 {
        return self.open_rel[0..self.open_rel_len];
    }

    pub fn openUri(self: *const Runtime) []const u8 {
        return self.open_uri[0..self.open_uri_len];
    }

    pub fn hasOpenDoc(self: *const Runtime) bool {
        return self.open_rel_len > 0;
    }

    /// Record `rel` as the open document and build its file URI.
    pub fn beginOpenDoc(self: *Runtime, rel: []const u8, language_id: []const u8) bool {
        if (rel.len == 0 or rel.len > self.open_rel.len) return false;
        const uri = transport_mod.buildFileUri(&self.open_uri, self.rootAbs(), rel) catch return false;
        self.open_uri_len = uri.len;
        @memcpy(self.open_rel[0..rel.len], rel);
        self.open_rel_len = rel.len;
        self.language_id = language_id;
        self.doc_version = 1;
        self.change_pending = false;
        self.save_pending = false;
        return true;
    }

    pub fn clearOpenDoc(self: *Runtime) void {
        self.open_uri_len = 0;
        self.open_rel_len = 0;
        self.language_id = "";
        self.doc_version = 0;
        self.change_pending = false;
        self.save_pending = false;
    }

    // ------------------------------------------------------ send queue

    /// Buffer for building the next outgoing payload in place, or null
    /// when the queue is full (callers count the drop).
    pub fn nextSlotBuf(self: *Runtime) ?[]u8 {
        if (self.count >= max_out_queue) return null;
        const idx = (self.head + self.count) % max_out_queue;
        return &self.slots[idx];
    }

    /// Commit `len` bytes previously written into `nextSlotBuf`.
    pub fn commit(self: *Runtime, len: usize) void {
        std.debug.assert(self.count < max_out_queue);
        std.debug.assert(len > 0 and len <= max_out_slot_bytes);
        const idx = (self.head + self.count) % max_out_queue;
        self.slot_lens[idx] = len;
        self.count += 1;
    }

    pub fn pendingSendCount(self: *const Runtime) usize {
        return self.count;
    }

    pub fn sendQueueIdle(self: *const Runtime) bool {
        return self.count == 0 and !self.awaiting_ack;
    }

    fn headPayload(self: *Runtime) ?[]const u8 {
        if (self.count == 0) return null;
        return self.slots[self.head][0..self.slot_lens[self.head]];
    }

    fn pop(self: *Runtime) void {
        std.debug.assert(self.count > 0);
        self.slot_lens[self.head] = 0;
        self.head = (self.head + 1) % max_out_queue;
        self.count -= 1;
    }

    /// The next POST to issue, or null when idle or awaiting the ack of
    /// the previous POST (serial protocol: one in flight per broker).
    /// Marks itself awaiting; call `ackPost` on the 204.
    pub fn duePost(self: *Runtime) ?transport_mod.OutboundPost {
        if (self.awaiting_ack) return null;
        while (true) {
            if (self.plan == null) {
                const payload = self.headPayload() orelse return null;
                self.plan = self.transport.planSend(payload) catch {
                    self.dropped_sends += 1;
                    self.pop();
                    continue;
                };
            }
            if (self.plan.?.next()) |post| {
                self.awaiting_ack = true;
                return post;
            }
            self.plan = null;
            self.pop();
        }
    }

    pub fn ackPost(self: *Runtime) void {
        self.awaiting_ack = false;
        if (self.plan) |*plan| {
            if (plan.done) {
                self.plan = null;
                self.pop();
            }
        }
    }

    /// Allocate the effect key for the next send POST (unique per POST
    /// so completed fetch slots can never collide).
    pub fn takeSendKey(self: *Runtime, base: u64) u64 {
        self.send_seq +%= 1;
        self.current_send_key = base | @as(u64, self.send_seq);
        return self.current_send_key;
    }

    pub fn takeHbKey(self: *Runtime, base: u64) u64 {
        self.hb_seq +%= 1;
        self.current_hb_key = base | @as(u64, self.hb_seq);
        return self.current_hb_key;
    }
};

// ================================================================ tests

const testing = std.testing;

test "activation decision requires toggle, workspace, registry match, and one attempt" {
    try testing.expect(shouldActivate(true, true, false, "src/lib/db.ts"));
    try testing.expect(shouldActivate(true, true, false, "src/app.tsx"));
    try testing.expect(shouldActivate(true, true, false, "index.mjs"));
    try testing.expect(!shouldActivate(false, true, false, "src/lib/db.ts"));
    try testing.expect(!shouldActivate(true, false, false, "src/lib/db.ts"));
    try testing.expect(!shouldActivate(true, true, true, "src/lib/db.ts"));
    try testing.expect(!shouldActivate(true, true, false, "src/main.zig"));
    try testing.expect(!shouldActivate(true, true, false, "README.md"));
    try testing.expect(!shouldActivate(true, true, false, ""));
    try testing.expectEqualStrings("typescript", languageIdForTsServer("a.ts").?);
    try testing.expectEqualStrings("javascriptreact", languageIdForTsServer("a.jsx").?);
    try testing.expect(languageIdForTsServer("a.rs") == null);
}

test "status labels are the honest UI vocabulary" {
    try testing.expectEqualStrings("off", Status.off.label());
    try testing.expectEqualStrings("unavailable", Status.unavailable_broker.label());
    try testing.expectEqualStrings("unavailable", Status.unavailable_server.label());
    try testing.expectEqualStrings("starting", Status.starting.label());
    try testing.expectEqualStrings("running", Status.running.label());
    try testing.expect(std.mem.indexOf(u8, Status.unavailable_broker.detail(), "not built") != null);
}

test "root uri and file uri mapping round-trip through percent encoding" {
    var uri_buf: [transport_mod.max_uri_bytes]u8 = undefined;
    const root = buildRootUri(&uri_buf, "/home/user/my project/").?;
    try testing.expectEqualStrings("file:///home/user/my%20project", root);
    try testing.expect(buildRootUri(&uri_buf, "relative/root") == null);

    var rel_buf: [max_path_bytes]u8 = undefined;
    const rel = uriToWorkspaceRel(
        "file:///home/user/my%20project/src/a%20b.ts",
        "/home/user/my project",
        &rel_buf,
    ).?;
    try testing.expectEqualStrings("src/a b.ts", rel);

    // Out-of-workspace files fall back to the absolute path.
    const abs = uriToWorkspaceRel("file:///tmp/x.ts", "/home/user/my project", &rel_buf).?;
    try testing.expectEqualStrings("/tmp/x.ts", abs);
    try testing.expect(uriToWorkspaceRel("untitled:one", "/root", &rel_buf) == null);
    try testing.expect(uriToWorkspaceRel("file:///bad%2", "/root", &rel_buf) == null);
}

test "runtime send queue enforces the serial ack protocol and chunking" {
    const rt = try testing.allocator.create(Runtime);
    defer testing.allocator.destroy(rt);
    rt.reset();

    // Ready the transport (listening handshake).
    var scratch: [4096]u8 = undefined;
    const listening = "{\"event\":\"listening\",\"port\":38617,\"token\":\"fee8c75f408e830831425370bb633345\"}";
    const incoming = try rt.transport.onLine(listening, &scratch);
    try testing.expect(incoming == .listening);

    // Small payload -> exactly one /message POST, gated by ack.
    {
        const buf = rt.nextSlotBuf().?;
        const payload = "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}";
        @memcpy(buf[0..payload.len], payload);
        rt.commit(payload.len);
    }
    const first = rt.duePost().?;
    try testing.expectEqual(transport_mod.PostTarget.message, first.target);
    try testing.expect(rt.duePost() == null); // serial: awaiting ack
    rt.ackPost();
    try testing.expect(rt.duePost() == null); // drained
    try testing.expectEqual(@as(usize, 0), rt.pendingSendCount());

    // Large payload -> ordered /chunk POSTs, one at a time.
    {
        const buf = rt.nextSlotBuf().?;
        const big_len = transport_mod.post_body_limit_bytes + 100;
        @memset(buf[0..big_len], 'x');
        buf[0] = '{';
        buf[big_len - 1] = '}';
        rt.commit(big_len);
    }
    const part0 = rt.duePost().?;
    try testing.expectEqual(transport_mod.PostTarget.chunk, part0.target);
    try testing.expectEqual(@as(u32, 0), part0.chunk_seq);
    try testing.expect(!part0.chunk_last);
    try testing.expect(rt.duePost() == null);
    rt.ackPost();
    const part1 = rt.duePost().?;
    try testing.expectEqual(@as(u32, 1), part1.chunk_seq);
    try testing.expect(part1.chunk_last);
    rt.ackPost();
    try testing.expect(rt.duePost() == null);
    try testing.expect(rt.sendQueueIdle());
}

test "runtime queue overflow and rotated effect keys stay bounded" {
    const rt = try testing.allocator.create(Runtime);
    defer testing.allocator.destroy(rt);
    rt.reset();

    var filled: usize = 0;
    while (rt.nextSlotBuf()) |buf| {
        buf[0] = '{';
        buf[1] = '}';
        rt.commit(2);
        filled += 1;
        if (filled > max_out_queue) break;
    }
    try testing.expectEqual(max_out_queue, filled);
    try testing.expect(rt.nextSlotBuf() == null);

    const base: u64 = 0xabcd_0000_0000_0000;
    const k1 = rt.takeSendKey(base);
    const k2 = rt.takeSendKey(base);
    try testing.expect(k1 != k2);
    try testing.expectEqual(base, k1 & 0xffff_0000_0000_0000);
}

test "runtime tracks one open document with versioning" {
    const rt = try testing.allocator.create(Runtime);
    defer testing.allocator.destroy(rt);
    rt.reset();
    try testing.expect(rt.setRoot("/work/project"));
    try testing.expectEqualStrings("file:///work/project", rt.rootUri());
    try testing.expect(rt.beginOpenDoc("src/lib/db.ts", "typescript"));
    try testing.expectEqualStrings("file:///work/project/src/lib/db.ts", rt.openUri());
    try testing.expectEqualStrings("src/lib/db.ts", rt.openRel());
    try testing.expectEqual(@as(i64, 1), rt.doc_version);
    rt.clearOpenDoc();
    try testing.expect(!rt.hasOpenDoc());
    // Traversal and absolute rel paths are rejected by the URI builder.
    try testing.expect(!rt.beginOpenDoc("../escape.ts", "typescript"));
    try testing.expect(!rt.beginOpenDoc("/abs.ts", "typescript"));
}
