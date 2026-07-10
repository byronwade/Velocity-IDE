//! Velocity PTY sidecar broker.
//!
//! The Native SDK has no PTY API, cannot stream stdin to a child, and
//! only delivers child stdout as bounded NDJSON lines (see
//! docs/velocity/sdk-capability-report.md). This broker is the ONE
//! governed child the app spawns per interactive terminal. It:
//!
//!   * opens a REAL pseudo-terminal (Linux: /dev/ptmx + TIOCSPTLCK/
//!     TIOCGPTN — the manual openpty(3) sequence, no libc dependency),
//!   * forks the shell into its own session with the PTY slave as its
//!     controlling terminal (login-style `-$SHELL` argv0 by default, or
//!     an explicit argv after `--`; cwd via `--cwd=`, environment
//!     passed through with TERM overridden via `--term=`),
//!   * relays PTY master output as NDJSON `{"event":"data","b64":...}`
//!     lines (raw terminal bytes are not newline-safe, so they travel
//!     base64-encoded in bounded chunks of <= 48 KiB raw per line),
//!   * accepts input as token-authed localhost POST /input
//!     (`{"b64":...}` -> write to the master) and POST /resize
//!     (`{"cols":N,"rows":M}` -> TIOCSWINSZ, kernel delivers SIGWINCH),
//!   * reports shell death as `{"event":"pty_exit","reason":...,
//!     "code":N}` and reuses the LSP broker's liveness + teardown
//!     semantics verbatim: `--liveness=stdin|http`, `POST /hb`,
//!     `POST /shutdown`, TERM -> grace -> KILL on the shell's process
//!     group, PDEATHSIG backstop.
//!
//! Shared plumbing (HTTP request parsing, token compare, raw-fd I/O,
//! kill escalation, death backstop, clock) is imported from
//! `lsp_broker.zig` rather than duplicated. This is a separate binary
//! (not `--mode=pty` in the LSP one) because the child-acquisition
//! path is fundamentally different — openpty + fork + setsid +
//! TIOCSCTTY + execve instead of `std.process.spawn` with pipes — and
//! keeping the proven LSP binary byte-stable matters more than sharing
//! an argv0.
//!
//! Platform gates: Linux proven (pty-spike.sh). macOS is expected to
//! be openpty-compatible but is UNTESTED (same ptmx concept, different
//! ioctls — see README). Windows is BLOCKED pending a ConPTY adapter.
//!
//! Usage: pty_broker [--liveness=stdin|http] [--hb-window-ms=N]
//!                   [--grace-ms=N] [--cwd=DIR] [--term=NAME]
//!                   [--cols=N] [--rows=N] [--] [shell-cmd args...]
//!
//! Unit tests live in this file: `zig test pty_broker.zig` (also runs
//! the imported lsp_broker.zig suite). End-to-end: `./pty-spike.sh`.

const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const broker = @import("lsp_broker.zig");

// ---------------------------------------------------------------- limits

/// Raw PTY bytes per outbound NDJSON `data` event, pre-base64. 48 KiB
/// raw -> 64 KiB base64 + envelope, comfortably under the SDK's
/// 256 KiB line ceiling while keeping per-event latency low.
pub const data_chunk_raw_bytes: usize = 48 * 1024;
/// App->broker POST body ceiling (SDK fetch payload cap).
pub const max_post_body_bytes: usize = broker.max_post_body_bytes;
/// Decoded /input bytes per POST (base64 of this fits in a POST body).
pub const max_input_raw_bytes: usize = 48 * 1024;
/// Terminal geometry sanity bounds (matches src/terminal limits).
pub const max_columns: u16 = 1000;
pub const max_rows: u16 = 1000;
/// Shell argv ceiling after broker flags.
pub const max_shell_args: usize = 16;
/// Combined flag + shell argv ceiling on the command line.
pub const max_cli_args: usize = 24;
/// Longest accepted --cwd/--term values and argv strings.
pub const max_flag_value_bytes: usize = 1024;
/// Scratch for parsing one POST JSON body.
pub const body_scratch_bytes: usize = 192 * 1024;

// ------------------------------------------------------------- options

pub const PtyOptions = struct {
    liveness: broker.LivenessMode = .stdin,
    hb_window_ms: u64 = broker.default_hb_window_ms,
    grace_ms: u64 = broker.default_grace_ms,
    cwd: ?[]const u8 = null,
    term: []const u8 = "xterm-256color",
    cols: u16 = 80,
    rows: u16 = 24,

    pub const ParseError = error{
        UnknownFlag,
        InvalidFlagValue,
        TooManyShellArgs,
    };

    pub const Parsed = struct {
        options: PtyOptions,
        /// Index into `args` where the shell argv starts; == args.len
        /// means "no explicit shell — use login-style $SHELL".
        shell_argv_start: usize,
    };

    /// Parse broker flags from `args` (argv[0] already stripped).
    /// Flags come first; the first non-flag argument — or everything
    /// after a literal `--` — is the shell command line. Unlike the
    /// LSP broker, the shell argv is OPTIONAL ($SHELL is the default).
    pub fn parse(args: []const []const u8) ParseError!Parsed {
        var options: PtyOptions = .{};
        var index: usize = 0;
        while (index < args.len) : (index += 1) {
            const arg = args[index];
            if (std.mem.eql(u8, arg, "--")) {
                index += 1;
                break;
            }
            if (!std.mem.startsWith(u8, arg, "--")) break;
            if (std.mem.startsWith(u8, arg, "--liveness=")) {
                const value = arg["--liveness=".len..];
                if (std.mem.eql(u8, value, "stdin")) {
                    options.liveness = .stdin;
                } else if (std.mem.eql(u8, value, "http")) {
                    options.liveness = .http;
                } else {
                    return error.InvalidFlagValue;
                }
            } else if (std.mem.startsWith(u8, arg, "--hb-window-ms=")) {
                const value = std.fmt.parseInt(u64, arg["--hb-window-ms=".len..], 10) catch
                    return error.InvalidFlagValue;
                if (value == 0) return error.InvalidFlagValue;
                options.hb_window_ms = value;
            } else if (std.mem.startsWith(u8, arg, "--grace-ms=")) {
                options.grace_ms = std.fmt.parseInt(u64, arg["--grace-ms=".len..], 10) catch
                    return error.InvalidFlagValue;
            } else if (std.mem.startsWith(u8, arg, "--cwd=")) {
                const value = arg["--cwd=".len..];
                if (value.len == 0 or value.len > max_flag_value_bytes or value[0] != '/')
                    return error.InvalidFlagValue;
                options.cwd = value;
            } else if (std.mem.startsWith(u8, arg, "--term=")) {
                const value = arg["--term=".len..];
                if (value.len == 0 or value.len > 64) return error.InvalidFlagValue;
                options.term = value;
            } else if (std.mem.startsWith(u8, arg, "--cols=")) {
                options.cols = parseDim(arg["--cols=".len..]) orelse return error.InvalidFlagValue;
            } else if (std.mem.startsWith(u8, arg, "--rows=")) {
                options.rows = parseDim(arg["--rows=".len..]) orelse return error.InvalidFlagValue;
            } else {
                return error.UnknownFlag;
            }
        }
        if (args.len - index > max_shell_args) return error.TooManyShellArgs;
        return .{ .options = options, .shell_argv_start = index };
    }

    fn parseDim(text: []const u8) ?u16 {
        const value = std.fmt.parseInt(u16, text, 10) catch return null;
        if (value == 0 or value > max_columns) return null;
        return value;
    }
};

// --------------------------------------------------- POST body parsing
//
// Both bodies are tiny JSON objects produced by the app's
// pty_transport.zig builders; std.json over a caller-provided scratch
// keeps parsing bounded and allocation-free after startup.

pub const Winsz = struct { cols: u16, rows: u16 };

pub const ResizeError = error{ Malformed, OutOfRange };

/// Parse a `/resize` body: `{"cols":N,"rows":M}`, both in
/// [1, max_columns/max_rows].
pub fn parseResizeBody(body: []const u8, scratch: []u8) ResizeError!Winsz {
    const root = parseBodyObject(body, scratch) catch return error.Malformed;
    const cols = integerField(root, "cols") orelse return error.Malformed;
    const rows = integerField(root, "rows") orelse return error.Malformed;
    if (cols < 1 or cols > max_columns) return error.OutOfRange;
    if (rows < 1 or rows > max_rows) return error.OutOfRange;
    return .{ .cols = @intCast(cols), .rows = @intCast(rows) };
}

pub const InputError = error{ Malformed, InvalidBase64, InputTooLarge };

/// Parse an `/input` body (`{"b64":"..."}`) and decode the base64
/// payload into `out`. Returns the decoded bytes (borrowing `out`).
pub fn decodeInputBody(body: []const u8, scratch: []u8, out: []u8) InputError![]const u8 {
    const root = parseBodyObject(body, scratch) catch return error.Malformed;
    const b64_value = root.get("b64") orelse return error.Malformed;
    const b64 = switch (b64_value) {
        .string => |s| s,
        else => return error.Malformed,
    };
    const decoder = std.base64.standard.Decoder;
    const raw_len = decoder.calcSizeForSlice(b64) catch return error.InvalidBase64;
    if (raw_len > max_input_raw_bytes or raw_len > out.len) return error.InputTooLarge;
    decoder.decode(out[0..raw_len], b64) catch return error.InvalidBase64;
    return out[0..raw_len];
}

fn parseBodyObject(body: []const u8, scratch: []u8) error{Malformed}!std.json.ObjectMap {
    if (body.len == 0 or body.len > max_post_body_bytes) return error.Malformed;
    var fba = std.heap.FixedBufferAllocator.init(scratch);
    const parsed = std.json.parseFromSlice(std.json.Value, fba.allocator(), body, .{}) catch
        return error.Malformed;
    return switch (parsed.value) {
        .object => |object| object,
        else => error.Malformed,
    };
}

fn integerField(object: std.json.ObjectMap, name: []const u8) ?i64 {
    const value = object.get(name) orelse return null;
    return switch (value) {
        .integer => |i| i,
        else => null,
    };
}

// --------------------------------------------------- outbound data events

/// Base64 storage sized for one full raw chunk.
pub const data_b64_bytes: usize = std.base64.standard.Encoder.calcSize(data_chunk_raw_bytes);
/// One encoded event line: envelope + base64 payload.
pub const data_line_bytes: usize = data_b64_bytes + 64;

pub const EncodeError = error{ ChunkTooLarge, OutputTooSmall };

/// Encode one bounded PTY output chunk as a single NDJSON `data` event
/// line (no trailing newline). `raw.len` must be <= data_chunk_raw_bytes
/// so the line stays far below the SDK's 256 KiB ceiling.
pub fn encodeDataEvent(line_buf: []u8, b64_buf: []u8, raw: []const u8) EncodeError![]const u8 {
    if (raw.len > data_chunk_raw_bytes) return error.ChunkTooLarge;
    if (b64_buf.len < std.base64.standard.Encoder.calcSize(raw.len)) return error.OutputTooSmall;
    const b64 = std.base64.standard.Encoder.encode(b64_buf, raw);
    return std.fmt.bufPrint(line_buf, "{{\"event\":\"data\",\"b64\":\"{s}\"}}", .{b64}) catch
        error.OutputTooSmall;
}

// -------------------------------------------------------------- auth

/// Route-level auth decision shared by every endpoint: null means
/// authorized; otherwise the HTTP status line to refuse with. Uses the
/// LSP broker's length-guarded constant-time compare.
pub fn authStatus(request_token: ?[]const u8, expected: []const u8) ?[]const u8 {
    const token = request_token orelse return "401 Unauthorized";
    if (!broker.constantTimeEql(token, expected)) return "401 Unauthorized";
    return null;
}

// ---------------------------------------------------------- shell argv

/// Login-style argv0 for a shell path: "/bin/bash" -> "-bash".
/// Returns a slice of `buf`.
pub fn loginArgv0(buf: []u8, shell_path: []const u8) error{OutputTooSmall}![]const u8 {
    const base = std.fs.path.basename(shell_path);
    if (base.len == 0) return error.OutputTooSmall;
    if (buf.len < base.len + 1) return error.OutputTooSmall;
    buf[0] = '-';
    @memcpy(buf[1..][0..base.len], base);
    return buf[0 .. base.len + 1];
}

// -------------------------------------------------------- PTY (Linux)
//
// Manual openpty(3): /dev/ptmx gives the master; TIOCSPTLCK unlocks
// the slave and TIOCGPTN names it (/dev/pts/N). devpts handles the
// permissions grantpt(3) would; no libc needed. Gated hard to Linux —
// macOS uses different ioctls (TIOCPTYGRANT/TIOCPTYUNLK) and is
// documented as untested; Windows has no PTY at all (ConPTY adapter
// pending).

const linux = std.os.linux;

pub const PtyPair = struct {
    master_fd: posix.fd_t,
    /// NUL-terminated "/dev/pts/N".
    slave_path: [32:0]u8,
};

pub const OpenPtyError = error{ UnsupportedPlatform, OpenPtmxFailed, UnlockFailed, PtsNameFailed };

pub fn openPty(initial: Winsz) OpenPtyError!PtyPair {
    if (builtin.os.tag != .linux) return error.UnsupportedPlatform;
    const rc = linux.open("/dev/ptmx", .{ .ACCMODE = .RDWR, .NOCTTY = true }, 0);
    if (posix.errno(rc) != .SUCCESS) return error.OpenPtmxFailed;
    const master_fd: posix.fd_t = @intCast(rc);
    errdefer _ = linux.close(master_fd);

    var unlock: c_int = 0;
    if (posix.errno(linux.ioctl(master_fd, linux.T.IOCSPTLCK, @intFromPtr(&unlock))) != .SUCCESS) {
        _ = linux.close(master_fd);
        return error.UnlockFailed;
    }
    var pts_number: c_uint = 0;
    if (posix.errno(linux.ioctl(master_fd, linux.T.IOCGPTN, @intFromPtr(&pts_number))) != .SUCCESS) {
        _ = linux.close(master_fd);
        return error.PtsNameFailed;
    }
    var pair: PtyPair = .{ .master_fd = master_fd, .slave_path = undefined };
    _ = std.fmt.bufPrintZ(&pair.slave_path, "/dev/pts/{d}", .{pts_number}) catch {
        _ = linux.close(master_fd);
        return error.PtsNameFailed;
    };
    applyWinsize(master_fd, initial);
    return pair;
}

pub fn applyWinsize(master_fd: posix.fd_t, size: Winsz) void {
    var ws: posix.winsize = .{ .row = size.rows, .col = size.cols, .xpixel = 0, .ypixel = 0 };
    // Kernel delivers SIGWINCH to the foreground process group itself.
    _ = linux.ioctl(master_fd, linux.T.IOCSWINSZ, @intFromPtr(&ws));
}

// -------------------------------------------------- fork + exec (child)

const max_env_entries: usize = 512;
const max_exec_candidates_path_bytes: usize = 4096;

/// Everything the child needs, prepared BEFORE fork (the child must
/// only touch pre-built memory + raw syscalls).
const ChildPlan = struct {
    slave_path: [*:0]const u8,
    master_fd: posix.fd_t,
    /// Candidate executable path(s): argv[0] resolution already done
    /// (absolute, or PATH-joined candidates tried in order).
    exec_paths: [16]?[*:0]const u8 = [_]?[*:0]const u8{null} ** 16,
    argv: [max_shell_args + 1:null]?[*:0]const u8 =
        [_:null]?[*:0]const u8{null} ** (max_shell_args + 1),
    envp: [max_env_entries + 2:null]?[*:0]const u8 =
        [_:null]?[*:0]const u8{null} ** (max_env_entries + 2),
    cwd: ?[*:0]const u8 = null,
};

/// Runs in the forked child. Raw syscalls only; never returns.
fn childExec(plan: *const ChildPlan) noreturn {
    _ = linux.setsid();
    const open_rc = linux.open(plan.slave_path, .{ .ACCMODE = .RDWR }, 0);
    if (posix.errno(open_rc) != .SUCCESS) linux.exit_group(126);
    const slave_fd: posix.fd_t = @intCast(open_rc);
    // First tty opened after setsid becomes controlling; make it explicit.
    _ = linux.ioctl(slave_fd, linux.T.IOCSCTTY, 0);
    _ = linux.dup2(slave_fd, 0);
    _ = linux.dup2(slave_fd, 1);
    _ = linux.dup2(slave_fd, 2);
    if (slave_fd > 2) _ = linux.close(slave_fd);
    _ = linux.close(plan.master_fd);
    if (plan.cwd) |cwd| _ = linux.chdir(cwd);
    for (plan.exec_paths) |candidate| {
        const path = candidate orelse break;
        _ = linux.execve(path, &plan.argv, &plan.envp);
        // Only reached on failure; try the next PATH candidate.
    }
    linux.exit_group(127);
}

// -------------------------------------------------- session escalation
//
// The LSP broker kills the child's process GROUP, which covers a
// pipe-spawned server tree. A PTY shell is different: interactive
// shells enable job control, so every background pipeline
// (`sleep 300 &`) gets its OWN process group inside the shell's
// SESSION (the shell became a session leader via setsid). Killing the
// leader's group alone would leak those jobs — proven by the spike.
// So the PTY teardown escalates over every pid whose /proc session id
// is the shell's: TERM all -> bounded grace -> KILL all.

/// Parse the session id (4th field after the comm ")" in
/// /proc/<pid>/stat). Zombies return null — they cannot be signalled
/// and must not stall the escalation grace loop. Pure; unit-tested.
pub fn sessionIdFromStat(stat_text: []const u8) ?posix.pid_t {
    // comm may contain spaces/parens; the LAST ')' ends it.
    const close = std.mem.lastIndexOfScalar(u8, stat_text, ')') orelse return null;
    var fields = std.mem.tokenizeScalar(u8, stat_text[close + 1 ..], ' ');
    const state = fields.next() orelse return null;
    if (std.mem.eql(u8, state, "Z")) return null;
    _ = fields.next() orelse return null; // ppid
    _ = fields.next() orelse return null; // pgrp
    const session_text = fields.next() orelse return null;
    return std.fmt.parseInt(posix.pid_t, session_text, 10) catch null;
}

/// Scan /proc for live processes in `session`; deliver `sig` to each
/// when non-null. Returns how many were found. Raw syscalls only.
fn sweepSession(session: posix.pid_t, sig: ?posix.SIG) usize {
    var found: usize = 0;
    const dir_rc = linux.open("/proc", .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (posix.errno(dir_rc) != .SUCCESS) return 0;
    const dir_fd: posix.fd_t = @intCast(dir_rc);
    defer _ = linux.close(dir_fd);
    var ents: [8192]u8 = undefined;
    while (true) {
        const n_rc = linux.getdents64(dir_fd, &ents, ents.len);
        if (posix.errno(n_rc) != .SUCCESS) break;
        const n: usize = @intCast(n_rc);
        if (n == 0) break;
        var off: usize = 0;
        while (off < n) {
            const ent: *align(1) linux.dirent64 = @ptrCast(&ents[off]);
            const reclen: usize = ent.reclen;
            if (reclen == 0) break;
            const name_ptr: [*:0]const u8 = @ptrCast(@as([*]const u8, @ptrCast(ent)) + @offsetOf(linux.dirent64, "name"));
            const name = std.mem.sliceTo(name_ptr, 0);
            off += reclen;
            const pid = std.fmt.parseInt(posix.pid_t, name, 10) catch continue;
            if (statSessionOf(pid) != session) continue;
            found += 1;
            if (sig) |s| _ = linux.kill(pid, s);
        }
    }
    return found;
}

fn statSessionOf(pid: posix.pid_t) ?posix.pid_t {
    var path_buf: [48]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, "/proc/{d}/stat", .{pid}) catch return null;
    const rc = linux.open(path, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (posix.errno(rc) != .SUCCESS) return null;
    const fd: posix.fd_t = @intCast(rc);
    defer _ = linux.close(fd);
    var stat_buf: [512]u8 = undefined;
    const n = broker.readFd(fd, &stat_buf);
    if (n == 0) return null;
    return sessionIdFromStat(stat_buf[0..n]);
}

/// TERM every process in the shell's session -> bounded grace -> KILL
/// the stragglers. Also signals the leader's own group (covers the
/// window before a fork'd job moves to its new group) and reaps the
/// direct child so its stat entry doesn't read as alive.
pub fn escalateKillSession(leader: posix.pid_t, grace_ms: u64) void {
    if (leader <= 0) return;
    _ = linux.kill(-leader, .TERM);
    _ = sweepSession(leader, .TERM);
    const deadline = broker.nowMs() + grace_ms;
    while (broker.nowMs() < deadline) {
        reapDirectChild(leader);
        if (sweepSession(leader, null) == 0) return;
        broker.sleepMs(25);
    }
    _ = linux.kill(-leader, .KILL);
    _ = sweepSession(leader, .KILL);
    broker.sleepMs(20);
    reapDirectChild(leader);
}

fn reapDirectChild(child_pid: posix.pid_t) void {
    var status: u32 = 0;
    _ = linux.waitpid(child_pid, &status, linux.W.NOHANG);
}

// -------------------------------------------------------------- runtime

const Runtime = struct {
    io: std.Io,

    opts: PtyOptions = .{},
    last_hb_ms: std.atomic.Value(u64) = .init(0),
    teardown_started: std.atomic.Value(bool) = .init(false),

    token: [broker.token_len]u8 = undefined,

    child_pid: posix.pid_t = 0,
    master_fd: posix.fd_t = -1,
    master_write_mutex: std.Io.Mutex = .init,
    stdout_mutex: std.Io.Mutex = .init,

    server: std.Io.net.Server = undefined,

    // Pre-allocated bounded buffers.
    read_buf: []u8, // master output read chunks (<= data_chunk_raw_bytes)
    b64_buf: []u8, // base64 staging (pump thread)
    line_buf: []u8, // NDJSON line assembly (pump thread)
    http_buf: []u8, // one HTTP request (http thread)
    body_scratch: []u8, // JSON parse scratch (http thread)
    input_buf: []u8, // decoded /input bytes (http thread)

    fn emitLine(self: *Runtime, line: []const u8) void {
        self.stdout_mutex.lockUncancelable(self.io);
        defer self.stdout_mutex.unlock(self.io);
        broker.writeAllFd(posix.STDOUT_FILENO, line) catch {};
        broker.writeAllFd(posix.STDOUT_FILENO, "\n") catch {};
    }

    fn emitError(self: *Runtime, code: []const u8, detail: []const u8) void {
        var detail_buf: [512]u8 = undefined;
        const escaped = broker.jsonEscape(&detail_buf, detail) catch detail_buf[0..0];
        var line_storage: [768]u8 = undefined;
        const line = std.fmt.bufPrint(&line_storage, "{{\"event\":\"error\",\"code\":\"{s}\",\"detail\":\"{s}\"}}", .{ code, escaped }) catch return;
        self.emitLine(line);
    }
};

/// Common teardown for every broker-initiated exit (stdin EOF,
/// heartbeat lapse, POST /shutdown). Mirrors the LSP broker exactly.
fn exitBroker(rt: *Runtime, reason: []const u8) noreturn {
    if (rt.teardown_started.swap(true, .monotonic)) broker.parkUntilExit();
    var line_storage: [96]u8 = undefined;
    if (std.fmt.bufPrint(&line_storage, "{{\"event\":\"broker_exit\",\"reason\":\"{s}\"}}", .{reason})) |line| {
        rt.emitLine(line);
    } else |_| {}
    escalateKillSession(rt.child_pid, rt.opts.grace_ms);
    std.process.exit(0);
}

fn stdinWatchMain(rt: *Runtime) void {
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = broker.readFd(posix.STDIN_FILENO, &buf);
        if (n == 0) break;
    }
    exitBroker(rt, "stdin_closed");
}

fn heartbeatWatchMain(rt: *Runtime) void {
    const poll_ms = @min(rt.opts.hb_window_ms / 4 + 1, 250);
    while (true) {
        broker.sleepMs(poll_ms);
        const last = rt.last_hb_ms.load(.monotonic);
        const now = broker.nowMs();
        if (now > last and now - last > rt.opts.hb_window_ms) {
            var detail_buf: [96]u8 = undefined;
            const detail = std.fmt.bufPrint(&detail_buf, "no /hb within {d} ms", .{rt.opts.hb_window_ms}) catch "heartbeat window lapsed";
            rt.emitError("heartbeat_lapsed", detail);
            exitBroker(rt, "heartbeat_lapsed");
        }
    }
}

/// Blocks in waitpid on the shell. When the shell dies on its own,
/// gives the output pump a short drain window (buffered master bytes),
/// then emits `pty_exit`, reaps stragglers, and exits. Broker-initiated
/// teardown (shutdown/lapse/stdin EOF) wins via `teardown_started` and
/// emits `broker_exit` instead — exactly one final event per run.
fn childWaitMain(rt: *Runtime) void {
    var status: u32 = 0;
    while (true) {
        const rc = linux.waitpid(rt.child_pid, &status, 0);
        const errno = posix.errno(rc);
        if (errno == .INTR) continue;
        if (errno != .SUCCESS) status = 0;
        break;
    }
    // Let the pump drain what the kernel still buffers on the master.
    broker.sleepMs(200);
    if (rt.teardown_started.swap(true, .monotonic)) broker.parkUntilExit();
    // Escalate over the (dead leader's) whole session so orphaned
    // background jobs holding the slave open are also torn down.
    escalateKillSession(rt.child_pid, rt.opts.grace_ms);
    var line_storage: [96]u8 = undefined;
    const line = if (linux.W.IFEXITED(status))
        std.fmt.bufPrint(&line_storage, "{{\"event\":\"pty_exit\",\"reason\":\"exited\",\"code\":{d}}}", .{linux.W.EXITSTATUS(status)})
    else if (linux.W.IFSIGNALED(status))
        std.fmt.bufPrint(&line_storage, "{{\"event\":\"pty_exit\",\"reason\":\"signal\",\"code\":{d}}}", .{@intFromEnum(linux.W.TERMSIG(status))})
    else
        std.fmt.bufPrint(&line_storage, "{{\"event\":\"pty_exit\",\"reason\":\"unknown\",\"code\":-1}}", .{});
    if (line) |l| rt.emitLine(l) else |_| {}
    std.process.exit(0);
}

// ---------------------------------------------------------- HTTP serving

fn httpServeMain(rt: *Runtime) void {
    while (true) {
        var stream = rt.server.accept(rt.io) catch |err| switch (err) {
            error.ConnectionAborted, error.WouldBlock => continue,
            else => return,
        };
        handleConnection(rt, stream);
        stream.close(rt.io);
    }
}

fn handleConnection(rt: *Runtime, stream: std.Io.net.Stream) void {
    const fd = stream.socket.handle;
    const buf = rt.http_buf;
    var len: usize = 0;
    const head_end = while (true) {
        if (std.mem.indexOf(u8, buf[0..len], "\r\n\r\n")) |i| break i;
        if (len >= broker.max_http_head_bytes) {
            broker.respond(rt.io, stream, "431 Request Header Fields Too Large", "{\"error\":\"head too large\"}");
            return;
        }
        const n = broker.readFd(fd, buf[len..@min(buf.len, broker.max_http_head_bytes + 1)]);
        if (n == 0) return;
        len += n;
    };
    const request = broker.HttpRequest.parse(buf[0..head_end]) catch {
        broker.respond(rt.io, stream, "400 Bad Request", "{\"error\":\"malformed request\"}");
        return;
    };
    if (!std.mem.eql(u8, request.method, "POST")) {
        broker.respond(rt.io, stream, "405 Method Not Allowed", "{\"error\":\"POST only\"}");
        return;
    }
    if (authStatus(request.token, &rt.token)) |status| {
        broker.respond(rt.io, stream, status, "{\"error\":\"missing or bad X-Broker-Token\"}");
        return;
    }
    if (request.content_length > max_post_body_bytes) {
        broker.respond(rt.io, stream, "413 Payload Too Large", "{\"error\":\"body exceeds 64 KiB\"}");
        return;
    }
    const body_start = head_end + 4;
    const body_total = body_start + request.content_length;
    if (body_total > buf.len) {
        broker.respond(rt.io, stream, "413 Payload Too Large", "{\"error\":\"request too large\"}");
        return;
    }
    while (len < body_total) {
        const n = broker.readFd(fd, buf[len..body_total]);
        if (n == 0) return;
        len += n;
    }
    const body = buf[body_start..body_total];

    if (std.mem.eql(u8, request.target, "/hb")) {
        rt.last_hb_ms.store(broker.nowMs(), .monotonic);
        broker.respond(rt.io, stream, "204 No Content", "");
    } else if (std.mem.eql(u8, request.target, "/shutdown")) {
        broker.respond(rt.io, stream, "204 No Content", "");
        exitBroker(rt, "shutdown_requested");
    } else if (std.mem.eql(u8, request.target, "/input")) {
        const decoded = decodeInputBody(body, rt.body_scratch, rt.input_buf) catch |err| {
            const message = switch (err) {
                error.Malformed => "{\"error\":\"expected {\\\"b64\\\":\\\"...\\\"}\"}",
                error.InvalidBase64 => "{\"error\":\"invalid base64\"}",
                error.InputTooLarge => "{\"error\":\"decoded input exceeds 48 KiB\"}",
            };
            broker.respond(rt.io, stream, "400 Bad Request", message);
            return;
        };
        if (decoded.len > 0) {
            rt.master_write_mutex.lockUncancelable(rt.io);
            defer rt.master_write_mutex.unlock(rt.io);
            broker.writeAllFd(rt.master_fd, decoded) catch {
                rt.emitError("pty_write_failed", "write to PTY master failed");
                broker.respond(rt.io, stream, "502 Bad Gateway", "{\"error\":\"pty gone\"}");
                return;
            };
        }
        broker.respond(rt.io, stream, "204 No Content", "");
    } else if (std.mem.eql(u8, request.target, "/resize")) {
        const size = parseResizeBody(body, rt.body_scratch) catch |err| {
            const message = switch (err) {
                error.Malformed => "{\"error\":\"expected {\\\"cols\\\":N,\\\"rows\\\":M}\"}",
                error.OutOfRange => "{\"error\":\"cols/rows out of [1,1000]\"}",
            };
            broker.respond(rt.io, stream, "400 Bad Request", message);
            return;
        };
        applyWinsize(rt.master_fd, size);
        broker.respond(rt.io, stream, "204 No Content", "");
    } else {
        broker.respond(rt.io, stream, "404 Not Found", "{\"error\":\"unknown path\"}");
    }
}

// ----------------------------------------------------------------- main

pub fn main(init: std.process.Init) !u8 {
    if (builtin.os.tag != .linux) {
        std.log.err("pty_broker: only Linux is implemented (macOS untested, Windows BLOCKED on ConPTY)", .{});
        return 2;
    }
    const io = init.io;
    const gpa = init.gpa;

    var argv_storage: [max_cli_args][]const u8 = undefined;
    var argv_len: usize = 0;
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next(); // argv[0]
    while (args.next()) |arg| {
        if (argv_len >= argv_storage.len) {
            std.log.err("too many arguments (max {d})", .{argv_storage.len});
            return 2;
        }
        argv_storage[argv_len] = arg;
        argv_len += 1;
    }
    const usage = "usage: pty_broker [--liveness=stdin|http] [--hb-window-ms=N] [--grace-ms=N] [--cwd=DIR] [--term=NAME] [--cols=N] [--rows=N] [--] [shell-cmd args...]";
    const parsed = PtyOptions.parse(argv_storage[0..argv_len]) catch |err| {
        std.log.err("{t}; {s}", .{ err, usage });
        return 2;
    };
    const shell_argv = argv_storage[parsed.shell_argv_start..argv_len];

    broker.ignoreSigpipe();
    broker.installDeathBackstop();

    const rt = try gpa.create(Runtime);
    rt.* = .{
        .io = io,
        .opts = parsed.options,
        .read_buf = try gpa.alloc(u8, data_chunk_raw_bytes),
        .b64_buf = try gpa.alloc(u8, data_b64_bytes),
        .line_buf = try gpa.alloc(u8, data_line_bytes),
        .http_buf = try gpa.alloc(u8, broker.max_http_head_bytes + max_post_body_bytes + 4),
        .body_scratch = try gpa.alloc(u8, body_scratch_bytes),
        .input_buf = try gpa.alloc(u8, max_input_raw_bytes),
    };

    var token_bytes: [broker.token_len / 2]u8 = undefined;
    try io.randomSecure(&token_bytes);
    rt.token = std.fmt.bytesToHex(token_bytes, .lower);

    // ---- PTY + shell (fork BEFORE any threads or the listener exist,
    // so the child inherits nothing but stdio + the master fd, both of
    // which it replaces/closes).
    var pty = openPty(.{ .cols = parsed.options.cols, .rows = parsed.options.rows }) catch |err| {
        var msg_buf: [128]u8 = undefined;
        const detail = std.fmt.bufPrint(&msg_buf, "openpty failed: {t}", .{err}) catch "openpty failed";
        rt.emitError("openpty_failed", detail);
        return 1;
    };
    rt.master_fd = pty.master_fd;

    const plan = try gpa.create(ChildPlan);
    plan.* = .{ .slave_path = &pty.slave_path, .master_fd = pty.master_fd };
    var string_arena: [8192]u8 = undefined;
    buildChildPlan(plan, &string_arena, init.minimal.environ, parsed.options, shell_argv) catch |err| {
        var msg_buf: [128]u8 = undefined;
        const detail = std.fmt.bufPrint(&msg_buf, "shell setup failed: {t}", .{err}) catch "shell setup failed";
        rt.emitError("spawn_failed", detail);
        return 1;
    };

    const fork_rc = linux.fork();
    if (posix.errno(fork_rc) != .SUCCESS) {
        rt.emitError("spawn_failed", "fork failed");
        return 1;
    }
    if (fork_rc == 0) childExec(plan); // never returns
    rt.child_pid = @intCast(fork_rc);
    broker.armDeathBackstop(rt.child_pid);

    // ---- Listener (created after fork: the shell never sees it).
    const address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    rt.server = try address.listen(io, .{});
    const port = try broker.boundPort(&rt.server);

    {
        var line_storage: [128]u8 = undefined;
        const line = try std.fmt.bufPrint(&line_storage, "{{\"event\":\"listening\",\"port\":{d},\"token\":\"{s}\"}}", .{ port, rt.token });
        rt.emitLine(line);
    }

    switch (rt.opts.liveness) {
        .stdin => {
            var stdin_thread = try std.Thread.spawn(.{}, stdinWatchMain, .{rt});
            stdin_thread.detach();
        },
        .http => {
            rt.last_hb_ms.store(broker.nowMs(), .monotonic);
            var hb_thread = try std.Thread.spawn(.{}, heartbeatWatchMain, .{rt});
            hb_thread.detach();
        },
    }
    var http_thread = try std.Thread.spawn(.{}, httpServeMain, .{rt});
    http_thread.detach();
    var wait_thread = try std.Thread.spawn(.{}, childWaitMain, .{rt});
    wait_thread.detach();

    // Main loop: pump PTY master output into bounded NDJSON data events.
    // read(2) coalesces bursts up to the 48 KiB chunk size per event; at
    // steady state that is one wakeup per SDK line, well inside the
    // 256 KiB line and 64-entry completion-queue budgets.
    while (true) {
        const n = broker.readFd(rt.master_fd, rt.read_buf);
        if (n == 0) break; // EIO/EOF: every slave fd closed (shell tree gone)
        const line = encodeDataEvent(rt.line_buf, rt.b64_buf, rt.read_buf[0..n]) catch {
            rt.emitError("emit_failed", "data event buffer overflow");
            continue;
        };
        rt.emitLine(line);
    }
    // The wait thread owns pty_exit emission; it is already reaping (or
    // a teardown owner is escalating). Park until one of them exits us.
    broker.parkUntilExit();
}

const BuildPlanError = error{ TooManyShellArgs, ValueTooLong, NoShell, ArenaFull };

/// Fill the ChildPlan: argv (login-style $SHELL default or explicit),
/// exec path candidates (absolute or PATH search), envp (parent
/// environment with TERM replaced), cwd. All strings are copied into
/// `arena` (must outlive exec) as NUL-terminated.
fn buildChildPlan(
    plan: *ChildPlan,
    arena: []u8,
    environ: std.process.Environ,
    opts: PtyOptions,
    shell_argv: []const []const u8,
) BuildPlanError!void {
    var used: usize = 0;

    // envp: pass everything through except TERM, then add our TERM.
    var env_count: usize = 0;
    const env_slice: []const ?[*:0]const u8 = environ.block.slice;
    for (env_slice) |entry_opt| {
        const entry = entry_opt orelse continue;
        if (std.mem.startsWith(u8, std.mem.span(entry), "TERM=")) continue;
        if (env_count >= max_env_entries) break;
        plan.envp[env_count] = entry;
        env_count += 1;
    }
    plan.envp[env_count] = try internFmt(arena, &used, "TERM={s}", .{opts.term});
    env_count += 1;
    plan.envp[env_count] = null;

    if (opts.cwd) |cwd| plan.cwd = try internFmt(arena, &used, "{s}", .{cwd});

    if (shell_argv.len == 0) {
        // Login-style default shell: file = $SHELL (fallback /bin/sh),
        // argv0 = "-basename".
        const shell_path = envValue(env_slice, "SHELL") orelse "/bin/sh";
        plan.exec_paths[0] = try internFmt(arena, &used, "{s}", .{shell_path});
        var argv0_buf: [128]u8 = undefined;
        const argv0 = loginArgv0(&argv0_buf, shell_path) catch return error.NoShell;
        plan.argv[0] = try internFmt(arena, &used, "{s}", .{argv0});
        plan.argv[1] = null;
        return;
    }

    if (shell_argv.len > max_shell_args) return error.TooManyShellArgs;
    for (shell_argv, 0..) |arg, i| {
        if (arg.len > max_flag_value_bytes) return error.ValueTooLong;
        plan.argv[i] = try internFmt(arena, &used, "{s}", .{arg});
    }
    plan.argv[shell_argv.len] = null;

    const command = shell_argv[0];
    if (std.mem.indexOfScalar(u8, command, '/') != null) {
        plan.exec_paths[0] = plan.argv[0].?;
        return;
    }
    // Bare command: resolve against PATH, trying candidates in order.
    const path_env = envValue(env_slice, "PATH") orelse "/usr/local/bin:/usr/bin:/bin";
    var candidates: usize = 0;
    var dirs = std.mem.splitScalar(u8, path_env, ':');
    while (dirs.next()) |dir| {
        if (dir.len == 0 or candidates >= plan.exec_paths.len - 1) continue;
        plan.exec_paths[candidates] = internFmt(arena, &used, "{s}/{s}", .{ dir, command }) catch break;
        candidates += 1;
    }
    if (candidates == 0) return error.NoShell;
}

fn envValue(env_slice: []const ?[*:0]const u8, name: []const u8) ?[]const u8 {
    for (env_slice) |entry_opt| {
        const entry = entry_opt orelse continue;
        const text = std.mem.span(entry);
        if (text.len > name.len + 1 and
            std.mem.startsWith(u8, text, name) and text[name.len] == '=')
        {
            return text[name.len + 1 ..];
        }
    }
    return null;
}

/// Copy a formatted NUL-terminated string into the arena; returns the
/// stable pointer for execve.
fn internFmt(arena: []u8, used: *usize, comptime fmt: []const u8, args: anytype) BuildPlanError![*:0]const u8 {
    const rest = arena[used.*..];
    const written = std.fmt.bufPrintZ(rest, fmt, args) catch return error.ArenaFull;
    used.* += written.len + 1;
    return written.ptr;
}

// ================================================================ tests

const testing = std.testing;

var test_scratch: [body_scratch_bytes]u8 = undefined;

// ------------------------------------------------------------- options

test "pty options default to stdin liveness, 80x24, xterm-256color, $SHELL" {
    const args = [_][]const u8{};
    const parsed = try PtyOptions.parse(&args);
    try testing.expectEqual(broker.LivenessMode.stdin, parsed.options.liveness);
    try testing.expectEqual(@as(u16, 80), parsed.options.cols);
    try testing.expectEqual(@as(u16, 24), parsed.options.rows);
    try testing.expectEqualStrings("xterm-256color", parsed.options.term);
    try testing.expectEqual(@as(?[]const u8, null), parsed.options.cwd);
    // shell_argv_start == args.len means "use $SHELL".
    try testing.expectEqual(@as(usize, 0), parsed.shell_argv_start);
}

test "pty options parse full flag set and explicit shell argv" {
    const args = [_][]const u8{
        "--liveness=http",  "--hb-window-ms=2000", "--grace-ms=500",
        "--cwd=/workspace", "--term=xterm",        "--cols=120",
        "--rows=40",        "--",                  "bash",
        "--norc",
    };
    const parsed = try PtyOptions.parse(&args);
    try testing.expectEqual(broker.LivenessMode.http, parsed.options.liveness);
    try testing.expectEqual(@as(u64, 2000), parsed.options.hb_window_ms);
    try testing.expectEqual(@as(u64, 500), parsed.options.grace_ms);
    try testing.expectEqualStrings("/workspace", parsed.options.cwd.?);
    try testing.expectEqualStrings("xterm", parsed.options.term);
    try testing.expectEqual(@as(u16, 120), parsed.options.cols);
    try testing.expectEqual(@as(u16, 40), parsed.options.rows);
    try testing.expectEqual(@as(usize, 8), parsed.shell_argv_start);
}

test "pty options reject bad geometry, relative cwd, unknown flags" {
    const zero_cols = [_][]const u8{"--cols=0"};
    try testing.expectError(error.InvalidFlagValue, PtyOptions.parse(&zero_cols));
    const huge_rows = [_][]const u8{"--rows=1001"};
    try testing.expectError(error.InvalidFlagValue, PtyOptions.parse(&huge_rows));
    const rel_cwd = [_][]const u8{"--cwd=workspace"};
    try testing.expectError(error.InvalidFlagValue, PtyOptions.parse(&rel_cwd));
    const junk = [_][]const u8{"--pty=yes"};
    try testing.expectError(error.UnknownFlag, PtyOptions.parse(&junk));
    const bad_mode = [_][]const u8{"--liveness=tcp"};
    try testing.expectError(error.InvalidFlagValue, PtyOptions.parse(&bad_mode));
}

test "pty options `--` separator protects a shell command that starts with dashes" {
    const args = [_][]const u8{ "--liveness=http", "--", "--weird-shell" };
    const parsed = try PtyOptions.parse(&args);
    try testing.expectEqual(@as(usize, 2), parsed.shell_argv_start);
    const bare = [_][]const u8{"--weird-shell"};
    try testing.expectError(error.UnknownFlag, PtyOptions.parse(&bare));
}

// -------------------------------------------------------- resize parsing

test "resize body parses cols and rows" {
    const size = try parseResizeBody("{\"cols\":120,\"rows\":40}", &test_scratch);
    try testing.expectEqual(@as(u16, 120), size.cols);
    try testing.expectEqual(@as(u16, 40), size.rows);
}

test "resize body rejects out-of-range and malformed geometry" {
    try testing.expectError(error.OutOfRange, parseResizeBody("{\"cols\":0,\"rows\":40}", &test_scratch));
    try testing.expectError(error.OutOfRange, parseResizeBody("{\"cols\":80,\"rows\":1001}", &test_scratch));
    try testing.expectError(error.OutOfRange, parseResizeBody("{\"cols\":-3,\"rows\":24}", &test_scratch));
    try testing.expectError(error.Malformed, parseResizeBody("{\"cols\":80}", &test_scratch));
    try testing.expectError(error.Malformed, parseResizeBody("{\"cols\":\"80\",\"rows\":24}", &test_scratch));
    try testing.expectError(error.Malformed, parseResizeBody("not json", &test_scratch));
    try testing.expectError(error.Malformed, parseResizeBody("", &test_scratch));
    try testing.expectError(error.Malformed, parseResizeBody("[80,24]", &test_scratch));
}

// --------------------------------------------------- input write framing

test "input body decodes base64 into the write buffer" {
    var out: [64]u8 = undefined;
    // "echo hi\n" -> ZWNobyBoaQo=
    const decoded = try decodeInputBody("{\"b64\":\"ZWNobyBoaQo=\"}", &test_scratch, &out);
    try testing.expectEqualStrings("echo hi\n", decoded);
}

test "input body accepts empty payload and rejects malformed/oversized" {
    var out: [max_input_raw_bytes]u8 = undefined;
    const empty = try decodeInputBody("{\"b64\":\"\"}", &test_scratch, &out);
    try testing.expectEqual(@as(usize, 0), empty.len);
    try testing.expectError(error.Malformed, decodeInputBody("{}", &test_scratch, &out));
    try testing.expectError(error.Malformed, decodeInputBody("{\"b64\":7}", &test_scratch, &out));
    try testing.expectError(error.InvalidBase64, decodeInputBody("{\"b64\":\"@@@@\"}", &test_scratch, &out));
    // Decoded length above the input cap is refused even when the body
    // itself fits in a POST.
    var small_out: [4]u8 = undefined;
    try testing.expectError(error.InputTooLarge, decodeInputBody("{\"b64\":\"ZWNobyBoaQo=\"}", &test_scratch, &small_out));
}

test "input decode is bounded at both the body cap and the decode buffer" {
    // (a) A body over the 64 KiB POST cap is refused before parsing —
    // this is the outer bound that makes >48 KiB decoded impossible.
    const oversized = try testing.allocator.alloc(u8, max_post_body_bytes + 1);
    defer testing.allocator.free(oversized);
    @memset(oversized, 'x');
    var out: [max_input_raw_bytes]u8 = undefined;
    try testing.expectError(error.Malformed, decodeInputBody(oversized, &test_scratch, &out));

    // (b) A well-formed body whose decoded size exceeds the caller's
    // buffer is refused by the decode bound, never a buffer overrun.
    const raw_len = 40 * 1024;
    const raw = try testing.allocator.alloc(u8, raw_len);
    defer testing.allocator.free(raw);
    @memset(raw, 'x');
    const b64_len = std.base64.standard.Encoder.calcSize(raw_len);
    const b64_storage = try testing.allocator.alloc(u8, b64_len);
    defer testing.allocator.free(b64_storage);
    const b64 = std.base64.standard.Encoder.encode(b64_storage, raw);
    const body = try testing.allocator.alloc(u8, b64_len + 32);
    defer testing.allocator.free(body);
    const rendered = try std.fmt.bufPrint(body, "{{\"b64\":\"{s}\"}}", .{b64});
    var small_out: [32 * 1024]u8 = undefined;
    const big_scratch = try testing.allocator.alloc(u8, 512 * 1024);
    defer testing.allocator.free(big_scratch);
    try testing.expectError(error.InputTooLarge, decodeInputBody(rendered, big_scratch, &small_out));
    // The same body decodes fine into a big-enough buffer.
    const ok = try decodeInputBody(rendered, big_scratch, &out);
    try testing.expectEqual(raw_len, ok.len);
}

// --------------------------------------------------- base64 chunk bounds

test "data event encodes raw bytes as one bounded NDJSON line" {
    var line_buf: [data_line_bytes]u8 = undefined;
    var b64_buf: [data_b64_bytes]u8 = undefined;
    const line = try encodeDataEvent(&line_buf, &b64_buf, "hi\r\n$ ");
    try testing.expectEqualStrings("{\"event\":\"data\",\"b64\":\"aGkNCiQg\"}", line);
    // Never a raw newline inside the line (NDJSON safety).
    try testing.expect(std.mem.indexOfScalar(u8, line, '\n') == null);
}

test "data event at the full 48 KiB chunk stays under the SDK line cap" {
    const raw = try testing.allocator.alloc(u8, data_chunk_raw_bytes);
    defer testing.allocator.free(raw);
    @memset(raw, 0xff); // worst case: every byte needs base64
    const line_buf = try testing.allocator.alloc(u8, data_line_bytes);
    defer testing.allocator.free(line_buf);
    const b64_buf = try testing.allocator.alloc(u8, data_b64_bytes);
    defer testing.allocator.free(b64_buf);
    const line = try encodeDataEvent(line_buf, b64_buf, raw);
    try testing.expect(line.len < 256 * 1024); // SDK .lines ceiling
    try testing.expect(line.len <= data_line_bytes);
}

test "data event refuses chunks above the raw bound" {
    const raw = try testing.allocator.alloc(u8, data_chunk_raw_bytes + 1);
    defer testing.allocator.free(raw);
    @memset(raw, 'x');
    var line_buf: [128]u8 = undefined;
    var b64_buf: [128]u8 = undefined;
    try testing.expectError(error.ChunkTooLarge, encodeDataEvent(&line_buf, &b64_buf, raw));
}

// ---------------------------------------------------------------- auth

test "requests without a token are refused" {
    const expected = "fee8c75f408e830831425370bb633345";
    try testing.expectEqualStrings("401 Unauthorized", authStatus(null, expected).?);
    // A parsed head without X-Broker-Token yields token == null.
    const head = "POST /input HTTP/1.1\r\nContent-Length: 2";
    const request = try broker.HttpRequest.parse(head);
    try testing.expectEqual(@as(?[]const u8, null), request.token);
    try testing.expect(authStatus(request.token, expected) != null);
}

test "wrong or truncated tokens are refused, exact token accepted" {
    const expected = "fee8c75f408e830831425370bb633345";
    try testing.expect(authStatus("fee8c75f408e830831425370bb633346", expected) != null);
    try testing.expect(authStatus("fee8c75f", expected) != null);
    try testing.expect(authStatus("", expected) != null);
    try testing.expectEqual(@as(?[]const u8, null), authStatus(expected, expected));
}

// --------------------------------------------------- session escalation

test "session id parses from /proc stat text, zombies excluded" {
    // Real shape, including a comm with spaces and parens.
    const stat = "1234 (tmux: server (x)) S 1 1234 1234 0 -1 4194560 100 0 0 0";
    try testing.expectEqual(@as(?posix.pid_t, 1234), sessionIdFromStat(stat));
    const other = "77 (sleep) S 42 900 4321 0 -1 0 0";
    try testing.expectEqual(@as(?posix.pid_t, 4321), sessionIdFromStat(other));
    const zombie = "78 (sleep) Z 42 900 4321 0 -1 0 0";
    try testing.expectEqual(@as(?posix.pid_t, null), sessionIdFromStat(zombie));
    try testing.expectEqual(@as(?posix.pid_t, null), sessionIdFromStat("garbage with no comm"));
    try testing.expectEqual(@as(?posix.pid_t, null), sessionIdFromStat("1 (x) S 1"));
    try testing.expectEqual(@as(?posix.pid_t, null), sessionIdFromStat(""));
}

// ---------------------------------------------------------- shell argv

test "login-style argv0 prefixes the shell basename with a dash" {
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("-bash", try loginArgv0(&buf, "/bin/bash"));
    try testing.expectEqualStrings("-zsh", try loginArgv0(&buf, "/usr/local/bin/zsh"));
    try testing.expectEqualStrings("-sh", try loginArgv0(&buf, "sh"));
    var tiny: [2]u8 = undefined;
    try testing.expectError(error.OutputTooSmall, loginArgv0(&tiny, "/bin/bash"));
}
