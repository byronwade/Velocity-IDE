//! Velocity LSP sidecar broker — SPIKE.
//!
//! The Native SDK cannot stream stdin to a child and cannot parse
//! Content-Length framing (see docs/velocity/sdk-capability-report.md).
//! This broker is the ONE governed child the app spawns per language
//! server. It:
//!
//!   * owns the actual language-server child process (spawned into its
//!     own process group so the whole tree can be killed),
//!   * speaks LSP stdio (Content-Length framing) to the server,
//!   * re-frames every server->app message as exactly one JSON object
//!     per line on its OWN stdout (NDJSON; the SDK streams these as
//!     spawn `.lines` events, bounded 256 KiB/line),
//!   * accepts app->server messages via HTTP POST on a localhost-only
//!     ephemeral port; the port + a random auth token are printed as
//!     the first NDJSON line and every POST must echo the token in the
//!     `X-Broker-Token` header,
//!   * reassembles chunked POSTs (the SDK caps fetch payloads at
//!     64 KiB) before forwarding to the server,
//!   * forwards server exit/crash as an NDJSON event, and exits itself
//!     when (a) its stdin closes (the app died) or (b) the server exits.
//!
//! Single file, std only, Zig 0.16. Bounded buffers throughout: LSP
//! messages are hard-rejected beyond 1 MiB (NDJSON error event) and the
//! decoder resyncs on framing corruption.
//!
//! Usage: lsp_broker <server-cmd> [args...]
//!
//! Unit tests live in this file: `zig test lsp_broker.zig`.
//! End-to-end proof: `./spike.sh` (uses fake_lsp.zig).

const std = @import("std");
const posix = std.posix;

// ---------------------------------------------------------------- limits

/// Hard ceiling for one LSP message payload in either direction.
pub const max_payload_bytes: usize = 1024 * 1024;
/// Hard ceiling for one Content-Length header block.
pub const max_header_bytes: usize = 4096;
/// Server->app messages whose sanitized payload fits inline go out as a
/// single `{"event":"message","payload":...}` line. The SDK line ceiling
/// is 256 KiB; leave envelope headroom.
pub const max_inline_payload_bytes: usize = 192 * 1024;
/// Raw bytes per server->app base64 chunk (encodes to 128 KiB + envelope).
pub const chunk_raw_bytes: usize = 96 * 1024;
/// App->broker POST body ceiling (SDK fetch payload cap).
pub const max_post_body_bytes: usize = 64 * 1024;
/// HTTP request head (request line + headers) ceiling.
pub const max_http_head_bytes: usize = 8 * 1024;
pub const token_len: usize = 32; // hex chars

// ------------------------------------------------- Content-Length codec

/// Encode one LSP frame (`Content-Length: N\r\n\r\n<payload>`) into
/// caller-owned storage.
pub fn encodeFrame(output: []u8, payload: []const u8) error{ PayloadTooLarge, OutputTooSmall }![]const u8 {
    if (payload.len > max_payload_bytes) return error.PayloadTooLarge;
    var header: [64]u8 = undefined;
    const prefix = std.fmt.bufPrint(&header, "Content-Length: {d}\r\n\r\n", .{payload.len}) catch
        return error.OutputTooSmall;
    if (output.len < prefix.len + payload.len) return error.OutputTooSmall;
    @memcpy(output[0..prefix.len], prefix);
    @memcpy(output[prefix.len..][0..payload.len], payload);
    return output[0 .. prefix.len + payload.len];
}

/// Incremental, bounded Content-Length decoder.
///
/// Feed arbitrary byte chunks with `feed`, then drain items with `next`
/// until it returns null. A returned `.frame` slice borrows the internal
/// buffer and is valid only until the following `feed`/`next` call.
///
/// Corruption policy:
///   * declared length > `max_payload_bytes` -> one `.oversized` item;
///     the payload is discarded without buffering (skip spans feeds),
///   * malformed/missing headers -> one `.malformed` item; the decoder
///     resyncs to the next plausible `Content-Length` header start.
pub const FrameDecoder = struct {
    buf: []u8,
    len: usize = 0,
    /// Bytes of an oversized payload still to discard without buffering.
    skip_remaining: usize = 0,
    /// Bytes of the last returned frame, consumed lazily on the next call.
    pending_consume: usize = 0,

    pub const recommended_buffer_bytes: usize = max_header_bytes + max_payload_bytes + 64 * 1024;

    pub const Item = union(enum) {
        frame: []const u8,
        oversized: usize,
        malformed,
    };

    pub fn init(buf: []u8) FrameDecoder {
        return .{ .buf = buf };
    }

    pub fn feed(self: *FrameDecoder, input: []const u8) error{BufferOverflow}!void {
        self.commit();
        var rest = input;
        if (self.skip_remaining > 0) {
            const n = @min(self.skip_remaining, rest.len);
            self.skip_remaining -= n;
            rest = rest[n..];
        }
        if (rest.len == 0) return;
        if (self.len + rest.len > self.buf.len) return error.BufferOverflow;
        @memcpy(self.buf[self.len..][0..rest.len], rest);
        self.len += rest.len;
    }

    /// Null means "need more input".
    pub fn next(self: *FrameDecoder) ?Item {
        self.commit();
        const data = self.buf[0..self.len];
        if (data.len == 0) return null;
        const separator = "\r\n\r\n";
        const header_end = std.mem.indexOf(u8, data, separator) orelse {
            if (data.len > max_header_bytes) {
                self.resync();
                return .malformed;
            }
            return null;
        };
        if (header_end > max_header_bytes) {
            self.resync();
            return .malformed;
        }
        const content_length = parseContentLength(data[0..header_end]) catch {
            // Drop the corrupt header block; what follows may be a
            // fresh frame (payload garbage will resync again).
            self.consume(header_end + separator.len);
            return .malformed;
        };
        const payload_start = header_end + separator.len;
        if (content_length > max_payload_bytes) {
            const available = self.len - payload_start;
            const skip_now = @min(available, content_length);
            self.consume(payload_start + skip_now);
            self.skip_remaining = content_length - skip_now;
            return .{ .oversized = content_length };
        }
        if (self.len < payload_start + content_length) return null;
        self.pending_consume = payload_start + content_length;
        return .{ .frame = self.buf[payload_start .. payload_start + content_length] };
    }

    pub fn reset(self: *FrameDecoder) void {
        self.len = 0;
        self.skip_remaining = 0;
        self.pending_consume = 0;
    }

    fn commit(self: *FrameDecoder) void {
        if (self.pending_consume == 0) return;
        const n = self.pending_consume;
        self.pending_consume = 0;
        self.consume(n);
    }

    fn consume(self: *FrameDecoder, n: usize) void {
        std.debug.assert(n <= self.len);
        const rest = self.len - n;
        std.mem.copyForwards(u8, self.buf[0..rest], self.buf[n..self.len]);
        self.len = rest;
    }

    fn resync(self: *FrameDecoder) void {
        // Drop at least one byte, then align to the next plausible
        // header start; keep a partial-match tail so a header split
        // across the resync point is still found.
        const marker = "Content-Length";
        if (self.len <= 1) {
            self.len = 0;
            return;
        }
        if (std.mem.indexOf(u8, self.buf[1..self.len], marker)) |i| {
            self.consume(1 + i);
            return;
        }
        // Keep only a trailing partial match of the marker (a header
        // split across the resync point); drop everything else.
        var keep: usize = @min(self.len - 1, marker.len - 1);
        while (keep > 0) : (keep -= 1) {
            if (std.mem.eql(u8, self.buf[self.len - keep .. self.len], marker[0..keep])) break;
        }
        self.consume(self.len - keep);
    }

    fn parseContentLength(header_block: []const u8) error{ InvalidHeader, MissingContentLength, DuplicateContentLength, InvalidContentLength }!usize {
        var content_length: ?usize = null;
        var lines = std.mem.splitSequence(u8, header_block, "\r\n");
        while (lines.next()) |line| {
            if (line.len == 0) return error.InvalidHeader;
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidHeader;
            const name = std.mem.trim(u8, line[0..colon], " \t");
            const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
            if (std.ascii.eqlIgnoreCase(name, "Content-Length")) {
                if (content_length != null) return error.DuplicateContentLength;
                content_length = std.fmt.parseInt(usize, value, 10) catch return error.InvalidContentLength;
            }
        }
        return content_length orelse error.MissingContentLength;
    }
};

// --------------------------------------------------------- NDJSON helpers

/// JSON-escape `src` into `dest` (for embedding arbitrary bytes in a
/// string value of an NDJSON event). Escapes quote, backslash, and all
/// control characters; the result never contains a raw newline.
pub fn jsonEscape(dest: []u8, src: []const u8) error{OutputTooSmall}![]const u8 {
    var n: usize = 0;
    for (src) |c| {
        const escaped: []const u8 = switch (c) {
            '"' => "\\\"",
            '\\' => "\\\\",
            '\n' => "\\n",
            '\r' => "\\r",
            '\t' => "\\t",
            0x08 => "\\b",
            0x0c => "\\f",
            else => blk: {
                if (c >= 0x20) {
                    if (n >= dest.len) return error.OutputTooSmall;
                    dest[n] = c;
                    n += 1;
                    continue;
                }
                var u: [6]u8 = undefined;
                _ = std.fmt.bufPrint(&u, "\\u{x:0>4}", .{c}) catch unreachable;
                break :blk &u;
            },
        };
        if (n + escaped.len > dest.len) return error.OutputTooSmall;
        @memcpy(dest[n..][0..escaped.len], escaped);
        n += escaped.len;
    }
    return dest[0..n];
}

/// Make a JSON payload safe to embed raw inside one NDJSON line.
///
/// Valid JSON can only contain raw `\n`/`\r` as inter-token whitespace
/// (inside strings they must already be `\n`-escaped), so replacing them
/// with spaces preserves the document. Invalid JSON was garbage anyway.
pub fn sanitizeNewlines(payload: []u8) void {
    for (payload) |*c| {
        if (c.* == '\n' or c.* == '\r') c.* = ' ';
    }
}

// -------------------------------------------------------- chunk assembly

/// Reassembles a message split across several POSTs (`seq` 0..n, the
/// last one flagged). Bounded by the caller-provided buffer; any
/// violation resets the assembler so the app can restart at seq 0.
pub const ChunkAssembler = struct {
    buf: []u8,
    len: usize = 0,
    id: u64 = 0,
    next_seq: u32 = 0,
    active: bool = false,

    pub const Error = error{ ChunkOutOfOrder, ChunkIdMismatch, PayloadTooLarge };

    pub fn init(buf: []u8) ChunkAssembler {
        return .{ .buf = buf };
    }

    /// Returns the completed message (borrowing the internal buffer,
    /// valid until the next `accept`) when `last` is set, else null.
    pub fn accept(self: *ChunkAssembler, id: u64, seq: u32, last: bool, data: []const u8) Error!?[]const u8 {
        if (seq == 0) {
            self.active = true;
            self.id = id;
            self.len = 0;
            self.next_seq = 0;
        } else {
            if (!self.active) {
                return error.ChunkOutOfOrder;
            }
            if (id != self.id) {
                self.reset();
                return error.ChunkIdMismatch;
            }
            if (seq != self.next_seq) {
                self.reset();
                return error.ChunkOutOfOrder;
            }
        }
        if (self.len + data.len > self.buf.len) {
            self.reset();
            return error.PayloadTooLarge;
        }
        @memcpy(self.buf[self.len..][0..data.len], data);
        self.len += data.len;
        self.next_seq = seq +% 1;
        if (last) {
            self.active = false;
            return self.buf[0..self.len];
        }
        return null;
    }

    pub fn reset(self: *ChunkAssembler) void {
        self.active = false;
        self.len = 0;
        self.next_seq = 0;
    }
};

// ------------------------------------------------------- HTTP (minimal)

/// The subset of an HTTP/1.1 request head the broker understands.
/// `head` excludes the terminating `\r\n\r\n`.
pub const HttpRequest = struct {
    method: []const u8,
    target: []const u8,
    content_length: usize,
    token: ?[]const u8 = null,
    chunk_id: ?u64 = null,
    chunk_seq: ?u32 = null,
    chunk_last: bool = false,

    pub const ParseError = error{ MalformedRequest, MalformedHeader };

    pub fn parse(head: []const u8) ParseError!HttpRequest {
        var lines = std.mem.splitSequence(u8, head, "\r\n");
        const request_line = lines.next() orelse return error.MalformedRequest;
        var parts = std.mem.splitScalar(u8, request_line, ' ');
        const method = parts.next() orelse return error.MalformedRequest;
        const target = parts.next() orelse return error.MalformedRequest;
        const version = parts.next() orelse return error.MalformedRequest;
        if (method.len == 0 or target.len == 0 or !std.mem.startsWith(u8, version, "HTTP/1.")) {
            return error.MalformedRequest;
        }
        var request: HttpRequest = .{ .method = method, .target = target, .content_length = 0 };
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.MalformedHeader;
            const name = std.mem.trim(u8, line[0..colon], " \t");
            const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
            if (std.ascii.eqlIgnoreCase(name, "Content-Length")) {
                request.content_length = std.fmt.parseInt(usize, value, 10) catch return error.MalformedHeader;
            } else if (std.ascii.eqlIgnoreCase(name, "X-Broker-Token")) {
                request.token = value;
            } else if (std.ascii.eqlIgnoreCase(name, "X-Chunk-Id")) {
                request.chunk_id = std.fmt.parseInt(u64, value, 10) catch return error.MalformedHeader;
            } else if (std.ascii.eqlIgnoreCase(name, "X-Chunk-Seq")) {
                request.chunk_seq = std.fmt.parseInt(u32, value, 10) catch return error.MalformedHeader;
            } else if (std.ascii.eqlIgnoreCase(name, "X-Chunk-Last")) {
                request.chunk_last = std.mem.eql(u8, value, "1");
            }
        }
        return request;
    }
};

fn constantTimeEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var diff: u8 = 0;
    for (a, b) |x, y| diff |= x ^ y;
    return diff == 0;
}

// ---------------------------------------------------------- raw fd I/O
//
// Zig 0.16 routes all stream I/O through `std.Io`; for the broker's
// dedicated blocking threads plain fd syscalls are simpler and
// sufficient. Linux/POSIX only (matches the spike scope; a Windows
// broker needs its own I/O layer — see README).

pub fn writeAllFd(fd: posix.fd_t, bytes: []const u8) error{WriteFailed}!void {
    var off: usize = 0;
    while (off < bytes.len) {
        const rc = posix.system.write(fd, bytes.ptr + off, bytes.len - off);
        switch (posix.errno(rc)) {
            .SUCCESS => off += @intCast(rc),
            .INTR, .AGAIN => continue,
            else => return error.WriteFailed,
        }
    }
}

fn readFd(fd: posix.fd_t, buf: []u8) usize {
    while (true) {
        const rc = posix.system.read(fd, buf.ptr, buf.len);
        switch (posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            else => return 0, // treat as EOF; callers only care about liveness
        }
    }
}

// -------------------------------------------------------------- runtime

const Runtime = struct {
    io: std.Io,
    gpa: std.mem.Allocator,

    token: [token_len]u8 = undefined,

    child: std.process.Child = undefined,
    child_pid: posix.pid_t = 0,
    child_stdin_fd: posix.fd_t = -1,
    child_stdout_fd: posix.fd_t = -1,
    stdin_mutex: std.Io.Mutex = .init,

    stdout_mutex: std.Io.Mutex = .init,

    server: std.Io.net.Server = undefined,

    // Pre-allocated bounded buffers.
    decode_buf: []u8, // child stdout -> FrameDecoder
    read_buf: []u8, // child stdout read chunks
    line_buf: []u8, // NDJSON line assembly (pump thread)
    b64_buf: []u8, // base64 chunk staging (pump thread)
    http_buf: []u8, // one HTTP request (http thread)
    assemble_buf: []u8, // POST chunk reassembly (http thread)
    frame_buf: []u8, // outgoing Content-Length frame (http thread)

    next_out_chunk_id: u64 = 1,

    fn emitLine(self: *Runtime, line: []const u8) void {
        self.stdout_mutex.lockUncancelable(self.io);
        defer self.stdout_mutex.unlock(self.io);
        writeAllFd(posix.STDOUT_FILENO, line) catch {};
        writeAllFd(posix.STDOUT_FILENO, "\n") catch {};
    }

    fn emitError(self: *Runtime, code: []const u8, detail: []const u8) void {
        var detail_buf: [512]u8 = undefined;
        const escaped = jsonEscape(&detail_buf, detail) catch detail_buf[0..0];
        var line_buf: [768]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf, "{{\"event\":\"error\",\"code\":\"{s}\",\"detail\":\"{s}\"}}", .{ code, escaped }) catch return;
        self.emitLine(line);
    }

    /// Forward one complete app->server message to the server's stdin.
    fn forwardToServer(self: *Runtime, payload: []const u8) error{ PayloadTooLarge, WriteFailed }!void {
        if (payload.len > max_payload_bytes) return error.PayloadTooLarge;
        self.stdin_mutex.lockUncancelable(self.io);
        defer self.stdin_mutex.unlock(self.io);
        const frame = encodeFrame(self.frame_buf, payload) catch return error.PayloadTooLarge;
        try writeAllFd(self.child_stdin_fd, frame);
    }

    /// Re-frame one server->app message as NDJSON on our stdout.
    /// `payload` is mutable: raw newlines are sanitized in place.
    fn emitServerMessage(self: *Runtime, payload: []u8) void {
        sanitizeNewlines(payload);
        if (payload.len <= max_inline_payload_bytes) {
            const line = std.fmt.bufPrint(self.line_buf, "{{\"event\":\"message\",\"payload\":{s}}}", .{payload}) catch {
                self.emitError("emit_failed", "inline line buffer overflow");
                return;
            };
            self.emitLine(line);
            return;
        }
        // Oversized for one line: base64 chunks, app reassembles.
        const id = self.next_out_chunk_id;
        self.next_out_chunk_id += 1;
        var seq: u32 = 0;
        var off: usize = 0;
        while (off < payload.len) : (seq += 1) {
            const take = @min(chunk_raw_bytes, payload.len - off);
            const raw = payload[off .. off + take];
            off += take;
            const b64 = std.base64.standard.Encoder.encode(self.b64_buf, raw);
            const last = off >= payload.len;
            const line = std.fmt.bufPrint(
                self.line_buf,
                "{{\"event\":\"message_chunk\",\"id\":{d},\"seq\":{d},\"last\":{},\"data_b64\":\"{s}\"}}",
                .{ id, seq, last, b64 },
            ) catch {
                self.emitError("emit_failed", "chunk line buffer overflow");
                return;
            };
            self.emitLine(line);
        }
    }
};

fn ignoreSigpipe() void {
    posix.sigaction(.PIPE, &.{
        .handler = .{ .handler = posix.SIG.IGN },
        .mask = posix.sigemptyset(),
        .flags = 0,
    }, null);
}

fn boundPort(server: *const std.Io.net.Server) !u16 {
    var sa: posix.sockaddr.in = undefined;
    var sa_len: posix.socklen_t = @sizeOf(posix.sockaddr.in);
    const rc = posix.system.getsockname(server.socket.handle, @ptrCast(&sa), &sa_len);
    if (posix.errno(rc) != .SUCCESS) return error.GetSockNameFailed;
    return std.mem.bigToNative(u16, sa.port);
}

/// Watches the broker's own stdin: EOF means the app died. Kill the
/// server's process group and exit.
fn stdinWatchMain(rt: *Runtime) void {
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = readFd(posix.STDIN_FILENO, &buf);
        if (n == 0) break;
        // Broker stdin carries no protocol; input is ignored.
    }
    killServerTree(rt);
    std.process.exit(0);
}

fn killServerTree(rt: *Runtime) void {
    if (rt.child_pid > 0) {
        // The server was spawned with pgid=0 (its own group): negative
        // pid signals the whole tree.
        posix.kill(-rt.child_pid, .TERM) catch {};
    }
}

// ---------------------------------------------------------- HTTP serving

fn respond(io: std.Io, stream: std.Io.net.Stream, status: []const u8, body: []const u8) void {
    _ = io;
    var buf: [512]u8 = undefined;
    const head = std.fmt.bufPrint(&buf, "HTTP/1.1 {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ status, body.len }) catch return;
    writeAllFd(stream.socket.handle, head) catch return;
    writeAllFd(stream.socket.handle, body) catch return;
}

fn httpServeMain(rt: *Runtime) void {
    var assembler = ChunkAssembler.init(rt.assemble_buf);
    while (true) {
        var stream = rt.server.accept(rt.io) catch |err| switch (err) {
            error.ConnectionAborted, error.WouldBlock => continue,
            else => return,
        };
        handleConnection(rt, &assembler, stream);
        stream.close(rt.io);
    }
}

fn handleConnection(rt: *Runtime, assembler: *ChunkAssembler, stream: std.Io.net.Stream) void {
    const fd = stream.socket.handle;
    const buf = rt.http_buf;
    var len: usize = 0;
    // Read until end of head.
    const head_end = while (true) {
        if (std.mem.indexOf(u8, buf[0..len], "\r\n\r\n")) |i| break i;
        if (len >= max_http_head_bytes) {
            respond(rt.io, stream, "431 Request Header Fields Too Large", "{\"error\":\"head too large\"}");
            return;
        }
        const n = readFd(fd, buf[len..@min(buf.len, max_http_head_bytes + 1)]);
        if (n == 0) return; // peer went away
        len += n;
    };
    const request = HttpRequest.parse(buf[0..head_end]) catch {
        respond(rt.io, stream, "400 Bad Request", "{\"error\":\"malformed request\"}");
        return;
    };
    if (!std.mem.eql(u8, request.method, "POST")) {
        respond(rt.io, stream, "405 Method Not Allowed", "{\"error\":\"POST only\"}");
        return;
    }
    const token = request.token orelse {
        respond(rt.io, stream, "401 Unauthorized", "{\"error\":\"missing X-Broker-Token\"}");
        return;
    };
    if (!constantTimeEql(token, &rt.token)) {
        respond(rt.io, stream, "401 Unauthorized", "{\"error\":\"bad token\"}");
        return;
    }
    if (request.content_length > max_post_body_bytes) {
        respond(rt.io, stream, "413 Payload Too Large", "{\"error\":\"body exceeds 64 KiB; use /chunk\"}");
        return;
    }
    // Read the body (part may already be buffered past the head).
    const body_start = head_end + 4;
    const body_total = body_start + request.content_length;
    if (body_total > buf.len) {
        respond(rt.io, stream, "413 Payload Too Large", "{\"error\":\"request too large\"}");
        return;
    }
    while (len < body_total) {
        const n = readFd(fd, buf[len..body_total]);
        if (n == 0) return;
        len += n;
    }
    const body = buf[body_start..body_total];

    if (std.mem.eql(u8, request.target, "/message")) {
        rt.forwardToServer(body) catch |err| {
            failForward(rt, stream, err);
            return;
        };
        respond(rt.io, stream, "204 No Content", "");
    } else if (std.mem.eql(u8, request.target, "/chunk")) {
        const chunk_id = request.chunk_id orelse {
            respond(rt.io, stream, "400 Bad Request", "{\"error\":\"missing X-Chunk-Id\"}");
            return;
        };
        const chunk_seq = request.chunk_seq orelse {
            respond(rt.io, stream, "400 Bad Request", "{\"error\":\"missing X-Chunk-Seq\"}");
            return;
        };
        const complete = assembler.accept(chunk_id, chunk_seq, request.chunk_last, body) catch |err| {
            const message = switch (err) {
                error.ChunkOutOfOrder => "{\"error\":\"chunk out of order\"}",
                error.ChunkIdMismatch => "{\"error\":\"chunk id mismatch\"}",
                error.PayloadTooLarge => "{\"error\":\"assembled message exceeds 1 MiB\"}",
            };
            const status = if (err == error.PayloadTooLarge) "413 Payload Too Large" else "409 Conflict";
            respond(rt.io, stream, status, message);
            return;
        };
        if (complete) |message| {
            rt.forwardToServer(message) catch |err| {
                failForward(rt, stream, err);
                return;
            };
        }
        respond(rt.io, stream, "204 No Content", "");
    } else {
        respond(rt.io, stream, "404 Not Found", "{\"error\":\"unknown path\"}");
    }
}

fn failForward(rt: *Runtime, stream: std.Io.net.Stream, err: anytype) void {
    switch (err) {
        error.PayloadTooLarge => respond(rt.io, stream, "413 Payload Too Large", "{\"error\":\"message exceeds 1 MiB\"}"),
        error.WriteFailed => {
            rt.emitError("server_stdin_failed", "write to language server stdin failed");
            respond(rt.io, stream, "502 Bad Gateway", "{\"error\":\"server stdin closed\"}");
        },
    }
}

// ----------------------------------------------------------------- main

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const gpa = init.gpa;

    // Collect the server argv (everything after our own argv[0]).
    var argv_storage: [16][]const u8 = undefined;
    var argv_len: usize = 0;
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next(); // argv[0]
    while (args.next()) |arg| {
        if (argv_len >= argv_storage.len) {
            std.log.err("too many server arguments (max {d})", .{argv_storage.len});
            return 2;
        }
        argv_storage[argv_len] = arg;
        argv_len += 1;
    }
    if (argv_len == 0) {
        std.log.err("usage: lsp_broker <server-cmd> [args...]", .{});
        return 2;
    }

    ignoreSigpipe();

    const rt = try gpa.create(Runtime);
    rt.* = .{
        .io = io,
        .gpa = gpa,
        .decode_buf = try gpa.alloc(u8, FrameDecoder.recommended_buffer_bytes),
        .read_buf = try gpa.alloc(u8, 64 * 1024),
        .line_buf = try gpa.alloc(u8, 256 * 1024),
        .b64_buf = try gpa.alloc(u8, std.base64.standard.Encoder.calcSize(chunk_raw_bytes)),
        .http_buf = try gpa.alloc(u8, max_http_head_bytes + max_post_body_bytes + 4),
        .assemble_buf = try gpa.alloc(u8, max_payload_bytes),
        .frame_buf = try gpa.alloc(u8, max_payload_bytes + 64),
    };

    // Random per-run auth token.
    var token_bytes: [token_len / 2]u8 = undefined;
    try io.randomSecure(&token_bytes);
    rt.token = std.fmt.bytesToHex(token_bytes, .lower);

    // Localhost-only ephemeral listener.
    const address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    rt.server = try address.listen(io, .{});
    const port = try boundPort(&rt.server);

    // The language server: our one child, in its own process group.
    rt.child = std.process.spawn(io, .{
        .argv = argv_storage[0..argv_len],
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .ignore,
        .pgid = 0,
    }) catch |err| {
        var msg_buf: [256]u8 = undefined;
        const detail = std.fmt.bufPrint(&msg_buf, "spawn failed: {t}", .{err}) catch "spawn failed";
        rt.emitError("spawn_failed", detail);
        return 1;
    };
    rt.child_pid = switch (@TypeOf(rt.child.id.?)) {
        posix.pid_t => rt.child.id.?,
        else => 0,
    };
    rt.child_stdin_fd = rt.child.stdin.?.handle;
    rt.child_stdout_fd = rt.child.stdout.?.handle;

    // First NDJSON line: where to POST and the token to echo.
    {
        var line_buf: [128]u8 = undefined;
        const line = try std.fmt.bufPrint(&line_buf, "{{\"event\":\"listening\",\"port\":{d},\"token\":\"{s}\"}}", .{ port, rt.token });
        rt.emitLine(line);
    }

    var stdin_thread = try std.Thread.spawn(.{}, stdinWatchMain, .{rt});
    stdin_thread.detach();
    var http_thread = try std.Thread.spawn(.{}, httpServeMain, .{rt});
    http_thread.detach();

    // Main loop: pump server stdout frames into NDJSON events.
    var decoder = FrameDecoder.init(rt.decode_buf);
    while (true) {
        const n = readFd(rt.child_stdout_fd, rt.read_buf);
        if (n == 0) break; // server exited or closed stdout
        decoder.feed(rt.read_buf[0..n]) catch {
            rt.emitError("decode_overflow", "decoder buffer overflow; resetting stream state");
            decoder.reset();
            continue;
        };
        while (decoder.next()) |item| switch (item) {
            .frame => |payload| rt.emitServerMessage(@constCast(payload)),
            .oversized => |declared| {
                var msg_buf: [96]u8 = undefined;
                const detail = std.fmt.bufPrint(&msg_buf, "declared Content-Length {d} exceeds 1 MiB; dropped", .{declared}) catch "oversized frame dropped";
                rt.emitError("oversized_frame", detail);
            },
            .malformed => rt.emitError("malformed_frame", "framing corruption; resynced to next header"),
        };
    }

    const term = rt.child.wait(io) catch {
        rt.emitLine("{\"event\":\"server_exit\",\"reason\":\"unknown\",\"code\":-1}");
        return 1;
    };
    {
        var line_buf: [96]u8 = undefined;
        const line = switch (term) {
            .exited => |code| std.fmt.bufPrint(&line_buf, "{{\"event\":\"server_exit\",\"reason\":\"exited\",\"code\":{d}}}", .{code}),
            .signal => |sig| std.fmt.bufPrint(&line_buf, "{{\"event\":\"server_exit\",\"reason\":\"signal\",\"code\":{d}}}", .{@intFromEnum(sig)}),
            else => std.fmt.bufPrint(&line_buf, "{{\"event\":\"server_exit\",\"reason\":\"unknown\",\"code\":-1}}", .{}),
        } catch return 1;
        rt.emitLine(line);
    }
    return 0;
}

// ================================================================ tests

const testing = std.testing;

test "encodeFrame produces exact Content-Length framing" {
    var storage: [128]u8 = undefined;
    const frame = try encodeFrame(&storage, "{\"id\":1}");
    try testing.expectEqualStrings("Content-Length: 8\r\n\r\n{\"id\":1}", frame);
}

test "encodeFrame rejects oversized payload and tiny output" {
    var tiny: [4]u8 = undefined;
    try testing.expectError(error.OutputTooSmall, encodeFrame(&tiny, "{}"));
    const huge_len = max_payload_bytes + 1;
    const huge = try testing.allocator.alloc(u8, huge_len);
    defer testing.allocator.free(huge);
    @memset(huge, 'x');
    var storage: [64]u8 = undefined;
    try testing.expectError(error.PayloadTooLarge, encodeFrame(&storage, huge));
}

test "decoder decodes one frame and preserves the following frame" {
    var buf: [1024]u8 = undefined;
    var decoder = FrameDecoder.init(&buf);
    try decoder.feed("Content-Length: 2\r\n\r\n{}Content-Length: 4\r\n\r\ntrue");
    try testing.expectEqualStrings("{}", decoder.next().?.frame);
    try testing.expectEqualStrings("true", decoder.next().?.frame);
    try testing.expectEqual(null, decoder.next());
}

test "decoder handles frames split across arbitrary read boundaries" {
    var buf: [1024]u8 = undefined;
    var decoder = FrameDecoder.init(&buf);
    // Split inside the header name, inside the separator, and inside the payload.
    try decoder.feed("Content-Le");
    try testing.expectEqual(null, decoder.next());
    try decoder.feed("ngth: 10\r\n");
    try testing.expectEqual(null, decoder.next());
    try decoder.feed("\r\n{\"a\"");
    try testing.expectEqual(null, decoder.next());
    try decoder.feed(":true}");
    try testing.expectEqualStrings("{\"a\":true}", decoder.next().?.frame[0..10]);
}

test "decoder accepts extra headers and case-insensitive name" {
    var buf: [1024]u8 = undefined;
    var decoder = FrameDecoder.init(&buf);
    try decoder.feed("content-length: 2\r\nContent-Type: application/vscode-jsonrpc; charset=utf-8\r\n\r\n[]");
    try testing.expectEqualStrings("[]", decoder.next().?.frame);
}

test "decoder rejects oversized declared length and skips payload across feeds" {
    var buf: [1024]u8 = undefined;
    var decoder = FrameDecoder.init(&buf);
    var header_buf: [64]u8 = undefined;
    const declared = max_payload_bytes + 5;
    const header = try std.fmt.bufPrint(&header_buf, "Content-Length: {d}\r\n\r\n", .{declared});
    try decoder.feed(header);
    const item = decoder.next().?;
    try testing.expectEqual(declared, item.oversized);
    // Feed the giant payload in pieces; none of it may be buffered.
    var remaining: usize = declared;
    var junk: [4096]u8 = undefined;
    @memset(&junk, 'x');
    while (remaining > 0) {
        const n = @min(remaining, junk.len);
        try decoder.feed(junk[0..n]);
        remaining -= n;
        try testing.expectEqual(@as(usize, 0), decoder.len);
    }
    // The stream recovers on the next well-formed frame.
    try decoder.feed("Content-Length: 2\r\n\r\nok");
    try testing.expectEqualStrings("ok", decoder.next().?.frame);
}

test "decoder reports malformed header line and recovers" {
    var buf: [1024]u8 = undefined;
    var decoder = FrameDecoder.init(&buf);
    try decoder.feed("Garbage-Without-Colon\r\n\r\nContent-Length: 2\r\n\r\nhi");
    try testing.expectEqual(FrameDecoder.Item.malformed, decoder.next().?);
    try testing.expectEqualStrings("hi", decoder.next().?.frame);
}

test "decoder reports missing and duplicate Content-Length" {
    var buf: [1024]u8 = undefined;
    var decoder = FrameDecoder.init(&buf);
    try decoder.feed("Content-Type: application/json\r\n\r\n");
    try testing.expectEqual(FrameDecoder.Item.malformed, decoder.next().?);
    try decoder.feed("Content-Length: 2\r\nContent-Length: 2\r\n\r\n");
    try testing.expectEqual(FrameDecoder.Item.malformed, decoder.next().?);
}

test "decoder resyncs when no header separator arrives within the bound" {
    var buf: [FrameDecoder.recommended_buffer_bytes]u8 = undefined;
    var decoder = FrameDecoder.init(&buf);
    // A long run of garbage with no \r\n\r\n at all.
    var junk: [max_header_bytes + 512]u8 = undefined;
    @memset(&junk, 'z');
    try decoder.feed(&junk);
    try testing.expectEqual(FrameDecoder.Item.malformed, decoder.next().?);
    // A valid frame after the noise still gets through.
    try decoder.feed("Content-Length: 5\r\n\r\nhello");
    var saw_frame = false;
    while (decoder.next()) |item| {
        switch (item) {
            .frame => |payload| {
                try testing.expectEqualStrings("hello", payload);
                saw_frame = true;
            },
            else => {},
        }
    }
    try testing.expect(saw_frame);
}

test "jsonEscape escapes embedded newlines, quotes, and control bytes" {
    var buf: [128]u8 = undefined;
    const escaped = try jsonEscape(&buf, "a\nb\r\"c\"\\d\x01");
    try testing.expectEqualStrings("a\\nb\\r\\\"c\\\"\\\\d\\u0001", escaped);
    try testing.expect(std.mem.indexOfScalar(u8, escaped, '\n') == null);
}

test "jsonEscape is bounded" {
    var tiny: [3]u8 = undefined;
    try testing.expectError(error.OutputTooSmall, jsonEscape(&tiny, "\n\n\n"));
}

test "sanitizeNewlines flattens pretty-printed JSON to one NDJSON-safe line" {
    var payload = "{\r\n  \"a\": \"x\\ny\"\r\n}".*;
    sanitizeNewlines(&payload);
    try testing.expectEqualStrings("{    \"a\": \"x\\ny\"  }", &payload);
    // The escaped \n inside the string survives; no raw newline remains.
    try testing.expect(std.mem.indexOfScalar(u8, &payload, '\n') == null);
}

test "chunk assembler reassembles in-order chunks" {
    var buf: [64]u8 = undefined;
    var assembler = ChunkAssembler.init(&buf);
    try testing.expectEqual(null, try assembler.accept(7, 0, false, "{\"big\""));
    try testing.expectEqual(null, try assembler.accept(7, 1, false, ":\"mess"));
    const complete = (try assembler.accept(7, 2, true, "age\"}")).?;
    try testing.expectEqualStrings("{\"big\":\"message\"}", complete);
}

test "chunk assembler rejects out-of-order, mismatched, and unopened sequences" {
    var buf: [64]u8 = undefined;
    var assembler = ChunkAssembler.init(&buf);
    try testing.expectError(error.ChunkOutOfOrder, assembler.accept(1, 1, false, "x"));
    _ = try assembler.accept(1, 0, false, "a");
    try testing.expectError(error.ChunkIdMismatch, assembler.accept(2, 1, false, "b"));
    // The failure reset state; a fresh seq-0 start works.
    _ = try assembler.accept(3, 0, false, "a");
    try testing.expectError(error.ChunkOutOfOrder, assembler.accept(3, 2, true, "c"));
    const complete = (try assembler.accept(4, 0, true, "solo")).?;
    try testing.expectEqualStrings("solo", complete);
}

test "chunk assembler bounds the assembled message" {
    var buf: [8]u8 = undefined;
    var assembler = ChunkAssembler.init(&buf);
    _ = try assembler.accept(1, 0, false, "12345678");
    try testing.expectError(error.PayloadTooLarge, assembler.accept(1, 1, true, "9"));
}

test "http request parse extracts token and chunk headers" {
    const head = "POST /chunk HTTP/1.1\r\nHost: 127.0.0.1:9\r\nx-broker-token: abc\r\nContent-Length: 12\r\nX-Chunk-Id: 42\r\nX-Chunk-Seq: 3\r\nX-Chunk-Last: 1";
    const request = try HttpRequest.parse(head);
    try testing.expectEqualStrings("POST", request.method);
    try testing.expectEqualStrings("/chunk", request.target);
    try testing.expectEqual(@as(usize, 12), request.content_length);
    try testing.expectEqualStrings("abc", request.token.?);
    try testing.expectEqual(@as(u64, 42), request.chunk_id.?);
    try testing.expectEqual(@as(u32, 3), request.chunk_seq.?);
    try testing.expect(request.chunk_last);
}

test "http request parse rejects garbage" {
    try testing.expectError(error.MalformedRequest, HttpRequest.parse("NOT_HTTP"));
    try testing.expectError(error.MalformedHeader, HttpRequest.parse("POST / HTTP/1.1\r\nBadHeaderNoColon"));
}

test "token comparison is length-guarded" {
    try testing.expect(constantTimeEql("abcd", "abcd"));
    try testing.expect(!constantTimeEql("abcd", "abce"));
    try testing.expect(!constantTimeEql("abc", "abcd"));
}
