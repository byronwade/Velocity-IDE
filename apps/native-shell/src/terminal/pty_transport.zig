//! Pure, bounded client-side state machine for the PTY sidecar broker
//! (`apps/native-shell/sidecar/pty_broker.zig`).
//!
//! This module performs NO I/O: no SDK calls, no process spawning, no
//! sockets, no clocks. The app model owns the real effects — Governor
//! `spawn` of the broker, Effects `fetch` POSTs, Effects timers for
//! heartbeats — and drives this module with the bytes those effects
//! produce:
//!
//!   * broker stdout NDJSON lines (spawn `.lines` events) go into
//!     `Transport.onLine`, which yields typed events and base64-decodes
//!     `data` payloads into a caller-provided buffer, ready to feed the
//!     bounded terminal ring (`pty_session.zig`'s `LineRing` /
//!     `PtySession.accept(.output)`);
//!   * keystrokes/paste go through `buildInputBody` (single POST) or
//!     `InputPlan` (bounded 32 KiB-raw chunks for large pastes), each
//!     yielding one `POST /input` body;
//!   * `buildResizeBody` yields the `POST /resize` body for TIOCSWINSZ;
//!   * the transport tracks the session lifecycle
//!     (starting -> running -> exited) and refuses out-of-phase moves.
//!
//! Bounded everything: fixed caps on lines, decoded output per event,
//! input chunk size, and geometry. Malformed input is an error value,
//! never a crash (tests prove it). Style and event vocabulary mirror
//! `../lsp/broker_transport.zig`.

const std = @import("std");

// ---------------------------------------------------------------- limits

/// SDK spawn `.lines` ceiling; the broker never emits longer lines.
pub const max_line_bytes: usize = 256 * 1024;
/// Broker raw bytes per `data` event (pre-base64); the decode buffer
/// passed to `Transport.init` must hold at least this much.
pub const max_output_raw_bytes: usize = 48 * 1024;
/// POST body ceiling the app must stay under (SDK fetch cap is 64 KiB;
/// 48 KiB leaves envelope headroom, matching the LSP transport).
pub const post_body_limit_bytes: usize = 48 * 1024;
/// Raw input bytes per /input POST: base64(32 KiB) + envelope fits the
/// POST body limit with room to spare.
pub const input_chunk_raw_bytes: usize = 32 * 1024;
pub const token_len: usize = 32; // hex chars
/// Terminal geometry sanity bounds (mirrors the broker and
/// pty_session.zig).
pub const max_columns: u16 = 1000;
pub const max_rows: u16 = 1000;
pub const max_error_detail_bytes: usize = 256;

// -------------------------------------------------------- broker events

pub const PtyExit = struct {
    reason: enum { exited, signal, unknown },
    code: i64,
};

pub const BrokerExitReason = enum { stdin_closed, heartbeat_lapsed, shutdown_requested, unknown };

pub const BrokerError = struct {
    /// Raw (still JSON-escaped) slices borrowing the input line; for
    /// logging/telemetry only.
    code: []const u8,
    detail: []const u8,
};

pub const PtyEvent = union(enum) {
    listening: struct { port: u16, token: [token_len]u8 },
    /// Base64 payload of one `data` event, borrowing the input line
    /// (NOT yet decoded — `Transport.onLine` decodes it).
    data_b64: []const u8,
    pty_exit: PtyExit,
    broker_exit: BrokerExitReason,
    broker_error: BrokerError,
};

pub const ParseLineError = error{
    LineTooLong,
    EmptyLine,
    MalformedEvent,
    UnknownEvent,
};

const data_prefix = "{\"event\":\"data\",\"b64\":\"";
const data_suffix = "\"}";

/// Parse one broker NDJSON line into a typed event.
///
/// `scratch` backs the bounded JSON parse (a FixedBufferAllocator) for
/// the non-`data` envelope events; `data` lines take a slicing fast
/// path (the broker emits a fixed envelope with the base64 payload as
/// the only string, so no JSON parse of up to 64 KiB is needed).
/// Returned slices may borrow `line` or `scratch` and are valid until
/// either is reused.
pub fn parsePtyLine(line_raw: []const u8, scratch: []u8) ParseLineError!PtyEvent {
    const line = std.mem.trimEnd(u8, line_raw, "\r");
    if (line.len == 0) return error.EmptyLine;
    if (line.len > max_line_bytes) return error.LineTooLong;

    if (std.mem.startsWith(u8, line, data_prefix)) {
        if (!std.mem.endsWith(u8, line, data_suffix)) return error.MalformedEvent;
        const payload = line[data_prefix.len .. line.len - data_suffix.len];
        // Base64 never contains quotes/backslashes; embedded ones mean
        // a corrupt or forged envelope. The decoder rejects any other
        // non-alphabet byte later.
        if (std.mem.indexOfAny(u8, payload, "\"\\") != null) return error.MalformedEvent;
        return .{ .data_b64 = payload };
    }

    var fba = std.heap.FixedBufferAllocator.init(scratch);
    const parsed = std.json.parseFromSlice(std.json.Value, fba.allocator(), line, .{}) catch
        return error.MalformedEvent;
    const root = switch (parsed.value) {
        .object => |object| object,
        else => return error.MalformedEvent,
    };
    const event = stringField(root, "event") orelse return error.MalformedEvent;

    if (std.mem.eql(u8, event, "listening")) {
        const port_value = integerField(root, "port") orelse return error.MalformedEvent;
        if (port_value < 1 or port_value > std.math.maxInt(u16)) return error.MalformedEvent;
        const token = stringField(root, "token") orelse return error.MalformedEvent;
        if (token.len != token_len) return error.MalformedEvent;
        for (token) |c| {
            if (!std.ascii.isHex(c)) return error.MalformedEvent;
        }
        var out: PtyEvent = .{ .listening = .{ .port = @intCast(port_value), .token = undefined } };
        @memcpy(&out.listening.token, token);
        return out;
    }
    if (std.mem.eql(u8, event, "data")) {
        // A data event that missed the fast path has a non-canonical
        // envelope; accept it anyway if the payload is a string.
        const payload = stringField(root, "b64") orelse return error.MalformedEvent;
        return .{ .data_b64 = payload };
    }
    if (std.mem.eql(u8, event, "pty_exit")) {
        const reason = stringField(root, "reason") orelse return error.MalformedEvent;
        const code = integerField(root, "code") orelse return error.MalformedEvent;
        return .{ .pty_exit = .{
            .reason = if (std.mem.eql(u8, reason, "exited"))
                .exited
            else if (std.mem.eql(u8, reason, "signal"))
                .signal
            else
                .unknown,
            .code = code,
        } };
    }
    if (std.mem.eql(u8, event, "broker_exit")) {
        const reason = stringField(root, "reason") orelse return error.MalformedEvent;
        const mapped: BrokerExitReason = if (std.mem.eql(u8, reason, "stdin_closed"))
            .stdin_closed
        else if (std.mem.eql(u8, reason, "heartbeat_lapsed"))
            .heartbeat_lapsed
        else if (std.mem.eql(u8, reason, "shutdown_requested"))
            .shutdown_requested
        else
            .unknown;
        return .{ .broker_exit = mapped };
    }
    if (std.mem.eql(u8, event, "error")) {
        return .{ .broker_error = .{
            .code = truncate(stringField(root, "code") orelse "", max_error_detail_bytes),
            .detail = truncate(stringField(root, "detail") orelse "", max_error_detail_bytes),
        } };
    }
    return error.UnknownEvent;
}

fn stringField(object: std.json.ObjectMap, name: []const u8) ?[]const u8 {
    const value = object.get(name) orelse return null;
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

fn integerField(object: std.json.ObjectMap, name: []const u8) ?i64 {
    const value = object.get(name) orelse return null;
    return switch (value) {
        .integer => |i| i,
        else => null,
    };
}

fn truncate(s: []const u8, limit: usize) []const u8 {
    return s[0..@min(s.len, limit)];
}

// ------------------------------------------------------------- builders

pub const BuildError = error{OutputTooSmall};

pub const InputBodyError = error{ EmptyInput, InputTooLarge, OutputTooSmall };

/// Suggested output size for one /input POST body:
/// base64(input_chunk_raw_bytes) + envelope, < post_body_limit_bytes.
pub const input_body_bytes: usize =
    std.base64.standard.Encoder.calcSize(input_chunk_raw_bytes) + 16;

comptime {
    std.debug.assert(input_body_bytes <= post_body_limit_bytes);
}

/// Build one `POST /input` body: `{"b64":"..."}`. `raw` must be
/// 1..=input_chunk_raw_bytes bytes; larger inputs go through
/// `InputPlan`.
pub fn buildInputBody(out: []u8, raw: []const u8) InputBodyError![]const u8 {
    if (raw.len == 0) return error.EmptyInput;
    if (raw.len > input_chunk_raw_bytes) return error.InputTooLarge;
    const b64_len = std.base64.standard.Encoder.calcSize(raw.len);
    const total = "{\"b64\":\"".len + b64_len + "\"}".len;
    if (out.len < total) return error.OutputTooSmall;
    var n: usize = 0;
    @memcpy(out[n..][0.."{\"b64\":\"".len], "{\"b64\":\"");
    n += "{\"b64\":\"".len;
    _ = std.base64.standard.Encoder.encode(out[n..][0..b64_len], raw);
    n += b64_len;
    @memcpy(out[n..][0..2], "\"}");
    n += 2;
    return out[0..n];
}

/// Iterator over the `/input` POST bodies for one (possibly large)
/// input burst — e.g. a paste. Chunks of <= input_chunk_raw_bytes raw
/// bytes, in order; the app sends them serially (await each response —
/// PTY input bytes must not be reordered).
pub const InputPlan = struct {
    raw: []const u8,
    offset: usize = 0,

    pub const Error = error{EmptyInput};

    pub fn init(raw: []const u8) Error!InputPlan {
        if (raw.len == 0) return error.EmptyInput;
        return .{ .raw = raw };
    }

    pub fn postCount(self: *const InputPlan) usize {
        return (self.raw.len + input_chunk_raw_bytes - 1) / input_chunk_raw_bytes;
    }

    /// Build the next body into `out` (>= input_body_bytes). Null when
    /// the plan is exhausted.
    pub fn next(self: *InputPlan, out: []u8) InputBodyError!?[]const u8 {
        if (self.offset >= self.raw.len) return null;
        const take = @min(input_chunk_raw_bytes, self.raw.len - self.offset);
        const chunk = self.raw[self.offset .. self.offset + take];
        self.offset += take;
        return try buildInputBody(out, chunk);
    }
};

pub const ResizeBodyError = error{ InvalidSize, OutputTooSmall };

/// Build the `POST /resize` body: `{"cols":N,"rows":M}`. Bounds match
/// the broker: 1..=1000 in both dimensions.
pub fn buildResizeBody(out: []u8, cols: u16, rows: u16) ResizeBodyError![]const u8 {
    if (cols == 0 or cols > max_columns or rows == 0 or rows > max_rows) {
        return error.InvalidSize;
    }
    return std.fmt.bufPrint(out, "{{\"cols\":{d},\"rows\":{d}}}", .{ cols, rows }) catch
        error.OutputTooSmall;
}

// ------------------------------------------------------------ transport

/// Session lifecycle: mirrors `pty_session.zig`'s intent — starting
/// until the broker's listening line, running while the shell lives,
/// exited after `pty_exit`/`broker_exit`.
pub const TransportPhase = enum {
    /// Broker spawned; waiting for its first (listening) line.
    starting,
    /// Port + token known; input/resize POSTs are legal, output flows.
    running,
    /// Shell or broker is gone; expect (or already saw) spawn on_exit.
    exited,
};

/// The top-level state machine the app model drives. Owns the broker
/// handshake (listening line), base64 output decoding, and lifecycle
/// bookkeeping. Still pure: the app maps `Incoming` onto spawn lines
/// and fetch POSTs, and pushes `.output` bytes into its terminal ring.
pub const Transport = struct {
    phase: TransportPhase = .starting,
    port: u16 = 0,
    token: [token_len]u8 = [_]u8{'0'} ** token_len,
    /// Exit metadata once phase == .exited via pty_exit.
    exit: ?PtyExit = null,
    /// Caller-provided buffer `data` payloads are decoded into; must
    /// hold max_output_raw_bytes.
    decode_buf: []u8,

    pub const Incoming = union(enum) {
        /// Handshake done: `port`/`token` are set; the shell is live.
        listening,
        /// Decoded PTY output (borrows the decode buffer until the
        /// next `onLine`). Feed to the terminal ring.
        output: []const u8,
        pty_exit: PtyExit,
        broker_exit: BrokerExitReason,
        broker_error: BrokerError,
    };

    pub const OnLineError = ParseLineError || error{
        ProtocolViolation,
        InvalidBase64,
        OutputTooLarge,
    };

    pub fn init(decode_buf: []u8) Transport {
        return .{ .decode_buf = decode_buf };
    }

    /// Feed one broker stdout line (spawn `on_line`). Errors are
    /// per-line: the caller logs/counts them and keeps feeding — a bad
    /// line never poisons transport state.
    pub fn onLine(self: *Transport, line: []const u8, scratch: []u8) OnLineError!Incoming {
        const event = try parsePtyLine(line, scratch);
        switch (event) {
            .listening => |listening| {
                if (self.phase != .starting) return error.ProtocolViolation;
                self.port = listening.port;
                self.token = listening.token;
                self.phase = .running;
                return .listening;
            },
            .data_b64 => |b64| {
                if (self.phase != .running) return error.ProtocolViolation;
                const decoder = std.base64.standard.Decoder;
                const raw_len = decoder.calcSizeForSlice(b64) catch return error.InvalidBase64;
                if (raw_len > max_output_raw_bytes or raw_len > self.decode_buf.len) {
                    return error.OutputTooLarge;
                }
                decoder.decode(self.decode_buf[0..raw_len], b64) catch return error.InvalidBase64;
                return .{ .output = self.decode_buf[0..raw_len] };
            },
            .pty_exit => |exit| {
                self.phase = .exited;
                self.exit = exit;
                return .{ .pty_exit = exit };
            },
            .broker_exit => |reason| {
                self.phase = .exited;
                return .{ .broker_exit = reason };
            },
            .broker_error => |broker_error| return .{ .broker_error = broker_error },
        }
    }

    /// Input/resize POSTs are only legal while the shell runs.
    pub fn canSend(self: *const Transport) bool {
        return self.phase == .running;
    }

    /// Value for the `X-Broker-Token` header on every POST.
    pub fn authToken(self: *const Transport) []const u8 {
        return &self.token;
    }
};

// ================================================================ tests

const testing = std.testing;

var test_scratch: [64 * 1024]u8 = undefined;
var test_decode: [max_output_raw_bytes]u8 = undefined;

// ------------------------------------------------ broker event parsing

test "parse listening event yields port and token" {
    const line = "{\"event\":\"listening\",\"port\":34609,\"token\":\"5341c3c1bee76b4e0666a641c60d8dcb\"}";
    const event = try parsePtyLine(line, &test_scratch);
    try testing.expectEqual(@as(u16, 34609), event.listening.port);
    try testing.expectEqualStrings("5341c3c1bee76b4e0666a641c60d8dcb", &event.listening.token);
}

test "parse listening rejects bad ports and tokens" {
    try testing.expectError(error.MalformedEvent, parsePtyLine("{\"event\":\"listening\",\"port\":0,\"token\":\"5341c3c1bee76b4e0666a641c60d8dcb\"}", &test_scratch));
    try testing.expectError(error.MalformedEvent, parsePtyLine("{\"event\":\"listening\",\"port\":70000,\"token\":\"5341c3c1bee76b4e0666a641c60d8dcb\"}", &test_scratch));
    try testing.expectError(error.MalformedEvent, parsePtyLine("{\"event\":\"listening\",\"port\":1,\"token\":\"short\"}", &test_scratch));
    try testing.expectError(error.MalformedEvent, parsePtyLine("{\"event\":\"listening\",\"port\":1,\"token\":\"zz41c3c1bee76b4e0666a641c60d8dcb\"}", &test_scratch));
    try testing.expectError(error.MalformedEvent, parsePtyLine("{\"event\":\"listening\",\"port\":1}", &test_scratch));
}

test "parse data event via the fast path" {
    const event = try parsePtyLine("{\"event\":\"data\",\"b64\":\"aGkNCiQg\"}", &test_scratch);
    try testing.expectEqualStrings("aGkNCiQg", event.data_b64);
}

test "parse data event with empty payload" {
    const event = try parsePtyLine("{\"event\":\"data\",\"b64\":\"\"}", &test_scratch);
    try testing.expectEqual(@as(usize, 0), event.data_b64.len);
}

test "parse data event rejects corrupt envelopes" {
    // Truncated (no closing quote+brace).
    try testing.expectError(error.MalformedEvent, parsePtyLine("{\"event\":\"data\",\"b64\":\"aGkN", &test_scratch));
    // Quote smuggled into the payload region.
    try testing.expectError(error.MalformedEvent, parsePtyLine("{\"event\":\"data\",\"b64\":\"aG\\\"kN\"}", &test_scratch));
    // b64 not a string in the slow-path envelope.
    try testing.expectError(error.MalformedEvent, parsePtyLine("{\"b64\":7,\"event\":\"data\"}", &test_scratch));
}

test "parse data event with reordered keys falls back to the JSON path" {
    const event = try parsePtyLine("{\"b64\":\"aGkNCiQg\",\"event\":\"data\"}", &test_scratch);
    try testing.expectEqualStrings("aGkNCiQg", event.data_b64);
}

test "parse pty_exit reasons and codes" {
    const exited = try parsePtyLine("{\"event\":\"pty_exit\",\"reason\":\"exited\",\"code\":0}", &test_scratch);
    try testing.expectEqual(@as(i64, 0), exited.pty_exit.code);
    try testing.expect(exited.pty_exit.reason == .exited);
    const signaled = try parsePtyLine("{\"event\":\"pty_exit\",\"reason\":\"signal\",\"code\":9}", &test_scratch);
    try testing.expect(signaled.pty_exit.reason == .signal);
    const unknown = try parsePtyLine("{\"event\":\"pty_exit\",\"reason\":\"gremlins\",\"code\":-1}", &test_scratch);
    try testing.expect(unknown.pty_exit.reason == .unknown);
    try testing.expectError(error.MalformedEvent, parsePtyLine("{\"event\":\"pty_exit\",\"reason\":\"exited\"}", &test_scratch));
}

test "parse broker_exit reasons" {
    const cases = [_]struct { line: []const u8, reason: BrokerExitReason }{
        .{ .line = "{\"event\":\"broker_exit\",\"reason\":\"stdin_closed\"}", .reason = .stdin_closed },
        .{ .line = "{\"event\":\"broker_exit\",\"reason\":\"heartbeat_lapsed\"}", .reason = .heartbeat_lapsed },
        .{ .line = "{\"event\":\"broker_exit\",\"reason\":\"shutdown_requested\"}", .reason = .shutdown_requested },
        .{ .line = "{\"event\":\"broker_exit\",\"reason\":\"???\"}", .reason = .unknown },
    };
    for (cases) |case| {
        const event = try parsePtyLine(case.line, &test_scratch);
        try testing.expectEqual(case.reason, event.broker_exit);
    }
}

test "parse error event truncates code and detail" {
    const event = try parsePtyLine("{\"event\":\"error\",\"code\":\"pty_write_failed\",\"detail\":\"write to PTY master failed\"}", &test_scratch);
    try testing.expectEqualStrings("pty_write_failed", event.broker_error.code);
    try testing.expectEqualStrings("write to PTY master failed", event.broker_error.detail);
}

test "parse rejects empty, oversized, non-JSON, and unknown-event lines" {
    try testing.expectError(error.EmptyLine, parsePtyLine("", &test_scratch));
    try testing.expectError(error.EmptyLine, parsePtyLine("\r", &test_scratch));
    const huge = try testing.allocator.alloc(u8, max_line_bytes + 1);
    defer testing.allocator.free(huge);
    @memset(huge, 'x');
    try testing.expectError(error.LineTooLong, parsePtyLine(huge, &test_scratch));
    try testing.expectError(error.MalformedEvent, parsePtyLine("not json at all", &test_scratch));
    try testing.expectError(error.MalformedEvent, parsePtyLine("[1,2,3]", &test_scratch));
    try testing.expectError(error.MalformedEvent, parsePtyLine("{\"no_event\":true}", &test_scratch));
    try testing.expectError(error.UnknownEvent, parsePtyLine("{\"event\":\"message\",\"payload\":{}}", &test_scratch));
}

test "parse tolerates trailing carriage return" {
    const event = try parsePtyLine("{\"event\":\"broker_exit\",\"reason\":\"shutdown_requested\"}\r", &test_scratch);
    try testing.expectEqual(BrokerExitReason.shutdown_requested, event.broker_exit);
}

// ------------------------------------------------------------- builders

test "input body wraps raw bytes in base64 JSON" {
    var out: [128]u8 = undefined;
    const body = try buildInputBody(&out, "echo hi\n");
    try testing.expectEqualStrings("{\"b64\":\"ZWNobyBoaQo=\"}", body);
}

test "input body round-trips arbitrary binary input" {
    var raw: [256]u8 = undefined;
    for (&raw, 0..) |*b, i| b.* = @intCast(i);
    var out: [512]u8 = undefined;
    const body = try buildInputBody(&out, &raw);
    // Body must be legal against the broker's own parser shape:
    // starts {"b64":" and ends "} with pure base64 between.
    try testing.expect(std.mem.startsWith(u8, body, "{\"b64\":\""));
    try testing.expect(std.mem.endsWith(u8, body, "\"}"));
    const b64 = body["{\"b64\":\"".len .. body.len - 2];
    var decoded: [256]u8 = undefined;
    try std.base64.standard.Decoder.decode(&decoded, b64);
    try testing.expectEqualSlices(u8, &raw, &decoded);
}

test "input body enforces bounds" {
    var out: [input_body_bytes]u8 = undefined;
    try testing.expectError(error.EmptyInput, buildInputBody(&out, ""));
    const huge = try testing.allocator.alloc(u8, input_chunk_raw_bytes + 1);
    defer testing.allocator.free(huge);
    @memset(huge, 'x');
    try testing.expectError(error.InputTooLarge, buildInputBody(&out, huge));
    var tiny: [4]u8 = undefined;
    try testing.expectError(error.OutputTooSmall, buildInputBody(&tiny, "hello"));
}

test "input body at the chunk bound stays inside the POST body limit" {
    const raw = try testing.allocator.alloc(u8, input_chunk_raw_bytes);
    defer testing.allocator.free(raw);
    @memset(raw, 0xff);
    const out = try testing.allocator.alloc(u8, input_body_bytes);
    defer testing.allocator.free(out);
    const body = try buildInputBody(out, raw);
    try testing.expect(body.len <= post_body_limit_bytes);
}

test "input plan splits a large paste into ordered bounded bodies" {
    const raw = try testing.allocator.alloc(u8, input_chunk_raw_bytes * 2 + 100);
    defer testing.allocator.free(raw);
    for (raw, 0..) |*b, i| b.* = @intCast(i % 251);
    var plan = try InputPlan.init(raw);
    try testing.expectEqual(@as(usize, 3), plan.postCount());
    const out = try testing.allocator.alloc(u8, input_body_bytes);
    defer testing.allocator.free(out);
    var reassembled = std.array_list.Managed(u8).init(testing.allocator);
    defer reassembled.deinit();
    var bodies: usize = 0;
    while (try plan.next(out)) |body| {
        bodies += 1;
        try testing.expect(body.len <= post_body_limit_bytes);
        const b64 = body["{\"b64\":\"".len .. body.len - 2];
        const decoder = std.base64.standard.Decoder;
        const raw_len = try decoder.calcSizeForSlice(b64);
        const start = reassembled.items.len;
        try reassembled.resize(start + raw_len);
        try decoder.decode(reassembled.items[start..], b64);
    }
    try testing.expectEqual(@as(usize, 3), bodies);
    try testing.expectEqualSlices(u8, raw, reassembled.items);
    try testing.expectEqual(@as(?[]const u8, null), try plan.next(out));
}

test "input plan refuses empty input; single chunk passes through" {
    try testing.expectError(error.EmptyInput, InputPlan.init(""));
    var plan = try InputPlan.init("ls\n");
    try testing.expectEqual(@as(usize, 1), plan.postCount());
    var out: [64]u8 = undefined;
    const body = (try plan.next(&out)).?;
    try testing.expectEqualStrings("{\"b64\":\"bHMK\"}", body);
    try testing.expectEqual(@as(?[]const u8, null), try plan.next(&out));
}

test "resize body renders cols and rows and enforces bounds" {
    var out: [64]u8 = undefined;
    try testing.expectEqualStrings("{\"cols\":120,\"rows\":40}", try buildResizeBody(&out, 120, 40));
    try testing.expectEqualStrings("{\"cols\":1,\"rows\":1}", try buildResizeBody(&out, 1, 1));
    try testing.expectEqualStrings("{\"cols\":1000,\"rows\":1000}", try buildResizeBody(&out, 1000, 1000));
    try testing.expectError(error.InvalidSize, buildResizeBody(&out, 0, 40));
    try testing.expectError(error.InvalidSize, buildResizeBody(&out, 80, 0));
    try testing.expectError(error.InvalidSize, buildResizeBody(&out, 1001, 40));
    try testing.expectError(error.InvalidSize, buildResizeBody(&out, 80, 1001));
    var tiny: [8]u8 = undefined;
    try testing.expectError(error.OutputTooSmall, buildResizeBody(&tiny, 120, 40));
}

// ------------------------------------------------------------ transport

const listening_line = "{\"event\":\"listening\",\"port\":34609,\"token\":\"5341c3c1bee76b4e0666a641c60d8dcb\"}";

test "transport lifecycle: starting -> running -> exited" {
    var transport = Transport.init(&test_decode);
    try testing.expectEqual(TransportPhase.starting, transport.phase);
    try testing.expect(!transport.canSend());

    const incoming = try transport.onLine(listening_line, &test_scratch);
    try testing.expectEqual(Transport.Incoming.listening, incoming);
    try testing.expectEqual(TransportPhase.running, transport.phase);
    try testing.expect(transport.canSend());
    try testing.expectEqual(@as(u16, 34609), transport.port);
    try testing.expectEqualStrings("5341c3c1bee76b4e0666a641c60d8dcb", transport.authToken());

    const output = try transport.onLine("{\"event\":\"data\",\"b64\":\"aGkNCiQg\"}", &test_scratch);
    try testing.expectEqualStrings("hi\r\n$ ", output.output);

    const exit = try transport.onLine("{\"event\":\"pty_exit\",\"reason\":\"exited\",\"code\":0}", &test_scratch);
    try testing.expectEqual(@as(i64, 0), exit.pty_exit.code);
    try testing.expectEqual(TransportPhase.exited, transport.phase);
    try testing.expect(!transport.canSend());
    try testing.expectEqual(@as(i64, 0), transport.exit.?.code);
}

test "transport decodes output into the caller buffer" {
    var transport = Transport.init(&test_decode);
    _ = try transport.onLine(listening_line, &test_scratch);
    const incoming = try transport.onLine("{\"event\":\"data\",\"b64\":\"VkVMT0NJVFlfUFRZXzQyCg==\"}", &test_scratch);
    try testing.expectEqualStrings("VELOCITY_PTY_42\n", incoming.output);
    // The returned slice borrows the decode buffer.
    try testing.expectEqual(@intFromPtr(&test_decode), @intFromPtr(incoming.output.ptr));
}

test "transport enforces event ordering" {
    var transport = Transport.init(&test_decode);
    // Output before the handshake is a protocol violation.
    try testing.expectError(error.ProtocolViolation, transport.onLine("{\"event\":\"data\",\"b64\":\"aGk=\"}", &test_scratch));
    _ = try transport.onLine(listening_line, &test_scratch);
    // A second listening line is a protocol violation.
    try testing.expectError(error.ProtocolViolation, transport.onLine(listening_line, &test_scratch));
    // Output after exit is a protocol violation.
    _ = try transport.onLine("{\"event\":\"broker_exit\",\"reason\":\"shutdown_requested\"}", &test_scratch);
    try testing.expectError(error.ProtocolViolation, transport.onLine("{\"event\":\"data\",\"b64\":\"aGk=\"}", &test_scratch));
}

test "transport survives malformed lines without state damage" {
    var transport = Transport.init(&test_decode);
    _ = try transport.onLine(listening_line, &test_scratch);
    try testing.expectError(error.MalformedEvent, transport.onLine("garbage", &test_scratch));
    try testing.expectError(error.InvalidBase64, transport.onLine("{\"event\":\"data\",\"b64\":\"@@@@\"}", &test_scratch));
    try testing.expectError(error.UnknownEvent, transport.onLine("{\"event\":\"nope\"}", &test_scratch));
    // Still running and still able to decode after the bad lines.
    try testing.expectEqual(TransportPhase.running, transport.phase);
    const incoming = try transport.onLine("{\"event\":\"data\",\"b64\":\"b2sK\"}", &test_scratch);
    try testing.expectEqualStrings("ok\n", incoming.output);
}

test "transport bounds decoded output by the caller buffer" {
    var small: [8]u8 = undefined;
    var transport = Transport.init(&small);
    _ = try transport.onLine(listening_line, &test_scratch);
    // 12 decoded bytes > 8-byte buffer.
    try testing.expectError(error.OutputTooLarge, transport.onLine("{\"event\":\"data\",\"b64\":\"aGVsbG8gd29ybGQh\"}", &test_scratch));
    // An event at exactly the buffer size passes.
    const incoming = try transport.onLine("{\"event\":\"data\",\"b64\":\"MTIzNDU2Nzg=\"}", &test_scratch);
    try testing.expectEqualStrings("12345678", incoming.output);
}

test "transport forwards broker errors without phase change" {
    var transport = Transport.init(&test_decode);
    _ = try transport.onLine(listening_line, &test_scratch);
    const incoming = try transport.onLine("{\"event\":\"error\",\"code\":\"pty_write_failed\",\"detail\":\"x\"}", &test_scratch);
    try testing.expectEqualStrings("pty_write_failed", incoming.broker_error.code);
    try testing.expectEqual(TransportPhase.running, transport.phase);
}

test "transport maps broker_exit reasons to exited phase" {
    var transport = Transport.init(&test_decode);
    _ = try transport.onLine(listening_line, &test_scratch);
    const incoming = try transport.onLine("{\"event\":\"broker_exit\",\"reason\":\"heartbeat_lapsed\"}", &test_scratch);
    try testing.expectEqual(BrokerExitReason.heartbeat_lapsed, incoming.broker_exit);
    try testing.expectEqual(TransportPhase.exited, transport.phase);
    try testing.expectEqual(@as(?PtyExit, null), transport.exit);
}
