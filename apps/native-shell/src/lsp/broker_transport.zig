//! Pure, bounded client-side state machine for the LSP sidecar broker
//! (`apps/native-shell/sidecar/lsp_broker.zig`).
//!
//! This module performs NO I/O: no SDK calls, no process spawning, no
//! sockets, no clocks. The app model owns the real effects — Governor
//! `spawn` of the broker, Effects `fetch` POSTs, Effects timers for
//! heartbeats and request timeouts — and drives this module with the
//! bytes and instants those effects produce:
//!
//!   * broker stdout NDJSON lines (spawn `.lines` events) go into
//!     `Transport.onLine`, which yields typed events and reassembles
//!     chunked server messages;
//!   * outgoing LSP payloads go through `Transport.planSend`, which
//!     yields the exact POST bodies (chunked above 48 KiB) for `fetch`;
//!   * `Session` allocates request ids, tracks pending requests with
//!     deadlines, and enforces the initialize -> initialized ->
//!     shutdown -> exit lifecycle;
//!   * builders/extractors cover the v1 message set: initialize(d),
//!     publishDiagnostics, textDocument/didOpen|didChange|didSave|
//!     didClose, shutdown/exit.
//!
//! Bounded everything: fixed caps on lines, messages, URIs, methods,
//! pending requests, and diagnostics. Malformed input is an error
//! value, never a crash (tests prove it).
//!
//! Time is a parameter: callers pass monotonic milliseconds into the
//! deadline APIs; nothing here reads a clock.

const std = @import("std");
const jsonrpc = @import("jsonrpc.zig");

// ---------------------------------------------------------------- limits

/// SDK spawn `.lines` ceiling; the broker never emits longer lines.
pub const max_line_bytes: usize = 256 * 1024;
/// Broker LSP payload cap in either direction.
pub const max_message_bytes: usize = 1024 * 1024;
/// POST bodies above this are split into /chunk parts of this size.
/// Kept well under the broker/SDK 64 KiB body cap for header headroom.
pub const post_body_limit_bytes: usize = 48 * 1024;
pub const token_len: usize = 32; // hex chars
pub const max_pending_requests: usize = 32;
pub const max_method_bytes: usize = 96;
pub const max_uri_bytes: usize = 512;
pub const max_diagnostics: usize = 64;
pub const max_diagnostic_message_bytes: usize = 256;
pub const max_server_name_bytes: usize = 64;
pub const max_error_detail_bytes: usize = 256;
/// Default deadline for pending requests (`Session.beginRequest`).
pub const default_request_timeout_ms: u64 = 15_000;
/// Suggested scratch size for `parseBrokerLine`/extractors: enough for
/// a std.json Value tree over the largest inline payload.
pub const recommended_scratch_bytes: usize = 1024 * 1024;

// -------------------------------------------------------- broker events

pub const ServerExit = struct {
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

pub const MessageChunk = struct {
    id: u64,
    seq: u32,
    last: bool,
    data_b64: []const u8,
};

pub const BrokerEvent = union(enum) {
    listening: struct { port: u16, token: [token_len]u8 },
    /// One complete LSP message, raw JSON borrowing the input line.
    message: []const u8,
    message_chunk: MessageChunk,
    server_exit: ServerExit,
    broker_exit: BrokerExitReason,
    broker_error: BrokerError,
};

pub const ParseLineError = error{
    LineTooLong,
    EmptyLine,
    MalformedEvent,
    UnknownEvent,
};

const message_prefix = "{\"event\":\"message\",\"payload\":";

/// Parse one broker NDJSON line into a typed event.
///
/// `scratch` backs the bounded JSON parse (a FixedBufferAllocator);
/// returned slices may borrow `line` or `scratch` and are valid until
/// either is reused. Malformed input returns an error; it never
/// crashes and never allocates outside `scratch`.
pub fn parseBrokerLine(line_raw: []const u8, scratch: []u8) ParseLineError!BrokerEvent {
    const line = std.mem.trimEnd(u8, line_raw, "\r");
    if (line.len == 0) return error.EmptyLine;
    if (line.len > max_line_bytes) return error.LineTooLong;

    // Fast path: `message` payloads are embedded raw by the broker
    // (fixed envelope, payload is the final field). Slicing avoids a
    // JSON parse of up to 192 KiB per message.
    if (std.mem.startsWith(u8, line, message_prefix)) {
        if (line[line.len - 1] != '}') return error.MalformedEvent;
        const payload = line[message_prefix.len .. line.len - 1];
        if (payload.len == 0) return error.MalformedEvent;
        // Cheap structural check (no allocation): catches truncated or
        // overlong lines whose braces don't balance. Full JSON
        // validation happens in the bounded extractors downstream.
        if (!balancedJsonNesting(payload)) return error.MalformedEvent;
        return .{ .message = payload };
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
        var out: BrokerEvent = .{ .listening = .{ .port = @intCast(port_value), .token = undefined } };
        @memcpy(&out.listening.token, token);
        return out;
    }
    if (std.mem.eql(u8, event, "message_chunk")) {
        const id = integerField(root, "id") orelse return error.MalformedEvent;
        const seq = integerField(root, "seq") orelse return error.MalformedEvent;
        const last = root.get("last") orelse return error.MalformedEvent;
        const data = stringField(root, "data_b64") orelse return error.MalformedEvent;
        if (id < 0 or seq < 0 or seq > std.math.maxInt(u32)) return error.MalformedEvent;
        if (last != .bool) return error.MalformedEvent;
        return .{ .message_chunk = .{
            .id = @intCast(id),
            .seq = @intCast(seq),
            .last = last.bool,
            .data_b64 = data,
        } };
    }
    if (std.mem.eql(u8, event, "server_exit")) {
        const reason = stringField(root, "reason") orelse return error.MalformedEvent;
        const code = integerField(root, "code") orelse return error.MalformedEvent;
        return .{ .server_exit = .{
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

/// String-aware brace/bracket balance scan: true when every `{`/`[`
/// closes and nothing closes early. Not a validator — just enough to
/// reject truncated payload embeddings without parsing.
fn balancedJsonNesting(payload: []const u8) bool {
    var depth: i32 = 0;
    var in_string = false;
    var escaped = false;
    for (payload) |c| {
        if (in_string) {
            if (escaped) {
                escaped = false;
            } else if (c == '\\') {
                escaped = true;
            } else if (c == '"') {
                in_string = false;
            }
            continue;
        }
        switch (c) {
            '"' => in_string = true,
            '{', '[' => depth += 1,
            '}', ']' => {
                depth -= 1;
                if (depth < 0) return false;
            },
            else => {},
        }
    }
    return depth == 0 and !in_string;
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

// -------------------------------------------------- chunk reassembly (in)

/// Client mirror of the broker's ChunkAssembler: concatenates decoded
/// `message_chunk` events (seq 0..n, last flagged) into one LSP
/// message. Bounded by the caller-provided buffer; every violation
/// resets state so the stream can recover at the next seq 0.
pub const ChunkReassembler = struct {
    buf: []u8,
    len: usize = 0,
    id: u64 = 0,
    next_seq: u32 = 0,
    active: bool = false,

    pub const Error = error{ ChunkOutOfOrder, ChunkIdMismatch, MessageTooLarge, InvalidBase64 };

    pub fn init(buf: []u8) ChunkReassembler {
        return .{ .buf = buf };
    }

    /// Returns the completed message (borrowing the internal buffer,
    /// valid until the next `accept`) when `last` is set, else null.
    pub fn accept(self: *ChunkReassembler, id: u64, seq: u32, last: bool, data_b64: []const u8) Error!?[]const u8 {
        if (seq == 0) {
            self.active = true;
            self.id = id;
            self.len = 0;
            self.next_seq = 0;
        } else {
            if (!self.active) return error.ChunkOutOfOrder;
            if (id != self.id) {
                self.reset();
                return error.ChunkIdMismatch;
            }
            if (seq != self.next_seq) {
                self.reset();
                return error.ChunkOutOfOrder;
            }
        }
        const decoder = std.base64.standard.Decoder;
        const raw_len = decoder.calcSizeForSlice(data_b64) catch {
            self.reset();
            return error.InvalidBase64;
        };
        if (self.len + raw_len > self.buf.len) {
            self.reset();
            return error.MessageTooLarge;
        }
        decoder.decode(self.buf[self.len..][0..raw_len], data_b64) catch {
            self.reset();
            return error.InvalidBase64;
        };
        self.len += raw_len;
        self.next_seq = seq +% 1;
        if (last) {
            self.active = false;
            return self.buf[0..self.len];
        }
        return null;
    }

    pub fn reset(self: *ChunkReassembler) void {
        self.active = false;
        self.len = 0;
        self.next_seq = 0;
    }
};

// ------------------------------------------------------ send planning (out)

pub const PostTarget = enum {
    /// POST /message — body is one complete LSP JSON message.
    message,
    /// POST /chunk — body is one part; carry the X-Chunk-* headers.
    chunk,
};

/// One HTTP POST the app must issue (as an Effects `fetch`), in order.
/// Every POST also carries `X-Broker-Token` (see `Transport.authToken`).
pub const OutboundPost = struct {
    target: PostTarget,
    /// Borrows the payload passed to `SendPlan.init`.
    body: []const u8,
    chunk_id: u64 = 0,
    chunk_seq: u32 = 0,
    chunk_last: bool = false,
};

/// Iterator over the POSTs for one outgoing LSP message. Payloads at
/// or below `post_body_limit_bytes` yield a single /message POST;
/// larger ones yield strictly-ordered /chunk POSTs which the app must
/// send serially (one assembly at a time per broker).
pub const SendPlan = struct {
    payload: []const u8,
    chunk_id: u64,
    offset: usize = 0,
    seq: u32 = 0,
    done: bool = false,

    pub const Error = error{ EmptyMessage, MessageTooLarge };

    pub fn init(payload: []const u8, chunk_id: u64) Error!SendPlan {
        if (payload.len == 0) return error.EmptyMessage;
        if (payload.len > max_message_bytes) return error.MessageTooLarge;
        return .{ .payload = payload, .chunk_id = chunk_id };
    }

    pub fn postCount(self: *const SendPlan) usize {
        if (self.payload.len <= post_body_limit_bytes) return 1;
        return (self.payload.len + post_body_limit_bytes - 1) / post_body_limit_bytes;
    }

    pub fn next(self: *SendPlan) ?OutboundPost {
        if (self.done) return null;
        if (self.payload.len <= post_body_limit_bytes) {
            self.done = true;
            return .{ .target = .message, .body = self.payload };
        }
        const take = @min(post_body_limit_bytes, self.payload.len - self.offset);
        const body = self.payload[self.offset .. self.offset + take];
        const seq = self.seq;
        self.offset += take;
        self.seq += 1;
        const last = self.offset >= self.payload.len;
        if (last) self.done = true;
        return .{
            .target = .chunk,
            .body = body,
            .chunk_id = self.chunk_id,
            .chunk_seq = seq,
            .chunk_last = last,
        };
    }
};

// ------------------------------------------------------------- session

pub const SessionPhase = enum {
    /// Nothing sent yet; `beginInitialize` is the only legal move.
    idle,
    /// initialize sent, response pending.
    initializing,
    /// initialized notification may be sent; document traffic is legal.
    ready,
    /// shutdown sent; only the exit notification remains.
    shutting_down,
    /// Server (or broker) is gone.
    exited,
    failed,
};

pub const CompletedRequest = struct {
    id: u64,
    method_storage: [max_method_bytes]u8,
    method_len: usize,

    pub fn method(self: *const CompletedRequest) []const u8 {
        return self.method_storage[0..self.method_len];
    }
};

pub const ExpiredRequest = CompletedRequest;

const PendingRequest = struct {
    id: u64 = 0,
    method_storage: [max_method_bytes]u8 = undefined,
    method_len: usize = 0,
    deadline_ms: u64 = 0,

    fn method(self: *const PendingRequest) []const u8 {
        return self.method_storage[0..self.method_len];
    }
};

/// Bounded LSP session bookkeeping: request-id allocation (reusing the
/// scaffold's `jsonrpc.RequestIdSequence`), a pending-request table
/// with caller-supplied monotonic-ms deadlines, and lifecycle
/// enforcement (initialize -> initialized -> shutdown -> exit).
pub const Session = struct {
    phase: SessionPhase = .idle,
    ids: jsonrpc.RequestIdSequence = .{},
    pending: [max_pending_requests]PendingRequest = [_]PendingRequest{.{}} ** max_pending_requests,
    pending_count: usize = 0,
    initialize_id: u64 = 0,
    shutdown_id: u64 = 0,

    pub const Error = error{
        WrongPhase,
        InvalidMethod,
        TooManyPendingRequests,
        RequestIdExhausted,
        UnknownRequest,
    };

    /// Allocate an id and record the request with a deadline. General
    /// requests require `.ready`; initialize/shutdown use the dedicated
    /// helpers below.
    pub fn beginRequest(self: *Session, method: []const u8, now_ms: u64, timeout_ms: u64) Error!u64 {
        if (self.phase != .ready) return error.WrongPhase;
        return self.track(method, now_ms, timeout_ms);
    }

    pub fn beginInitialize(self: *Session, now_ms: u64, timeout_ms: u64) Error!u64 {
        if (self.phase != .idle) return error.WrongPhase;
        const id = try self.track("initialize", now_ms, timeout_ms);
        self.phase = .initializing;
        self.initialize_id = id;
        return id;
    }

    /// The initialize response arrived. On success the caller must send
    /// the `initialized` notification (see `buildInitialized`) before
    /// any document traffic.
    pub fn onInitializeResponse(self: *Session, id: u64) Error!void {
        if (self.phase != .initializing or id != self.initialize_id) return error.WrongPhase;
        _ = try self.completeRequest(id);
        self.phase = .ready;
    }

    pub fn beginShutdown(self: *Session, now_ms: u64, timeout_ms: u64) Error!u64 {
        if (self.phase != .ready) return error.WrongPhase;
        const id = try self.track("shutdown", now_ms, timeout_ms);
        self.phase = .shutting_down;
        self.shutdown_id = id;
        return id;
    }

    /// The shutdown response arrived; the caller sends the `exit`
    /// notification (see `buildExit`) and then expects `server_exit`.
    pub fn onShutdownResponse(self: *Session, id: u64) Error!void {
        if (self.phase != .shutting_down or id != self.shutdown_id) return error.WrongPhase;
        _ = try self.completeRequest(id);
    }

    /// Resolve a response id against the pending table (any phase; late
    /// responses during shutdown still clear their slot).
    pub fn completeRequest(self: *Session, id: u64) Error!CompletedRequest {
        var index: usize = 0;
        while (index < self.pending_count) : (index += 1) {
            if (self.pending[index].id != id) continue;
            const completed: CompletedRequest = .{
                .id = id,
                .method_storage = self.pending[index].method_storage,
                .method_len = self.pending[index].method_len,
            };
            self.pending_count -= 1;
            if (index != self.pending_count) self.pending[index] = self.pending[self.pending_count];
            return completed;
        }
        return error.UnknownRequest;
    }

    /// Remove and report every pending request whose deadline passed.
    /// Returns how many were written to `out` (bounded by its length;
    /// call again if it was full). Timing out initialize or shutdown
    /// fails the session.
    pub fn expireOverdue(self: *Session, now_ms: u64, out: []ExpiredRequest) usize {
        var written: usize = 0;
        var index: usize = 0;
        while (index < self.pending_count) {
            if (self.pending[index].deadline_ms > now_ms or written >= out.len) {
                index += 1;
                continue;
            }
            const expired_id = self.pending[index].id;
            out[written] = .{
                .id = expired_id,
                .method_storage = self.pending[index].method_storage,
                .method_len = self.pending[index].method_len,
            };
            written += 1;
            self.pending_count -= 1;
            if (index != self.pending_count) self.pending[index] = self.pending[self.pending_count];
            if ((self.phase == .initializing and expired_id == self.initialize_id) or
                (self.phase == .shutting_down and expired_id == self.shutdown_id))
            {
                self.phase = .failed;
            }
        }
        return written;
    }

    /// Document notifications (didOpen/didChange/didSave/didClose) are
    /// only legal while ready.
    pub fn canSendDocumentEvents(self: *const Session) bool {
        return self.phase == .ready;
    }

    pub fn onServerExit(self: *Session) void {
        // Expected after shutdown/exit; premature exit is still exited —
        // the app decides whether to restart via the Governor.
        self.phase = .exited;
        self.pending_count = 0;
    }

    pub fn fail(self: *Session) void {
        self.phase = .failed;
        self.pending_count = 0;
    }

    pub fn pendingCount(self: *const Session) usize {
        return self.pending_count;
    }

    fn track(self: *Session, method: []const u8, now_ms: u64, timeout_ms: u64) Error!u64 {
        if (method.len == 0 or method.len > max_method_bytes) return error.InvalidMethod;
        if (self.pending_count >= max_pending_requests) return error.TooManyPendingRequests;
        const request_id = self.ids.take() catch return error.RequestIdExhausted;
        const id = request_id.integer;
        var slot = &self.pending[self.pending_count];
        slot.id = id;
        @memcpy(slot.method_storage[0..method.len], method);
        slot.method_len = method.len;
        slot.deadline_ms = now_ms +| timeout_ms;
        self.pending_count += 1;
        return id;
    }
};

// ------------------------------------------------------------- builders

pub const BuildError = error{OutputTooSmall};

/// Bounded output cursor with inline JSON string escaping.
const Builder = struct {
    out: []u8,
    len: usize = 0,

    fn raw(self: *Builder, bytes: []const u8) BuildError!void {
        if (self.len + bytes.len > self.out.len) return error.OutputTooSmall;
        @memcpy(self.out[self.len..][0..bytes.len], bytes);
        self.len += bytes.len;
    }

    fn integer(self: *Builder, value: i64) BuildError!void {
        var buf: [24]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "{d}", .{value}) catch unreachable;
        try self.raw(text);
    }

    /// Append `"..."` with full JSON escaping of `src`.
    fn string(self: *Builder, src: []const u8) BuildError!void {
        try self.raw("\"");
        for (src) |c| {
            switch (c) {
                '"' => try self.raw("\\\""),
                '\\' => try self.raw("\\\\"),
                '\n' => try self.raw("\\n"),
                '\r' => try self.raw("\\r"),
                '\t' => try self.raw("\\t"),
                0x08 => try self.raw("\\b"),
                0x0c => try self.raw("\\f"),
                else => {
                    if (c >= 0x20) {
                        if (self.len >= self.out.len) return error.OutputTooSmall;
                        self.out[self.len] = c;
                        self.len += 1;
                    } else {
                        var u: [6]u8 = undefined;
                        _ = std.fmt.bufPrint(&u, "\\u{x:0>4}", .{c}) catch unreachable;
                        try self.raw(&u);
                    }
                },
            }
        }
        try self.raw("\"");
    }

    fn slice(self: *const Builder) []const u8 {
        return self.out[0..self.len];
    }
};

pub const BuildUriError = error{
    OutputTooSmall,
    RootNotAbsolute,
    InvalidPath,
    UriTooLong,
};

/// Build a `file://` URI from an absolute workspace root and a
/// workspace-relative path. Percent-encodes everything outside the RFC
/// 3986 unreserved set (plus `/`), rejects traversal (`.`/`..`
/// segments), backslashes, absolute rel paths, and empty input.
/// Bounded by `max_uri_bytes` regardless of `out.len`.
pub fn buildFileUri(out: []u8, workspace_root: []const u8, rel_path: []const u8) BuildUriError![]const u8 {
    if (workspace_root.len == 0 or workspace_root[0] != '/') return error.RootNotAbsolute;
    if (rel_path.len == 0 or rel_path[0] == '/') return error.InvalidPath;
    try validatePathBytes(workspace_root);
    try validatePathBytes(rel_path);
    try rejectDotSegments(rel_path);

    var builder: Builder = .{ .out = out };
    builder.raw("file://") catch return error.OutputTooSmall;
    const root = std.mem.trimEnd(u8, workspace_root, "/");
    try appendEncodedPath(&builder, root);
    builder.raw("/") catch return error.OutputTooSmall;
    try appendEncodedPath(&builder, rel_path);
    if (builder.len > max_uri_bytes) return error.UriTooLong;
    return builder.slice();
}

fn validatePathBytes(path: []const u8) BuildUriError!void {
    for (path) |c| {
        if (c == 0 or c == '\\') return error.InvalidPath;
    }
}

fn rejectDotSegments(path: []const u8) BuildUriError!void {
    var segments = std.mem.splitScalar(u8, path, '/');
    while (segments.next()) |segment| {
        if (segment.len == 0) return error.InvalidPath; // "a//b"
        if (std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) {
            return error.InvalidPath;
        }
    }
}

fn appendEncodedPath(builder: *Builder, path: []const u8) BuildUriError!void {
    for (path) |c| {
        const unreserved = std.ascii.isAlphanumeric(c) or
            c == '-' or c == '.' or c == '_' or c == '~' or c == '/';
        if (unreserved) {
            builder.raw(&[_]u8{c}) catch return error.OutputTooSmall;
        } else {
            var enc: [3]u8 = undefined;
            _ = std.fmt.bufPrint(&enc, "%{X:0>2}", .{c}) catch unreachable;
            builder.raw(&enc) catch return error.OutputTooSmall;
        }
    }
}

/// Minimal v1 initialize request: null processId, the workspace root
/// URI, and just the client capabilities this app acts on.
pub fn buildInitialize(out: []u8, id: u64, root_uri: []const u8) BuildError![]const u8 {
    var builder: Builder = .{ .out = out };
    try builder.raw("{\"jsonrpc\":\"2.0\",\"id\":");
    try builder.integer(@intCast(id));
    try builder.raw(",\"method\":\"initialize\",\"params\":{\"processId\":null,\"rootUri\":");
    try builder.string(root_uri);
    try builder.raw(",\"capabilities\":{\"textDocument\":{\"publishDiagnostics\":{},\"synchronization\":{\"didSave\":true}}},\"workspaceFolders\":null}}");
    return builder.slice();
}

pub fn buildInitialized(out: []u8) BuildError![]const u8 {
    var builder: Builder = .{ .out = out };
    try builder.raw("{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}");
    return builder.slice();
}

pub fn buildDidOpen(out: []u8, uri: []const u8, language_id: []const u8, version: i64, text: []const u8) BuildError![]const u8 {
    var builder: Builder = .{ .out = out };
    try builder.raw("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":");
    try builder.string(uri);
    try builder.raw(",\"languageId\":");
    try builder.string(language_id);
    try builder.raw(",\"version\":");
    try builder.integer(version);
    try builder.raw(",\"text\":");
    try builder.string(text);
    try builder.raw("}}}");
    return builder.slice();
}

/// Full-document sync (one contentChanges entry with the whole text) —
/// matches the `textDocumentSync: 1` servers advertise for v1.
pub fn buildDidChange(out: []u8, uri: []const u8, version: i64, text: []const u8) BuildError![]const u8 {
    var builder: Builder = .{ .out = out };
    try builder.raw("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":");
    try builder.string(uri);
    try builder.raw(",\"version\":");
    try builder.integer(version);
    try builder.raw("},\"contentChanges\":[{\"text\":");
    try builder.string(text);
    try builder.raw("}]}}");
    return builder.slice();
}

pub fn buildDidSave(out: []u8, uri: []const u8) BuildError![]const u8 {
    var builder: Builder = .{ .out = out };
    try builder.raw("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didSave\",\"params\":{\"textDocument\":{\"uri\":");
    try builder.string(uri);
    try builder.raw("}}}");
    return builder.slice();
}

pub fn buildDidClose(out: []u8, uri: []const u8) BuildError![]const u8 {
    var builder: Builder = .{ .out = out };
    try builder.raw("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didClose\",\"params\":{\"textDocument\":{\"uri\":");
    try builder.string(uri);
    try builder.raw("}}}");
    return builder.slice();
}

pub fn buildShutdown(out: []u8, id: u64) BuildError![]const u8 {
    var builder: Builder = .{ .out = out };
    try builder.raw("{\"jsonrpc\":\"2.0\",\"id\":");
    try builder.integer(@intCast(id));
    try builder.raw(",\"method\":\"shutdown\",\"params\":null}");
    return builder.slice();
}

pub fn buildExit(out: []u8) BuildError![]const u8 {
    var builder: Builder = .{ .out = out };
    try builder.raw("{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":null}");
    return builder.slice();
}

// ----------------------------------------------------------- extraction

pub const ExtractError = error{
    MalformedMessage,
    ScratchExhausted,
    UriTooLong,
};

pub const MessageKind = union(enum) {
    /// A response to one of our requests (`id`, integer for v1).
    response: u64,
    publish_diagnostics,
    /// A request FROM the server (has both method and id); v1 answers
    /// with MethodNotFound or ignores per method. Id may borrow scratch.
    server_request: jsonrpc.RequestId,
    /// Any other notification.
    notification,
};

/// Cheap first-pass classification of one server LSP message so the
/// app can route it (respond / extract diagnostics / ignore).
pub fn classifyServerMessage(payload: []const u8, scratch: []u8) ExtractError!MessageKind {
    const root = try parseObject(payload, scratch);
    const method = stringField(root, "method");
    const id_value = root.get("id");
    if (method) |m| {
        if (id_value != null and id_value.? != .null) {
            const id: jsonrpc.RequestId = switch (id_value.?) {
                .integer => |i| blk: {
                    if (i < 0) return error.MalformedMessage;
                    break :blk .{ .integer = @intCast(i) };
                },
                .string => |s| .{ .string = truncate(s, jsonrpc.max_string_id_bytes) },
                else => return error.MalformedMessage,
            };
            return .{ .server_request = id };
        }
        if (std.mem.eql(u8, m, "textDocument/publishDiagnostics")) return .publish_diagnostics;
        return .notification;
    }
    if (id_value) |id| {
        switch (id) {
            .integer => |i| {
                if (i < 0) return error.MalformedMessage;
                return .{ .response = @intCast(i) };
            },
            else => return error.MalformedMessage,
        }
    }
    return error.MalformedMessage;
}

pub const InitializeOutcome = struct {
    /// True when the response carried a result (vs a JSON-RPC error).
    ok: bool = false,
    /// True when result.capabilities is present (an object).
    has_capabilities: bool = false,
    server_name_storage: [max_server_name_bytes]u8 = undefined,
    server_name_len: usize = 0,
    error_message_storage: [max_error_detail_bytes]u8 = undefined,
    error_message_len: usize = 0,

    pub fn serverName(self: *const InitializeOutcome) []const u8 {
        return self.server_name_storage[0..self.server_name_len];
    }

    pub fn errorMessage(self: *const InitializeOutcome) []const u8 {
        return self.error_message_storage[0..self.error_message_len];
    }
};

/// Typed view of an initialize response (already matched to the
/// session's initialize id by the caller via `classifyServerMessage`).
pub fn extractInitializeResult(payload: []const u8, scratch: []u8) ExtractError!InitializeOutcome {
    const root = try parseObject(payload, scratch);
    var outcome: InitializeOutcome = .{};
    if (root.get("result")) |result| {
        if (result != .object) return error.MalformedMessage;
        outcome.ok = true;
        if (result.object.get("capabilities")) |caps| {
            outcome.has_capabilities = caps == .object;
        }
        if (result.object.get("serverInfo")) |info| {
            if (info == .object) {
                if (stringField(info.object, "name")) |name| {
                    const n = @min(name.len, max_server_name_bytes);
                    @memcpy(outcome.server_name_storage[0..n], name[0..n]);
                    outcome.server_name_len = n;
                }
            }
        }
        return outcome;
    }
    if (root.get("error")) |err| {
        if (err == .object) {
            if (stringField(err.object, "message")) |message| {
                const n = @min(message.len, max_error_detail_bytes);
                @memcpy(outcome.error_message_storage[0..n], message[0..n]);
                outcome.error_message_len = n;
            }
        }
        return outcome; // ok = false
    }
    return error.MalformedMessage;
}

pub const Severity = enum(u8) {
    @"error" = 1,
    warning = 2,
    information = 3,
    hint = 4,
};

pub const Position = struct {
    line: u32,
    character: u32,
};

pub const Range = struct {
    start: Position,
    end: Position,
};

pub const Diagnostic = struct {
    range: Range = .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 0, .character = 0 },
    },
    severity: Severity = .@"error",
    message_storage: [max_diagnostic_message_bytes]u8 = undefined,
    message_len: usize = 0,
    message_truncated: bool = false,

    pub fn message(self: *const Diagnostic) []const u8 {
        return self.message_storage[0..self.message_len];
    }
};

pub const DiagnosticsPage = struct {
    uri_storage: [max_uri_bytes]u8 = undefined,
    uri_len: usize = 0,
    items: [max_diagnostics]Diagnostic = [_]Diagnostic{.{}} ** max_diagnostics,
    count: usize = 0,
    /// Diagnostics beyond `max_diagnostics` (kept honest, not silent).
    dropped: usize = 0,
    /// Array entries that were not valid diagnostic objects.
    skipped_malformed: usize = 0,

    pub fn uri(self: *const DiagnosticsPage) []const u8 {
        return self.uri_storage[0..self.uri_len];
    }

    pub fn item(self: *const DiagnosticsPage, index: usize) ?*const Diagnostic {
        if (index >= self.count) return null;
        return &self.items[index];
    }
};

/// Extract a bounded snapshot of one publishDiagnostics notification.
/// Individual malformed diagnostics are skipped (and counted), never
/// fatal; a malformed envelope (missing uri/diagnostics) is an error.
pub fn extractPublishDiagnostics(payload: []const u8, scratch: []u8, out: *DiagnosticsPage) ExtractError!void {
    const root = try parseObject(payload, scratch);
    const params_value = root.get("params") orelse return error.MalformedMessage;
    if (params_value != .object) return error.MalformedMessage;
    const params = params_value.object;
    const uri = stringField(params, "uri") orelse return error.MalformedMessage;
    if (uri.len == 0) return error.MalformedMessage;
    if (uri.len > max_uri_bytes) return error.UriTooLong;
    const list_value = params.get("diagnostics") orelse return error.MalformedMessage;
    if (list_value != .array) return error.MalformedMessage;

    out.* = .{};
    @memcpy(out.uri_storage[0..uri.len], uri);
    out.uri_len = uri.len;

    for (list_value.array.items) |entry| {
        if (entry != .object) {
            out.skipped_malformed += 1;
            continue;
        }
        if (out.count >= max_diagnostics) {
            out.dropped += 1;
            continue;
        }
        if (extractOneDiagnostic(entry.object)) |diagnostic| {
            out.items[out.count] = diagnostic;
            out.count += 1;
        } else {
            out.skipped_malformed += 1;
        }
    }
}

fn extractOneDiagnostic(object: std.json.ObjectMap) ?Diagnostic {
    var diagnostic: Diagnostic = .{};
    const range_value = object.get("range") orelse return null;
    if (range_value != .object) return null;
    const start = extractPosition(range_value.object, "start") orelse return null;
    const end = extractPosition(range_value.object, "end") orelse return null;
    if (end.line < start.line or (end.line == start.line and end.character < start.character)) return null;
    diagnostic.range = .{ .start = start, .end = end };

    if (object.get("severity")) |severity| {
        // Missing/invalid severity stays at the default (.error), the
        // convention editors use for untagged diagnostics.
        if (severity == .integer and severity.integer >= 1 and severity.integer <= 4) {
            diagnostic.severity = @enumFromInt(@as(u8, @intCast(severity.integer)));
        }
    }

    const message = stringField(object, "message") orelse return null;
    const n = @min(message.len, max_diagnostic_message_bytes);
    @memcpy(diagnostic.message_storage[0..n], message[0..n]);
    diagnostic.message_len = n;
    diagnostic.message_truncated = message.len > n;
    return diagnostic;
}

fn extractPosition(range: std.json.ObjectMap, name: []const u8) ?Position {
    const value = range.get(name) orelse return null;
    if (value != .object) return null;
    const line = integerField(value.object, "line") orelse return null;
    const character = integerField(value.object, "character") orelse return null;
    if (line < 0 or character < 0) return null;
    return .{
        .line = std.math.cast(u32, line) orelse return null,
        .character = std.math.cast(u32, character) orelse return null,
    };
}

fn parseObject(payload: []const u8, scratch: []u8) ExtractError!std.json.ObjectMap {
    if (payload.len == 0 or payload.len > max_message_bytes) return error.MalformedMessage;
    var fba = std.heap.FixedBufferAllocator.init(scratch);
    const parsed = std.json.parseFromSlice(std.json.Value, fba.allocator(), payload, .{}) catch |err| {
        return if (err == error.OutOfMemory) error.ScratchExhausted else error.MalformedMessage;
    };
    return switch (parsed.value) {
        .object => |object| object,
        else => error.MalformedMessage,
    };
}

// ------------------------------------------------------------ transport

pub const TransportPhase = enum {
    /// Broker spawned; waiting for its first (listening) line.
    awaiting_listening,
    /// Port + token known; POSTs are legal.
    ready,
    /// Broker announced its own exit (or the server's); expect on_exit.
    broker_gone,
};

/// The top-level state machine the app model drives. Owns the broker
/// handshake (listening line), inbound chunk reassembly, the LSP
/// session, and outgoing chunk-id allocation. Still pure: the app maps
/// `Incoming`/`SendPlan` onto spawn lines and fetch POSTs.
pub const Transport = struct {
    phase: TransportPhase = .awaiting_listening,
    port: u16 = 0,
    token: [token_len]u8 = [_]u8{'0'} ** token_len,
    session: Session = .{},
    reassembler: ChunkReassembler,
    next_send_chunk_id: u64 = 1,

    pub const Incoming = union(enum) {
        /// Nothing actionable (e.g. a chunk part was buffered).
        none,
        /// Handshake done: `port`/`token` are set. Send initialize.
        listening,
        /// One complete LSP message (borrows the line or the
        /// reassembly buffer until the next `onLine`).
        lsp_message: []const u8,
        server_exit: ServerExit,
        broker_exit: BrokerExitReason,
        broker_error: BrokerError,
    };

    pub const OnLineError = ParseLineError || ChunkReassembler.Error || error{ProtocolViolation};

    pub fn init(reassembly_buf: []u8) Transport {
        return .{ .reassembler = ChunkReassembler.init(reassembly_buf) };
    }

    /// Feed one broker stdout line (spawn `on_line`). Errors are
    /// per-line: the caller logs/counts them and keeps feeding — a bad
    /// line never poisons transport state beyond its own chunk stream.
    pub fn onLine(self: *Transport, line: []const u8, scratch: []u8) OnLineError!Incoming {
        const event = try parseBrokerLine(line, scratch);
        switch (event) {
            .listening => |listening| {
                if (self.phase != .awaiting_listening) return error.ProtocolViolation;
                self.port = listening.port;
                self.token = listening.token;
                self.phase = .ready;
                return .listening;
            },
            .message => |payload| {
                if (self.phase != .ready) return error.ProtocolViolation;
                return .{ .lsp_message = payload };
            },
            .message_chunk => |chunk| {
                if (self.phase != .ready) return error.ProtocolViolation;
                const complete = try self.reassembler.accept(chunk.id, chunk.seq, chunk.last, chunk.data_b64);
                if (complete) |message| return .{ .lsp_message = message };
                return .none;
            },
            .server_exit => |exit| {
                self.phase = .broker_gone;
                self.session.onServerExit();
                return .{ .server_exit = exit };
            },
            .broker_exit => |reason| {
                self.phase = .broker_gone;
                self.session.onServerExit();
                return .{ .broker_exit = reason };
            },
            .broker_error => |broker_error| return .{ .broker_error = broker_error },
        }
    }

    /// Plan the POST(s) for one outgoing LSP payload; allocates a fresh
    /// chunk id when the payload needs /chunk. Only legal once ready.
    pub fn planSend(self: *Transport, payload: []const u8) (SendPlan.Error || error{NotReady})!SendPlan {
        if (self.phase != .ready) return error.NotReady;
        var chunk_id: u64 = 0;
        if (payload.len > post_body_limit_bytes) {
            chunk_id = self.next_send_chunk_id;
            self.next_send_chunk_id += 1;
        }
        return SendPlan.init(payload, chunk_id);
    }

    /// Value for the `X-Broker-Token` header on every POST.
    pub fn authToken(self: *const Transport) []const u8 {
        return &self.token;
    }
};

// ================================================================ tests

const testing = std.testing;

var test_scratch: [recommended_scratch_bytes]u8 = undefined;

// ------------------------------------------------ broker event parsing

test "parse listening event yields port and token" {
    const line = "{\"event\":\"listening\",\"port\":38617,\"token\":\"fee8c75f408e830831425370bb633345\"}";
    const event = try parseBrokerLine(line, &test_scratch);
    try testing.expectEqual(@as(u16, 38617), event.listening.port);
    try testing.expectEqualStrings("fee8c75f408e830831425370bb633345", &event.listening.token);
}

test "parse listening rejects bad ports and tokens" {
    try testing.expectError(error.MalformedEvent, parseBrokerLine("{\"event\":\"listening\",\"port\":0,\"token\":\"fee8c75f408e830831425370bb633345\"}", &test_scratch));
    try testing.expectError(error.MalformedEvent, parseBrokerLine("{\"event\":\"listening\",\"port\":99999,\"token\":\"fee8c75f408e830831425370bb633345\"}", &test_scratch));
    try testing.expectError(error.MalformedEvent, parseBrokerLine("{\"event\":\"listening\",\"port\":8080,\"token\":\"short\"}", &test_scratch));
    // right length, non-hex
    try testing.expectError(error.MalformedEvent, parseBrokerLine("{\"event\":\"listening\",\"port\":8080,\"token\":\"zzz8c75f408e830831425370bb633345\"}", &test_scratch));
    try testing.expectError(error.MalformedEvent, parseBrokerLine("{\"event\":\"listening\",\"port\":8080}", &test_scratch));
    try testing.expectError(error.MalformedEvent, parseBrokerLine("{\"event\":\"listening\",\"port\":\"8080\",\"token\":\"fee8c75f408e830831425370bb633345\"}", &test_scratch));
}

test "parse message event returns the raw payload slice" {
    const line = "{\"event\":\"message\",\"payload\":{\"jsonrpc\":\"2.0\",\"id\":42,\"result\":{\"capabilities\":{}}}}";
    const event = try parseBrokerLine(line, &test_scratch);
    try testing.expectEqualStrings("{\"jsonrpc\":\"2.0\",\"id\":42,\"result\":{\"capabilities\":{}}}", event.message);
}

test "parse message tolerates nested braces and trailing carriage return" {
    const line = "{\"event\":\"message\",\"payload\":{\"a\":{\"b\":{\"c\":[1,2,{\"d\":\"}}\"}]}}}}\r";
    const event = try parseBrokerLine(line, &test_scratch);
    try testing.expectEqualStrings("{\"a\":{\"b\":{\"c\":[1,2,{\"d\":\"}}\"}]}}}", event.message);
}

test "parse message rejects empty and unterminated payloads" {
    try testing.expectError(error.MalformedEvent, parseBrokerLine("{\"event\":\"message\",\"payload\":}", &test_scratch));
    try testing.expectError(error.MalformedEvent, parseBrokerLine("{\"event\":\"message\",\"payload\":{\"a\":1}", &test_scratch));
}

test "parse message_chunk event extracts id seq last and data" {
    const line = "{\"event\":\"message_chunk\",\"id\":3,\"seq\":1,\"last\":true,\"data_b64\":\"aGVsbG8=\"}";
    const event = try parseBrokerLine(line, &test_scratch);
    try testing.expectEqual(@as(u64, 3), event.message_chunk.id);
    try testing.expectEqual(@as(u32, 1), event.message_chunk.seq);
    try testing.expect(event.message_chunk.last);
    try testing.expectEqualStrings("aGVsbG8=", event.message_chunk.data_b64);
}

test "parse message_chunk rejects missing or mistyped fields" {
    try testing.expectError(error.MalformedEvent, parseBrokerLine("{\"event\":\"message_chunk\",\"id\":3,\"seq\":1,\"data_b64\":\"aa==\"}", &test_scratch));
    try testing.expectError(error.MalformedEvent, parseBrokerLine("{\"event\":\"message_chunk\",\"id\":-1,\"seq\":0,\"last\":false,\"data_b64\":\"aa==\"}", &test_scratch));
    try testing.expectError(error.MalformedEvent, parseBrokerLine("{\"event\":\"message_chunk\",\"id\":1,\"seq\":0,\"last\":\"yes\",\"data_b64\":\"aa==\"}", &test_scratch));
}

test "parse server_exit and broker_exit events" {
    const exited = try parseBrokerLine("{\"event\":\"server_exit\",\"reason\":\"exited\",\"code\":0}", &test_scratch);
    try testing.expectEqual(@as(i64, 0), exited.server_exit.code);
    try testing.expect(exited.server_exit.reason == .exited);
    const signalled = try parseBrokerLine("{\"event\":\"server_exit\",\"reason\":\"signal\",\"code\":15}", &test_scratch);
    try testing.expect(signalled.server_exit.reason == .signal);
    const lapsed = try parseBrokerLine("{\"event\":\"broker_exit\",\"reason\":\"heartbeat_lapsed\"}", &test_scratch);
    try testing.expect(lapsed.broker_exit == .heartbeat_lapsed);
    const requested = try parseBrokerLine("{\"event\":\"broker_exit\",\"reason\":\"shutdown_requested\"}", &test_scratch);
    try testing.expect(requested.broker_exit == .shutdown_requested);
    const odd = try parseBrokerLine("{\"event\":\"broker_exit\",\"reason\":\"later-version-reason\"}", &test_scratch);
    try testing.expect(odd.broker_exit == .unknown);
}

test "parse error event carries bounded code and detail" {
    const event = try parseBrokerLine("{\"event\":\"error\",\"code\":\"oversized_frame\",\"detail\":\"declared 2 MiB\"}", &test_scratch);
    try testing.expectEqualStrings("oversized_frame", event.broker_error.code);
    try testing.expectEqualStrings("declared 2 MiB", event.broker_error.detail);
}

test "parse rejects garbage without crashing" {
    try testing.expectError(error.EmptyLine, parseBrokerLine("", &test_scratch));
    try testing.expectError(error.EmptyLine, parseBrokerLine("\r", &test_scratch));
    try testing.expectError(error.MalformedEvent, parseBrokerLine("not json at all", &test_scratch));
    try testing.expectError(error.MalformedEvent, parseBrokerLine("[1,2,3]", &test_scratch));
    try testing.expectError(error.MalformedEvent, parseBrokerLine("{\"no_event\":true}", &test_scratch));
    try testing.expectError(error.MalformedEvent, parseBrokerLine("{\"event\":42}", &test_scratch));
    try testing.expectError(error.UnknownEvent, parseBrokerLine("{\"event\":\"future_thing\",\"x\":1}", &test_scratch));
    try testing.expectError(error.MalformedEvent, parseBrokerLine("{\"event\":\"listening\"", &test_scratch));
}

test "parse enforces the line ceiling" {
    const big = try testing.allocator.alloc(u8, max_line_bytes + 1);
    defer testing.allocator.free(big);
    @memset(big, 'x');
    try testing.expectError(error.LineTooLong, parseBrokerLine(big, &test_scratch));
}

test "parse survives scratch exhaustion as an error" {
    var tiny: [32]u8 = undefined;
    // Deep nesting exhausts the fixed scratch; must be an error, not a crash.
    try testing.expectError(error.MalformedEvent, parseBrokerLine("{\"event\":\"listening\",\"port\":[[[[[[[[[[1]]]]]]]]]],\"token\":\"x\"}", &tiny));
}

// ---------------------------------------------------- chunk reassembly

test "chunk reassembler concatenates decoded chunks in order" {
    var buf: [64]u8 = undefined;
    var reassembler = ChunkReassembler.init(&buf);
    // "hello" + " " + "world" in three chunks
    try testing.expectEqual(null, try reassembler.accept(9, 0, false, "aGVsbG8="));
    try testing.expectEqual(null, try reassembler.accept(9, 1, false, "IA=="));
    const complete = (try reassembler.accept(9, 2, true, "d29ybGQ=")).?;
    try testing.expectEqualStrings("hello world", complete);
}

test "chunk reassembler handles a single-chunk message" {
    var buf: [64]u8 = undefined;
    var reassembler = ChunkReassembler.init(&buf);
    const complete = (try reassembler.accept(1, 0, true, "c29sbw==")).?;
    try testing.expectEqualStrings("solo", complete);
}

test "chunk reassembler rejects disorder mismatch and bad base64" {
    var buf: [64]u8 = undefined;
    var reassembler = ChunkReassembler.init(&buf);
    try testing.expectError(error.ChunkOutOfOrder, reassembler.accept(1, 1, false, "aQ=="));
    _ = try reassembler.accept(1, 0, false, "aQ==");
    try testing.expectError(error.ChunkIdMismatch, reassembler.accept(2, 1, false, "aQ=="));
    _ = try reassembler.accept(3, 0, false, "aQ==");
    try testing.expectError(error.ChunkOutOfOrder, reassembler.accept(3, 2, true, "aQ=="));
    _ = try reassembler.accept(4, 0, false, "aQ==");
    try testing.expectError(error.InvalidBase64, reassembler.accept(4, 1, true, "!!not-base64!!"));
    // Every failure resets: a fresh seq 0 works.
    const complete = (try reassembler.accept(5, 0, true, "b2s=")).?;
    try testing.expectEqualStrings("ok", complete);
}

test "chunk reassembler bounds the assembled message" {
    var buf: [8]u8 = undefined;
    var reassembler = ChunkReassembler.init(&buf);
    _ = try reassembler.accept(1, 0, false, "MTIzNDU2Nzg="); // "12345678"
    try testing.expectError(error.MessageTooLarge, reassembler.accept(1, 1, true, "OQ==")); // "9"
}

// -------------------------------------------------------- send planning

test "send plan emits one /message post at or below the limit" {
    var payload_buf: [post_body_limit_bytes]u8 = undefined;
    @memset(&payload_buf, 'a');
    var plan = try SendPlan.init(&payload_buf, 0);
    try testing.expectEqual(@as(usize, 1), plan.postCount());
    const post = plan.next().?;
    try testing.expectEqual(PostTarget.message, post.target);
    try testing.expectEqual(payload_buf.len, post.body.len);
    try testing.expectEqual(null, plan.next());
}

test "send plan chunks payloads above 48 KiB with ordered flagged parts" {
    const payload = try testing.allocator.alloc(u8, post_body_limit_bytes * 2 + 100);
    defer testing.allocator.free(payload);
    @memset(payload, 'b');
    var plan = try SendPlan.init(payload, 12);
    try testing.expectEqual(@as(usize, 3), plan.postCount());
    var total: usize = 0;
    var expected_seq: u32 = 0;
    while (plan.next()) |post| {
        try testing.expectEqual(PostTarget.chunk, post.target);
        try testing.expectEqual(@as(u64, 12), post.chunk_id);
        try testing.expectEqual(expected_seq, post.chunk_seq);
        try testing.expect(post.body.len <= post_body_limit_bytes);
        total += post.body.len;
        expected_seq += 1;
        try testing.expectEqual(total >= payload.len, post.chunk_last);
    }
    try testing.expectEqual(payload.len, total);
    try testing.expectEqual(@as(u32, 3), expected_seq);
}

test "send plan rejects empty and oversized payloads" {
    try testing.expectError(error.EmptyMessage, SendPlan.init("", 1));
    const huge = try testing.allocator.alloc(u8, max_message_bytes + 1);
    defer testing.allocator.free(huge);
    try testing.expectError(error.MessageTooLarge, SendPlan.init(huge, 1));
}

// -------------------------------------------------------------- session

test "session lifecycle initialize -> initialized -> shutdown -> exit" {
    var session: Session = .{};
    try testing.expectEqual(SessionPhase.idle, session.phase);
    try testing.expect(!session.canSendDocumentEvents());

    const init_id = try session.beginInitialize(1000, 5000);
    try testing.expectEqual(@as(u64, 1), init_id);
    try testing.expectEqual(SessionPhase.initializing, session.phase);
    // Document traffic and further requests are illegal before ready.
    try testing.expectError(error.WrongPhase, session.beginRequest("textDocument/hover", 1001, 100));
    try testing.expectError(error.WrongPhase, session.beginInitialize(1001, 100));

    try session.onInitializeResponse(init_id);
    try testing.expectEqual(SessionPhase.ready, session.phase);
    try testing.expect(session.canSendDocumentEvents());
    try testing.expectEqual(@as(usize, 0), session.pendingCount());

    const hover_id = try session.beginRequest("textDocument/hover", 2000, 1000);
    const completed = try session.completeRequest(hover_id);
    try testing.expectEqualStrings("textDocument/hover", completed.method());

    const shutdown_id = try session.beginShutdown(3000, 5000);
    try testing.expectEqual(SessionPhase.shutting_down, session.phase);
    try testing.expect(!session.canSendDocumentEvents());
    try testing.expectError(error.WrongPhase, session.beginRequest("x", 3001, 1));
    try session.onShutdownResponse(shutdown_id);
    session.onServerExit();
    try testing.expectEqual(SessionPhase.exited, session.phase);
}

test "session rejects out-of-order lifecycle responses" {
    var session: Session = .{};
    try testing.expectError(error.WrongPhase, session.onInitializeResponse(1));
    const init_id = try session.beginInitialize(0, 100);
    try testing.expectError(error.WrongPhase, session.onInitializeResponse(init_id + 7));
    try session.onInitializeResponse(init_id);
    try testing.expectError(error.WrongPhase, session.onShutdownResponse(5));
}

test "session request ids are monotonic and the pending table is bounded" {
    var session: Session = .{};
    const init_id = try session.beginInitialize(0, 100);
    try session.onInitializeResponse(init_id);
    var last: u64 = init_id;
    var count: usize = 0;
    while (count < max_pending_requests) : (count += 1) {
        const id = try session.beginRequest("textDocument/hover", 0, 1000);
        try testing.expect(id > last);
        last = id;
    }
    try testing.expectError(error.TooManyPendingRequests, session.beginRequest("one/more", 0, 1000));
}

test "session completeRequest rejects unknown ids and validates methods" {
    var session: Session = .{};
    const init_id = try session.beginInitialize(0, 100);
    try session.onInitializeResponse(init_id);
    try testing.expectError(error.UnknownRequest, session.completeRequest(999));
    try testing.expectError(error.InvalidMethod, session.beginRequest("", 0, 1));
    const long = [_]u8{'m'} ** (max_method_bytes + 1);
    try testing.expectError(error.InvalidMethod, session.beginRequest(&long, 0, 1));
}

test "session expires overdue requests and fails on lifecycle timeout" {
    var session: Session = .{};
    const init_id = try session.beginInitialize(0, 100);
    try session.onInitializeResponse(init_id);
    const a = try session.beginRequest("a/slow", 1000, 500); // deadline 1500
    _ = try session.beginRequest("b/fast", 1000, 5000); // deadline 6000
    var expired: [4]ExpiredRequest = undefined;
    try testing.expectEqual(@as(usize, 0), session.expireOverdue(1400, &expired));
    try testing.expectEqual(@as(usize, 1), session.expireOverdue(1600, &expired));
    try testing.expectEqual(a, expired[0].id);
    try testing.expectEqualStrings("a/slow", expired[0].method());
    try testing.expectEqual(@as(usize, 1), session.pendingCount());
    try testing.expectEqual(SessionPhase.ready, session.phase);

    // A shutdown that times out fails the session.
    const shutdown_id = try session.beginShutdown(2000, 100);
    _ = shutdown_id;
    _ = session.expireOverdue(10_000, &expired);
    try testing.expectEqual(SessionPhase.failed, session.phase);
    try testing.expectEqual(@as(usize, 0), session.pendingCount());
}

test "session initialize timeout fails the session" {
    var session: Session = .{};
    _ = try session.beginInitialize(0, 100);
    var expired: [1]ExpiredRequest = undefined;
    try testing.expectEqual(@as(usize, 1), session.expireOverdue(200, &expired));
    try testing.expectEqualStrings("initialize", expired[0].method());
    try testing.expectEqual(SessionPhase.failed, session.phase);
}

test "session expiry respects a small out buffer across calls" {
    var session: Session = .{};
    const init_id = try session.beginInitialize(0, 1000);
    try session.onInitializeResponse(init_id);
    _ = try session.beginRequest("a", 0, 10);
    _ = try session.beginRequest("b", 0, 10);
    _ = try session.beginRequest("c", 0, 10);
    var one: [1]ExpiredRequest = undefined;
    try testing.expectEqual(@as(usize, 1), session.expireOverdue(100, &one));
    try testing.expectEqual(@as(usize, 1), session.expireOverdue(100, &one));
    try testing.expectEqual(@as(usize, 1), session.expireOverdue(100, &one));
    try testing.expectEqual(@as(usize, 0), session.expireOverdue(100, &one));
}

// ------------------------------------------------------------- builders

test "buildFileUri percent-encodes and joins root with relative path" {
    var buf: [max_uri_bytes]u8 = undefined;
    const uri = try buildFileUri(&buf, "/home/user/proj", "src/main file.zig");
    try testing.expectEqualStrings("file:///home/user/proj/src/main%20file.zig", uri);
    const trailing = try buildFileUri(&buf, "/ws/", "a.ts");
    try testing.expectEqualStrings("file:///ws/a.ts", trailing);
    const unicode = try buildFileUri(&buf, "/ws", "s\xc3\xa9rie.ts"); // é
    try testing.expectEqualStrings("file:///ws/s%C3%A9rie.ts", unicode);
}

test "buildFileUri rejects traversal absolute and malformed paths" {
    var buf: [max_uri_bytes]u8 = undefined;
    try testing.expectError(error.RootNotAbsolute, buildFileUri(&buf, "relative/root", "a.ts"));
    try testing.expectError(error.RootNotAbsolute, buildFileUri(&buf, "", "a.ts"));
    try testing.expectError(error.InvalidPath, buildFileUri(&buf, "/ws", "/abs.ts"));
    try testing.expectError(error.InvalidPath, buildFileUri(&buf, "/ws", ""));
    try testing.expectError(error.InvalidPath, buildFileUri(&buf, "/ws", "../escape.ts"));
    try testing.expectError(error.InvalidPath, buildFileUri(&buf, "/ws", "a/../b.ts"));
    try testing.expectError(error.InvalidPath, buildFileUri(&buf, "/ws", "./b.ts"));
    try testing.expectError(error.InvalidPath, buildFileUri(&buf, "/ws", "a//b.ts"));
    try testing.expectError(error.InvalidPath, buildFileUri(&buf, "/ws", "a\\b.ts"));
    try testing.expectError(error.InvalidPath, buildFileUri(&buf, "/ws", "a\x00b.ts"));
}

test "buildFileUri enforces the uri ceiling" {
    var buf: [2 * max_uri_bytes]u8 = undefined;
    const long_name = [_]u8{'x'} ** max_uri_bytes;
    try testing.expectError(error.UriTooLong, buildFileUri(&buf, "/ws", &long_name));
    var tiny: [8]u8 = undefined;
    try testing.expectError(error.OutputTooSmall, buildFileUri(&tiny, "/ws", "file.ts"));
}

test "buildInitialize produces valid json with id uri and capabilities" {
    var buf: [1024]u8 = undefined;
    const body = try buildInitialize(&buf, 7, "file:///ws");
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, body, .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    try testing.expectEqual(@as(i64, 7), root.get("id").?.integer);
    try testing.expectEqualStrings("initialize", root.get("method").?.string);
    const params = root.get("params").?.object;
    try testing.expectEqualStrings("file:///ws", params.get("rootUri").?.string);
    try testing.expect(params.get("capabilities").? == .object);
}

test "buildInitialized shutdown and exit are exact" {
    var buf: [256]u8 = undefined;
    try testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}",
        try buildInitialized(&buf),
    );
    try testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"shutdown\",\"params\":null}",
        try buildShutdown(&buf, 9),
    );
    try testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"method\":\"exit\",\"params\":null}",
        try buildExit(&buf),
    );
}

test "buildDidOpen escapes document text and round-trips through a json parser" {
    var buf: [1024]u8 = undefined;
    const text = "const s = \"line1\";\n\tlet done = 1; // \x01 control";
    const body = try buildDidOpen(&buf, "file:///ws/a.ts", "typescript", 1, text);
    try testing.expect(std.mem.indexOfScalar(u8, body, '\n') == null);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, body, .{});
    defer parsed.deinit();
    const doc = parsed.value.object.get("params").?.object.get("textDocument").?.object;
    try testing.expectEqualStrings("file:///ws/a.ts", doc.get("uri").?.string);
    try testing.expectEqualStrings("typescript", doc.get("languageId").?.string);
    try testing.expectEqual(@as(i64, 1), doc.get("version").?.integer);
    try testing.expectEqualStrings(text, doc.get("text").?.string);
}

test "buildDidChange carries full-sync content changes" {
    var buf: [512]u8 = undefined;
    const body = try buildDidChange(&buf, "file:///ws/a.ts", 4, "new \"text\"");
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, body, .{});
    defer parsed.deinit();
    const params = parsed.value.object.get("params").?.object;
    try testing.expectEqual(@as(i64, 4), params.get("textDocument").?.object.get("version").?.integer);
    const changes = params.get("contentChanges").?.array;
    try testing.expectEqual(@as(usize, 1), changes.items.len);
    try testing.expectEqualStrings("new \"text\"", changes.items[0].object.get("text").?.string);
}

test "buildDidSave and buildDidClose reference the uri" {
    var buf: [256]u8 = undefined;
    try testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didSave\",\"params\":{\"textDocument\":{\"uri\":\"file:///ws/a.ts\"}}}",
        try buildDidSave(&buf, "file:///ws/a.ts"),
    );
    try testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didClose\",\"params\":{\"textDocument\":{\"uri\":\"file:///ws/a.ts\"}}}",
        try buildDidClose(&buf, "file:///ws/a.ts"),
    );
}

test "builders are bounded by the output buffer" {
    var tiny: [16]u8 = undefined;
    try testing.expectError(error.OutputTooSmall, buildInitialize(&tiny, 1, "file:///ws"));
    try testing.expectError(error.OutputTooSmall, buildDidOpen(&tiny, "file:///ws/a.ts", "ts", 1, "text"));
    try testing.expectError(error.OutputTooSmall, buildDidChange(&tiny, "file:///ws/a.ts", 1, "text"));
    try testing.expectError(error.OutputTooSmall, buildInitialized(tiny[0..8]));
}

// ----------------------------------------------------------- extraction

test "classify routes responses diagnostics server requests and notifications" {
    const response = try classifyServerMessage("{\"jsonrpc\":\"2.0\",\"id\":42,\"result\":null}", &test_scratch);
    try testing.expectEqual(@as(u64, 42), response.response);
    const diags = try classifyServerMessage("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{}}", &test_scratch);
    try testing.expect(diags == .publish_diagnostics);
    const request = try classifyServerMessage("{\"jsonrpc\":\"2.0\",\"id\":\"cfg-1\",\"method\":\"workspace/configuration\",\"params\":{}}", &test_scratch);
    try testing.expectEqualStrings("cfg-1", request.server_request.string);
    const int_request = try classifyServerMessage("{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"client/registerCapability\"}", &test_scratch);
    try testing.expectEqual(@as(u64, 8), int_request.server_request.integer);
    const note = try classifyServerMessage("{\"jsonrpc\":\"2.0\",\"method\":\"window/logMessage\",\"params\":{}}", &test_scratch);
    try testing.expect(note == .notification);
}

test "classify rejects malformed messages" {
    try testing.expectError(error.MalformedMessage, classifyServerMessage("{}", &test_scratch));
    try testing.expectError(error.MalformedMessage, classifyServerMessage("[]", &test_scratch));
    try testing.expectError(error.MalformedMessage, classifyServerMessage("nope", &test_scratch));
    try testing.expectError(error.MalformedMessage, classifyServerMessage("{\"id\":-5,\"result\":null}", &test_scratch));
    try testing.expectError(error.MalformedMessage, classifyServerMessage("{\"id\":true,\"result\":null}", &test_scratch));
    try testing.expectError(error.MalformedMessage, classifyServerMessage("", &test_scratch));
}

test "extract initialize result reports capability presence and server name" {
    const ok = try extractInitializeResult("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"capabilities\":{\"textDocumentSync\":1},\"serverInfo\":{\"name\":\"typescript-language-server\",\"version\":\"4.4.1\"}}}", &test_scratch);
    try testing.expect(ok.ok);
    try testing.expect(ok.has_capabilities);
    try testing.expectEqualStrings("typescript-language-server", ok.serverName());

    const bare = try extractInitializeResult("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}", &test_scratch);
    try testing.expect(bare.ok);
    try testing.expect(!bare.has_capabilities);
    try testing.expectEqualStrings("", bare.serverName());
}

test "extract initialize result surfaces json-rpc errors" {
    const failed = try extractInitializeResult("{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32603,\"message\":\"tsserver missing\"}}", &test_scratch);
    try testing.expect(!failed.ok);
    try testing.expectEqualStrings("tsserver missing", failed.errorMessage());
    try testing.expectError(error.MalformedMessage, extractInitializeResult("{\"jsonrpc\":\"2.0\",\"id\":1}", &test_scratch));
    try testing.expectError(error.MalformedMessage, extractInitializeResult("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":42}", &test_scratch));
}

test "extract publishDiagnostics yields uri ranges severities and messages" {
    const payload =
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{" ++
        "\"uri\":\"file:///ws/a.ts\",\"diagnostics\":[" ++
        "{\"range\":{\"start\":{\"line\":2,\"character\":4},\"end\":{\"line\":2,\"character\":9}},\"severity\":1,\"message\":\"expected expression\"}," ++
        "{\"range\":{\"start\":{\"line\":5,\"character\":0},\"end\":{\"line\":6,\"character\":1}},\"severity\":2,\"message\":\"unused variable\"}," ++
        "{\"range\":{\"start\":{\"line\":9,\"character\":0},\"end\":{\"line\":9,\"character\":0}},\"message\":\"no severity given\"}" ++
        "]}}";
    var page: DiagnosticsPage = .{};
    try extractPublishDiagnostics(payload, &test_scratch, &page);
    try testing.expectEqualStrings("file:///ws/a.ts", page.uri());
    try testing.expectEqual(@as(usize, 3), page.count);
    const first = page.item(0).?;
    try testing.expectEqual(@as(u32, 2), first.range.start.line);
    try testing.expectEqual(@as(u32, 4), first.range.start.character);
    try testing.expectEqual(@as(u32, 9), first.range.end.character);
    try testing.expectEqual(Severity.@"error", first.severity);
    try testing.expectEqualStrings("expected expression", first.message());
    try testing.expectEqual(Severity.warning, page.item(1).?.severity);
    // Missing severity defaults to error (editor convention).
    try testing.expectEqual(Severity.@"error", page.item(2).?.severity);
    try testing.expectEqual(null, page.item(3));
    try testing.expectEqual(@as(usize, 0), page.dropped);
    try testing.expectEqual(@as(usize, 0), page.skipped_malformed);
}

test "extract publishDiagnostics accepts an empty list (clears diagnostics)" {
    var page: DiagnosticsPage = .{};
    try extractPublishDiagnostics("{\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///ws/a.ts\",\"diagnostics\":[]}}", &test_scratch, &page);
    try testing.expectEqual(@as(usize, 0), page.count);
    try testing.expectEqualStrings("file:///ws/a.ts", page.uri());
}

test "extract publishDiagnostics bounds the list and the messages" {
    const payload_buf = try testing.allocator.alloc(u8, 64 * 1024);
    defer testing.allocator.free(payload_buf);
    var len: usize = 0;
    const head = "{\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///ws/big.ts\",\"diagnostics\":[";
    @memcpy(payload_buf[len..][0..head.len], head);
    len += head.len;
    const total = max_diagnostics + 10;
    const long_message = [_]u8{'m'} ** (max_diagnostic_message_bytes + 50);
    var index: usize = 0;
    while (index < total) : (index += 1) {
        const entry = try std.fmt.bufPrint(
            payload_buf[len..],
            "{s}{{\"range\":{{\"start\":{{\"line\":{d},\"character\":0}},\"end\":{{\"line\":{d},\"character\":1}}}},\"severity\":3,\"message\":\"{s}\"}}",
            .{ if (index == 0) "" else ",", index, index, long_message },
        );
        len += entry.len;
    }
    const tail = "]}}";
    @memcpy(payload_buf[len..][0..tail.len], tail);
    len += tail.len;
    var page: DiagnosticsPage = .{};
    try extractPublishDiagnostics(payload_buf[0..len], &test_scratch, &page);
    try testing.expectEqual(max_diagnostics, page.count);
    try testing.expectEqual(@as(usize, 10), page.dropped);
    const diagnostic = page.item(0).?;
    try testing.expectEqual(max_diagnostic_message_bytes, diagnostic.message().len);
    try testing.expect(diagnostic.message_truncated);
}

test "extract publishDiagnostics skips malformed entries and rejects bad envelopes" {
    const payload =
        "{\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///ws/a.ts\",\"diagnostics\":[" ++
        "42," ++ // not an object
        "{\"message\":\"no range\"}," ++
        "{\"range\":{\"start\":{\"line\":-1,\"character\":0},\"end\":{\"line\":0,\"character\":0}},\"message\":\"negative line\"}," ++
        "{\"range\":{\"start\":{\"line\":5,\"character\":0},\"end\":{\"line\":4,\"character\":0}},\"message\":\"inverted range\"}," ++
        "{\"range\":{\"start\":{\"line\":1,\"character\":1},\"end\":{\"line\":1,\"character\":2}},\"message\":\"good\"}" ++
        "]}}";
    var page: DiagnosticsPage = .{};
    try extractPublishDiagnostics(payload, &test_scratch, &page);
    try testing.expectEqual(@as(usize, 1), page.count);
    try testing.expectEqual(@as(usize, 4), page.skipped_malformed);
    try testing.expectEqualStrings("good", page.item(0).?.message());

    try testing.expectError(error.MalformedMessage, extractPublishDiagnostics("{\"params\":{}}", &test_scratch, &page));
    try testing.expectError(error.MalformedMessage, extractPublishDiagnostics("{\"params\":{\"uri\":\"file:///a\"}}", &test_scratch, &page));
    try testing.expectError(error.MalformedMessage, extractPublishDiagnostics("{\"params\":{\"uri\":\"\",\"diagnostics\":[]}}", &test_scratch, &page));
    try testing.expectError(error.MalformedMessage, extractPublishDiagnostics("not json", &test_scratch, &page));
    var long_uri_buf: [max_uri_bytes + 128]u8 = undefined;
    const long_uri_payload = try std.fmt.bufPrint(&long_uri_buf, "{{\"params\":{{\"uri\":\"{s}\",\"diagnostics\":[]}}}}", .{[_]u8{'u'} ** (max_uri_bytes + 1)});
    try testing.expectError(error.UriTooLong, extractPublishDiagnostics(long_uri_payload, &test_scratch, &page));
}

// ------------------------------------------------------------ transport

fn chunkLine(buf: []u8, id: u64, seq: u32, last: bool, raw: []const u8) []const u8 {
    var b64_buf: [512]u8 = undefined;
    const b64 = std.base64.standard.Encoder.encode(&b64_buf, raw);
    return std.fmt.bufPrint(buf, "{{\"event\":\"message_chunk\",\"id\":{d},\"seq\":{d},\"last\":{},\"data_b64\":\"{s}\"}}", .{ id, seq, last, b64 }) catch unreachable;
}

test "transport handshake then message flow" {
    var reassembly_buf: [1024]u8 = undefined;
    var transport = Transport.init(&reassembly_buf);
    try testing.expectEqual(TransportPhase.awaiting_listening, transport.phase);
    // Messages before the handshake are protocol violations.
    try testing.expectError(error.ProtocolViolation, transport.onLine("{\"event\":\"message\",\"payload\":{\"x\":1}}", &test_scratch));

    const listening = try transport.onLine("{\"event\":\"listening\",\"port\":40001,\"token\":\"fee8c75f408e830831425370bb633345\"}", &test_scratch);
    try testing.expect(listening == .listening);
    try testing.expectEqual(@as(u16, 40001), transport.port);
    try testing.expectEqualStrings("fee8c75f408e830831425370bb633345", transport.authToken());
    // A second listening line is a violation.
    try testing.expectError(error.ProtocolViolation, transport.onLine("{\"event\":\"listening\",\"port\":40002,\"token\":\"fee8c75f408e830831425370bb633345\"}", &test_scratch));

    const message = try transport.onLine("{\"event\":\"message\",\"payload\":{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}}", &test_scratch);
    try testing.expectEqualStrings("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}", message.lsp_message);
}

test "transport reassembles chunked server messages across lines" {
    var reassembly_buf: [1024]u8 = undefined;
    var transport = Transport.init(&reassembly_buf);
    _ = try transport.onLine("{\"event\":\"listening\",\"port\":40001,\"token\":\"fee8c75f408e830831425370bb633345\"}", &test_scratch);
    var line_buf: [1024]u8 = undefined;
    const part1 = try transport.onLine(chunkLine(&line_buf, 5, 0, false, "{\"jsonrpc\":\"2.0\",\"method\":\"big\","), &test_scratch);
    try testing.expect(part1 == .none);
    const part2 = try transport.onLine(chunkLine(&line_buf, 5, 1, true, "\"params\":{\"n\":1}}"), &test_scratch);
    try testing.expectEqualStrings("{\"jsonrpc\":\"2.0\",\"method\":\"big\",\"params\":{\"n\":1}}", part2.lsp_message);

    // A bad chunk stream errors but the transport recovers on seq 0.
    _ = try transport.onLine(chunkLine(&line_buf, 6, 0, false, "abc"), &test_scratch);
    try testing.expectError(error.ChunkOutOfOrder, transport.onLine(chunkLine(&line_buf, 6, 2, true, "xyz"), &test_scratch));
    const recovered = try transport.onLine(chunkLine(&line_buf, 7, 0, true, "{\"ok\":true}"), &test_scratch);
    try testing.expectEqualStrings("{\"ok\":true}", recovered.lsp_message);
}

test "transport surfaces exits errors and refuses sends when not ready" {
    var reassembly_buf: [256]u8 = undefined;
    var transport = Transport.init(&reassembly_buf);
    try testing.expectError(error.NotReady, transport.planSend("{\"x\":1}"));
    _ = try transport.onLine("{\"event\":\"listening\",\"port\":40001,\"token\":\"fee8c75f408e830831425370bb633345\"}", &test_scratch);

    const broker_error = try transport.onLine("{\"event\":\"error\",\"code\":\"oversized_frame\",\"detail\":\"dropped\"}", &test_scratch);
    try testing.expectEqualStrings("oversized_frame", broker_error.broker_error.code);
    try testing.expectEqual(TransportPhase.ready, transport.phase); // errors are non-fatal

    const exit = try transport.onLine("{\"event\":\"server_exit\",\"reason\":\"exited\",\"code\":0}", &test_scratch);
    try testing.expectEqual(@as(i64, 0), exit.server_exit.code);
    try testing.expectEqual(TransportPhase.broker_gone, transport.phase);
    try testing.expectEqual(SessionPhase.exited, transport.session.phase);
    try testing.expectError(error.NotReady, transport.planSend("{\"x\":1}"));
}

test "transport broker_exit marks the session exited" {
    var reassembly_buf: [256]u8 = undefined;
    var transport = Transport.init(&reassembly_buf);
    _ = try transport.onLine("{\"event\":\"listening\",\"port\":40001,\"token\":\"fee8c75f408e830831425370bb633345\"}", &test_scratch);
    const gone = try transport.onLine("{\"event\":\"broker_exit\",\"reason\":\"heartbeat_lapsed\"}", &test_scratch);
    try testing.expect(gone.broker_exit == .heartbeat_lapsed);
    try testing.expectEqual(TransportPhase.broker_gone, transport.phase);
    try testing.expectEqual(SessionPhase.exited, transport.session.phase);
}

test "transport allocates monotonically increasing send chunk ids" {
    var reassembly_buf: [256]u8 = undefined;
    var transport = Transport.init(&reassembly_buf);
    _ = try transport.onLine("{\"event\":\"listening\",\"port\":40001,\"token\":\"fee8c75f408e830831425370bb633345\"}", &test_scratch);

    var small_plan = try transport.planSend("{\"tiny\":true}");
    try testing.expectEqual(PostTarget.message, small_plan.next().?.target);
    try testing.expectEqual(@as(u64, 1), transport.next_send_chunk_id); // unchanged for /message

    const big = try testing.allocator.alloc(u8, post_body_limit_bytes + 1);
    defer testing.allocator.free(big);
    @memset(big, 'z');
    var first = try transport.planSend(big);
    var second = try transport.planSend(big);
    try testing.expectEqual(@as(u64, 1), first.next().?.chunk_id);
    try testing.expectEqual(@as(u64, 2), second.next().?.chunk_id);
}

test "transport end-to-end session walkthrough over the wire shapes" {
    // Full drive: handshake -> initialize -> diagnostics -> shutdown,
    // using only wire-shaped inputs and outputs.
    var reassembly_buf: [4096]u8 = undefined;
    var transport = Transport.init(&reassembly_buf);
    _ = try transport.onLine("{\"event\":\"listening\",\"port\":38617,\"token\":\"fee8c75f408e830831425370bb633345\"}", &test_scratch);

    var out_buf: [2048]u8 = undefined;
    var uri_buf: [max_uri_bytes]u8 = undefined;
    const uri = try buildFileUri(&uri_buf, "/ws/acme", "src/app.ts");

    const init_id = try transport.session.beginInitialize(1_000, 10_000);
    const init_body = try buildInitialize(&out_buf, init_id, "file:///ws/acme");
    var init_plan = try transport.planSend(init_body);
    try testing.expectEqual(PostTarget.message, init_plan.next().?.target);

    // Server replies (as re-framed by the broker).
    var line_buf: [512]u8 = undefined;
    const response_line = try std.fmt.bufPrint(&line_buf, "{{\"event\":\"message\",\"payload\":{{\"jsonrpc\":\"2.0\",\"id\":{d},\"result\":{{\"capabilities\":{{\"textDocumentSync\":1}}}}}}}}", .{init_id});
    const incoming = try transport.onLine(response_line, &test_scratch);
    const kind = try classifyServerMessage(incoming.lsp_message, &test_scratch);
    try testing.expectEqual(init_id, kind.response);
    const outcome = try extractInitializeResult(incoming.lsp_message, &test_scratch);
    try testing.expect(outcome.ok and outcome.has_capabilities);
    try transport.session.onInitializeResponse(kind.response);
    _ = try buildInitialized(&out_buf);

    try testing.expect(transport.session.canSendDocumentEvents());
    _ = try buildDidOpen(&out_buf, uri, "typescript", 1, "const x = 1;");

    const diag_line = "{\"event\":\"message\",\"payload\":{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///ws/acme/src/app.ts\",\"diagnostics\":[{\"range\":{\"start\":{\"line\":0,\"character\":6},\"end\":{\"line\":0,\"character\":7}},\"severity\":1,\"message\":\"x is declared but never read\"}]}}}";
    const diag_incoming = try transport.onLine(diag_line, &test_scratch);
    try testing.expect((try classifyServerMessage(diag_incoming.lsp_message, &test_scratch)) == .publish_diagnostics);
    var page: DiagnosticsPage = .{};
    try extractPublishDiagnostics(diag_incoming.lsp_message, &test_scratch, &page);
    try testing.expectEqual(@as(usize, 1), page.count);
    try testing.expectEqualStrings("file:///ws/acme/src/app.ts", page.uri());

    const shutdown_id = try transport.session.beginShutdown(2_000, 10_000);
    _ = try buildShutdown(&out_buf, shutdown_id);
    const shutdown_line = try std.fmt.bufPrint(&line_buf, "{{\"event\":\"message\",\"payload\":{{\"jsonrpc\":\"2.0\",\"id\":{d},\"result\":null}}}}", .{shutdown_id});
    const shutdown_incoming = try transport.onLine(shutdown_line, &test_scratch);
    try transport.session.onShutdownResponse((try classifyServerMessage(shutdown_incoming.lsp_message, &test_scratch)).response);
    _ = try buildExit(&out_buf);

    const exit_incoming = try transport.onLine("{\"event\":\"server_exit\",\"reason\":\"exited\",\"code\":0}", &test_scratch);
    try testing.expect(exit_incoming.server_exit.reason == .exited);
    try testing.expectEqual(SessionPhase.exited, transport.session.phase);
}
