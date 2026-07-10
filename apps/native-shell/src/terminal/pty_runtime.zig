//! App-side interactive terminal (PTY) session runtime: the bounded,
//! pure wiring seams between `pty_transport.zig` (the proven transport
//! state machine, 25 tests) and the app model's effects (Governor spawn
//! of `sidecar/pty_broker.zig`, `/input` fetch POSTs, heartbeat timer).
//!
//! Everything here is deterministic and I/O-free except `probe`, which
//! takes the runtime `std.Io` plus the PATH string as parameters so the
//! availability check stays honest (no process before the user flips the
//! "Interactive shell" switch AND the broker binary exists).
//!
//! v1 scope: one PTY session (the terminal panel's interactive mode),
//! Linux only (the broker's platform gate), ANSI sequences stripped —
//! not rendered — before the bounded scrollback ring.

const std = @import("std");
const builtin = @import("builtin");
const transport_mod = @import("pty_transport.zig");
const pty_session = @import("pty_session.zig");
const ansi_strip = @import("ansi_strip.zig");

pub const broker_binary_name = "velocity-pty-broker";
/// Where the (not-yet-app-built) broker lands when built via
/// `scripts/build-pty-broker.sh`, relative to the app's cwd.
pub const broker_build_rel_path = "zig-out/bin/velocity-pty-broker";

pub const heartbeat_interval_ms: u64 = 10_000;
pub const hb_window_ms_arg = "--hb-window-ms=30000";
pub const max_broker_line_bytes: usize = transport_mod.max_line_bytes;
/// Session path bound (matches lsp_session.max_path_bytes).
pub const max_path_bytes: usize = 512;
/// The panel renders at most this many trailing ring lines (the full
/// 2000-line ring stays queryable; the view budget mirrors the pipe
/// runner's 200-line cap).
pub const max_view_lines: usize = 200;

/// The broker only exists for POSIX PTYs and is proven on Linux
/// (sidecar README platform gates); everywhere else the mode reports an
/// honest "unavailable on this platform" without probing.
pub const platform_supported: bool = builtin.os.tag == .linux;

// -------------------------------------------------------------- status

/// Honest, user-visible session state ("PTY: <label>" in the terminal
/// panel header).
pub const Status = enum {
    off,
    unavailable_broker,
    unavailable_platform,
    starting,
    running,
    exited,
    stopped,
    failed,

    pub fn label(self: Status) []const u8 {
        return switch (self) {
            .off => "off",
            .unavailable_broker, .unavailable_platform => "unavailable",
            .starting => "starting",
            .running => "running",
            .exited => "exited",
            .stopped => "stopped",
            .failed => "failed",
        };
    }

    pub fn detail(self: Status) []const u8 {
        return switch (self) {
            .unavailable_broker => "PTY broker binary not built; run scripts/build-pty-broker.sh",
            .unavailable_platform => "Interactive shell is not available on this platform yet (Linux only)",
            else => self.label(),
        };
    }
};

// --------------------------------------------------------- activation

/// Pure activation decision: switch on AND a disk workspace open AND the
/// terminal panel visible AND no earlier attempt this episode (honest
/// unavailable states persist instead of re-probing every message).
pub fn shouldActivate(
    enabled: bool,
    workspace_open: bool,
    panel_shown: bool,
    already_attempted: bool,
) bool {
    if (!enabled or !workspace_open or !panel_shown or already_attempted) return false;
    return true;
}

// -------------------------------------------------------- availability

pub const Availability = union(enum) {
    available: []const u8,
    no_broker,
};

/// Discover the broker binary (local build output first, then PATH).
/// No spawning, only existence checks — same discovery order as the LSP
/// broker.
pub fn probe(io: std.Io, path_env: []const u8, broker_buf: []u8) Availability {
    if (std.Io.Dir.cwd().access(io, broker_build_rel_path, .{})) |_| {
        // The runtime Io needs a PATH_MAX-wide realpath buffer; fall back
        // to the cwd-relative path when the resolved one exceeds session
        // limits (mirrors lsp_session.findBroker).
        var real_buf: [std.fs.max_path_bytes]u8 = undefined;
        if (std.Io.Dir.cwd().realPathFile(io, broker_build_rel_path, &real_buf)) |n| {
            if (n <= broker_buf.len) {
                @memcpy(broker_buf[0..n], real_buf[0..n]);
                return .{ .available = broker_buf[0..n] };
            }
        } else |_| {}
        if (broker_build_rel_path.len <= broker_buf.len) {
            @memcpy(broker_buf[0..broker_build_rel_path.len], broker_build_rel_path);
            return .{ .available = broker_buf[0..broker_build_rel_path.len] };
        }
        return .no_broker;
    } else |_| {}
    if (findInPath(io, path_env, broker_binary_name, broker_buf)) |path| {
        return .{ .available = path };
    }
    return .no_broker;
}

/// PATH walk (duplicated from lsp_session.findInPath so this module has
/// no cross-directory imports and stays standalone-testable).
fn findInPath(io: std.Io, path_env: []const u8, name: []const u8, buf: []u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, path_env, ':');
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        const full = std.fmt.bufPrint(buf, "{s}/{s}", .{ std.mem.trimEnd(u8, dir, "/"), name }) catch continue;
        std.Io.Dir.cwd().access(io, full, .{ .execute = true }) catch continue;
        return full;
    }
    return null;
}

// -------------------------------------------------------------- runtime

/// Heap-resident per-session state (~1.1 MiB of fixed buffers: the
/// 2000-line scrollback ring plus transport decode/strip buffers). The
/// app model allocates exactly one while the interactive mode is active
/// and frees it on teardown — nothing exists before the user activates.
pub const Runtime = struct {
    transport: transport_mod.Transport = undefined,
    /// Base64 `data` payloads decode into this (caller-buffer API).
    decode_buf: [transport_mod.max_output_raw_bytes]u8 = undefined,
    /// ANSI stripping writes the filtered bytes here before the ring.
    strip_buf: [transport_mod.max_output_raw_bytes]u8 = undefined,
    /// Envelope-event JSON parse scratch (listening/exit/error lines are
    /// small; `data` lines take the transport's no-parse fast path).
    scratch: [4096]u8 = undefined,
    stripper: ansi_strip.Stripper = .{},
    /// Bounded scrollback ring + input queue + exit bookkeeping.
    session: pty_session.PtySession = .{},

    /// View projection: the trailing `max_view_lines` ring lines as the
    /// `[]const []const u8` slice the terminal panel binds. Slices point
    /// into the ring's storage; refreshed after every mutation.
    view_storage: [max_view_lines][]const u8 = [_][]const u8{""} ** max_view_lines,
    view_count: usize = 0,

    /// One `/input` POST in flight at a time (PTY bytes must not
    /// reorder); keystrokes submitted meanwhile coalesce in the queue.
    awaiting_ack: bool = false,
    in_flight_raw_len: usize = 0,
    body_buf: [transport_mod.input_body_bytes]u8 = undefined,
    /// Input dropped because the bounded queue was full. Honest counter.
    dropped_input: u32 = 0,

    send_seq: u32 = 0,
    current_send_key: u64 = 0,
    hb_seq: u32 = 0,
    current_hb_key: u64 = 0,
    hb_in_flight: bool = false,
    hb_fail_count: u32 = 0,
    line_error_count: u32 = 0,

    /// In-place (re)initialization; the struct is too large for by-value
    /// moves, so callers heap-allocate and then reset.
    pub fn reset(self: *Runtime) void {
        self.transport = transport_mod.Transport.init(&self.decode_buf);
        self.stripper = .{};
        self.session = .{};
        self.session.state = .starting;
        self.view_storage = [_][]const u8{""} ** max_view_lines;
        self.view_count = 0;
        self.awaiting_ack = false;
        self.in_flight_raw_len = 0;
        self.dropped_input = 0;
        self.send_seq = 0;
        self.current_send_key = 0;
        self.hb_seq = 0;
        self.current_hb_key = 0;
        self.hb_in_flight = false;
        self.hb_fail_count = 0;
        self.line_error_count = 0;
    }

    // ------------------------------------------------------------ output

    /// One decoded `data` payload: strip ANSI sequences, then feed the
    /// bounded ring (drop-with-truncation inside `PtySession`).
    pub fn acceptOutput(self: *Runtime, decoded: []const u8) void {
        const stripped = self.stripper.strip(decoded, &self.strip_buf);
        self.session.accept(.{ .output = stripped });
        self.refreshView();
    }

    /// Record the shell's own exit: flush the partial line, remember the
    /// code, and surface it in the scrollback.
    pub fn noteExit(self: *Runtime, code: i64) void {
        self.session.accept(.{ .exited = @intCast(std.math.clamp(code, std.math.minInt(i32), std.math.maxInt(i32))) });
        var buf: [48]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "[shell exited {d}]", .{code}) catch "[shell exited]";
        self.session.lines.push(msg);
        self.refreshView();
    }

    /// Note a transport-level end (broker gone) in the scrollback.
    pub fn noteStopped(self: *Runtime, text: []const u8) void {
        self.session.accept(.{ .transport_failed = text });
        self.session.lines.push(text);
        self.refreshView();
    }

    pub fn clearScrollback(self: *Runtime) void {
        self.session.lines.clear();
        self.session.partial_len = 0;
        self.refreshView();
    }

    /// The trailing ring lines the panel renders.
    pub fn viewSlice(self: *const Runtime) []const []const u8 {
        return self.view_storage[0..self.view_count];
    }

    fn refreshView(self: *Runtime) void {
        const total = self.session.lines.count;
        const take = @min(total, max_view_lines);
        const first = total - take;
        var i: usize = 0;
        while (i < take) : (i += 1) {
            self.view_storage[i] = self.session.lines.line(first + i) orelse "";
        }
        self.view_count = take;
    }

    // ------------------------------------------------------------- input

    /// Queue one submitted command line (newline appended) for the PTY.
    /// Coalesces naturally: everything queued while a POST is in flight
    /// ships as one body on the next pump.
    pub fn queueLine(self: *Runtime, line: []const u8) error{InputBufferFull}!void {
        const saved_len = self.session.input_len;
        self.session.queueCommand(.{ .input = line }) catch return error.InputBufferFull;
        self.session.queueCommand(.{ .input = "\n" }) catch {
            // Roll the partial write back so a truncated command (without
            // its newline) never reaches the shell.
            self.session.input_len = saved_len;
            return error.InputBufferFull;
        };
    }

    /// Queue raw control bytes (e.g. ETX/Ctrl-C for interrupt).
    pub fn queueRaw(self: *Runtime, bytes: []const u8) error{InputBufferFull}!void {
        self.session.queueCommand(.{ .input = bytes }) catch return error.InputBufferFull;
    }

    /// Build the next `/input` POST body, or null when idle, awaiting an
    /// ack, or the shell cannot receive input. Marks itself awaiting;
    /// call `ackInput` on the 204 (or `failInput` on failure).
    pub fn dueInput(self: *Runtime) ?[]const u8 {
        if (self.awaiting_ack) return null;
        if (!self.transport.canSend()) return null;
        const queued = self.session.queuedInput();
        if (queued.len == 0) return null;
        const take = @min(queued.len, transport_mod.input_chunk_raw_bytes);
        const body = transport_mod.buildInputBody(&self.body_buf, queued[0..take]) catch {
            // Cannot happen with take in 1..=chunk bytes and a sized
            // buffer; drop the bytes rather than wedge the queue.
            self.session.consumeInput(take);
            self.dropped_input +%= 1;
            return null;
        };
        self.in_flight_raw_len = take;
        self.awaiting_ack = true;
        return body;
    }

    pub fn ackInput(self: *Runtime) void {
        self.session.consumeInput(self.in_flight_raw_len);
        self.in_flight_raw_len = 0;
        self.awaiting_ack = false;
    }

    /// The in-flight POST failed: drop those bytes (the broker may be
    /// dying; retrying risks reordering) and unblock the queue.
    pub fn failInput(self: *Runtime) void {
        self.session.consumeInput(self.in_flight_raw_len);
        self.in_flight_raw_len = 0;
        self.awaiting_ack = false;
        self.dropped_input +%= 1;
    }

    // -------------------------------------------------------------- keys

    /// Allocate the effect key for the next input POST (unique per POST
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

const listening_line = "{\"event\":\"listening\",\"port\":34609,\"token\":\"5341c3c1bee76b4e0666a641c60d8dcb\"}";

fn readyRuntime() !*Runtime {
    const rt = try testing.allocator.create(Runtime);
    rt.reset();
    var scratch: [4096]u8 = undefined;
    const incoming = try rt.transport.onLine(listening_line, &scratch);
    try testing.expect(incoming == .listening);
    return rt;
}

test "activation decision requires switch, workspace, panel, and one attempt" {
    try testing.expect(shouldActivate(true, true, true, false));
    try testing.expect(!shouldActivate(false, true, true, false));
    try testing.expect(!shouldActivate(true, false, true, false));
    try testing.expect(!shouldActivate(true, true, false, false));
    try testing.expect(!shouldActivate(true, true, true, true));
}

test "status labels are the honest UI vocabulary" {
    try testing.expectEqualStrings("off", Status.off.label());
    try testing.expectEqualStrings("unavailable", Status.unavailable_broker.label());
    try testing.expectEqualStrings("unavailable", Status.unavailable_platform.label());
    try testing.expectEqualStrings("running", Status.running.label());
    try testing.expectEqualStrings("exited", Status.exited.label());
    try testing.expect(std.mem.indexOf(u8, Status.unavailable_broker.detail(), "not built") != null);
    try testing.expect(std.mem.indexOf(u8, Status.unavailable_platform.detail(), "platform") != null);
}

test "output events strip ANSI and land in the bounded ring, tail projected" {
    const rt = try readyRuntime();
    defer testing.allocator.destroy(rt);
    rt.acceptOutput("\x1b[32m$ \x1b[0mecho hi\r\nhi\r\n");
    try testing.expectEqual(@as(usize, 2), rt.viewSlice().len);
    try testing.expectEqualStrings("$ echo hi", rt.viewSlice()[0]);
    try testing.expectEqualStrings("hi", rt.viewSlice()[1]);

    // A split escape sequence across two data events still strips.
    rt.acceptOutput("a\x1b[3");
    rt.acceptOutput("1mb\n");
    try testing.expectEqualStrings("ab", rt.viewSlice()[2]);

    // Flood the ring past the view budget: projection stays bounded to
    // the trailing lines.
    var i: usize = 0;
    var buf: [32]u8 = undefined;
    while (i < max_view_lines + 50) : (i += 1) {
        const text = std.fmt.bufPrint(&buf, "line-{d}\n", .{i}) catch unreachable;
        rt.acceptOutput(text);
    }
    try testing.expectEqual(max_view_lines, rt.viewSlice().len);
    try testing.expectEqualStrings("line-249", rt.viewSlice()[max_view_lines - 1]);
}

test "input queue coalesces while a POST is in flight and stays serial" {
    const rt = try readyRuntime();
    defer testing.allocator.destroy(rt);

    try rt.queueLine("export V=42");
    const first = rt.dueInput().?;
    try testing.expectEqualStrings("{\"b64\":\"ZXhwb3J0IFY9NDIK\"}", first);
    // Serial: nothing else while awaiting the ack.
    try rt.queueLine("echo $V");
    try rt.queueLine("pwd");
    try testing.expect(rt.dueInput() == null);
    rt.ackInput();
    // Both queued lines coalesce into ONE follow-up POST body.
    const second = rt.dueInput().?;
    var decoded: [64]u8 = undefined;
    const b64 = second["{\"b64\":\"".len .. second.len - 2];
    const n = try std.base64.standard.Decoder.calcSizeForSlice(b64);
    try std.base64.standard.Decoder.decode(decoded[0..n], b64);
    try testing.expectEqualStrings("echo $V\npwd\n", decoded[0..n]);
    rt.ackInput();
    try testing.expect(rt.dueInput() == null);
}

test "input is refused before the handshake and after exit" {
    const rt = try testing.allocator.create(Runtime);
    defer testing.allocator.destroy(rt);
    rt.reset();
    try rt.queueLine("early");
    try testing.expect(rt.dueInput() == null); // starting: no POSTs yet

    var scratch: [4096]u8 = undefined;
    _ = try rt.transport.onLine(listening_line, &scratch);
    try testing.expect(rt.dueInput() != null);
    rt.ackInput();

    _ = try rt.transport.onLine("{\"event\":\"pty_exit\",\"reason\":\"exited\",\"code\":0}", &scratch);
    try rt.queueLine("late");
    try testing.expect(rt.dueInput() == null); // exited: no POSTs
}

test "failInput drops the in-flight bytes and unblocks the queue" {
    const rt = try readyRuntime();
    defer testing.allocator.destroy(rt);
    try rt.queueLine("doomed");
    try testing.expect(rt.dueInput() != null);
    try rt.queueLine("next");
    rt.failInput();
    try testing.expectEqual(@as(u32, 1), rt.dropped_input);
    const body = rt.dueInput().?;
    try testing.expect(std.mem.indexOf(u8, body, "bmV4dAo=") != null); // "next\n"
}

test "queueLine never ships a command without its newline" {
    const rt = try readyRuntime();
    defer testing.allocator.destroy(rt);
    // Fill the queue to one byte short of capacity.
    var filler: [pty_session.max_input_bytes - 1]u8 = undefined;
    @memset(&filler, 'x');
    try rt.queueRaw(&filler);
    // "z" fits but its newline does not: the whole line must be rolled back.
    try testing.expectError(error.InputBufferFull, rt.queueLine("z"));
    try testing.expectEqual(filler.len, rt.session.queuedInput().len);
}

test "exit note surfaces the shell exit code in the scrollback" {
    const rt = try readyRuntime();
    defer testing.allocator.destroy(rt);
    rt.acceptOutput("partial");
    rt.noteExit(3);
    const lines = rt.viewSlice();
    try testing.expectEqualStrings("partial", lines[lines.len - 2]);
    try testing.expectEqualStrings("[shell exited 3]", lines[lines.len - 1]);
    try testing.expectEqual(@as(i32, 3), rt.session.exit_code.?);
    try testing.expectEqual(pty_session.State.exited, rt.session.state);
}

test "clearScrollback empties the projection" {
    const rt = try readyRuntime();
    defer testing.allocator.destroy(rt);
    rt.acceptOutput("one\ntwo\n");
    try testing.expectEqual(@as(usize, 2), rt.viewSlice().len);
    rt.clearScrollback();
    try testing.expectEqual(@as(usize, 0), rt.viewSlice().len);
}

test "rotated effect keys stay in their namespace and never repeat consecutively" {
    const rt = try testing.allocator.create(Runtime);
    defer testing.allocator.destroy(rt);
    rt.reset();
    const base: u64 = 0xabcd_0000_0000_0000;
    const k1 = rt.takeSendKey(base);
    const k2 = rt.takeSendKey(base);
    try testing.expect(k1 != k2);
    try testing.expectEqual(base, k1 & 0xffff_0000_0000_0000);
    try testing.expect(rt.takeHbKey(base) != rt.current_send_key);
}
