//! Bounded, transport-independent LSP broker state.
//! This module does not spawn, supervise, or claim a language-server process.

const std = @import("std");
const jsonrpc = @import("jsonrpc.zig");

pub const max_sessions: usize = 4;
pub const max_pending_requests: usize = 32;
pub const max_diagnostics: usize = 128;
pub const max_session_name_bytes: usize = 64;
pub const max_method_bytes: usize = 96;
pub const max_uri_bytes: usize = 512;
pub const max_message_bytes: usize = 512;

pub const TransportAvailability = enum {
    unavailable,
};

pub fn transportAvailability() TransportAvailability {
    return .unavailable;
}

pub const SessionState = enum {
    created,
    initializing,
    ready,
    stopped,
    failed,
};

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

pub const DiagnosticInput = struct {
    uri: []const u8,
    range: Range,
    severity: Severity,
    message: []const u8,
};

pub const Diagnostic = struct {
    uri_storage: [max_uri_bytes]u8 = undefined,
    uri_len: usize = 0,
    range: Range = .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 0, .character = 0 },
    },
    severity: Severity = .information,
    message_storage: [max_message_bytes]u8 = undefined,
    message_len: usize = 0,

    pub fn uri(self: *const Diagnostic) []const u8 {
        return self.uri_storage[0..self.uri_len];
    }

    pub fn message(self: *const Diagnostic) []const u8 {
        return self.message_storage[0..self.message_len];
    }

    fn set(self: *Diagnostic, input: DiagnosticInput) !void {
        if (input.uri.len == 0 or input.uri.len > max_uri_bytes) return error.InvalidDiagnosticUri;
        if (input.message.len > max_message_bytes) return error.DiagnosticMessageTooLong;
        if (positionAfter(input.range.start, input.range.end)) return error.InvalidDiagnosticRange;
        @memcpy(self.uri_storage[0..input.uri.len], input.uri);
        @memcpy(self.message_storage[0..input.message.len], input.message);
        self.uri_len = input.uri.len;
        self.message_len = input.message.len;
        self.range = input.range;
        self.severity = input.severity;
    }
};

const PendingRequest = struct {
    id: u64 = 0,
    method_storage: [max_method_bytes]u8 = undefined,
    method_len: usize = 0,

    fn method(self: *const PendingRequest) []const u8 {
        return self.method_storage[0..self.method_len];
    }
};

pub const Session = struct {
    id: u32 = 0,
    name_storage: [max_session_name_bytes]u8 = undefined,
    name_len: usize = 0,
    state: SessionState = .created,
    ids: jsonrpc.RequestIdSequence = .{},
    pending: [max_pending_requests]PendingRequest = [_]PendingRequest{.{}} ** max_pending_requests,
    pending_count: usize = 0,

    pub fn name(self: *const Session) []const u8 {
        return self.name_storage[0..self.name_len];
    }

    pub fn beginRequest(self: *Session, method: []const u8) !jsonrpc.RequestId {
        if (self.state == .stopped or self.state == .failed) return error.SessionNotActive;
        if (method.len == 0 or method.len > max_method_bytes) return error.InvalidMethod;
        if (self.pending_count >= max_pending_requests) return error.TooManyPendingRequests;
        const request_id = try self.ids.take();
        const id = request_id.integer;
        var pending = &self.pending[self.pending_count];
        pending.id = id;
        @memcpy(pending.method_storage[0..method.len], method);
        pending.method_len = method.len;
        self.pending_count += 1;
        return request_id;
    }

    pub fn completeRequest(self: *Session, id: jsonrpc.RequestId) !void {
        try id.validate();
        const integer_id = switch (id) {
            .integer => |value| value,
            .string => return error.UnknownRequest,
        };
        var index: usize = 0;
        while (index < self.pending_count) : (index += 1) {
            if (self.pending[index].id == integer_id) {
                self.pending_count -= 1;
                if (index != self.pending_count) self.pending[index] = self.pending[self.pending_count];
                return;
            }
        }
        return error.UnknownRequest;
    }

    pub fn pendingMethod(self: *const Session, index: usize) ?[]const u8 {
        if (index >= self.pending_count) return null;
        return self.pending[index].method();
    }
};

pub const Broker = struct {
    sessions: [max_sessions]Session = [_]Session{.{}} ** max_sessions,
    session_count: usize = 0,
    next_session_id: u32 = 1,
    diagnostics: [max_diagnostics]Diagnostic = [_]Diagnostic{.{}} ** max_diagnostics,
    diagnostic_count: usize = 0,

    pub fn openSession(self: *Broker, name: []const u8) !*Session {
        if (name.len == 0 or name.len > max_session_name_bytes) return error.InvalidSessionName;
        if (self.session_count >= max_sessions) return error.TooManySessions;
        if (self.next_session_id == 0) return error.SessionIdExhausted;

        var session = &self.sessions[self.session_count];
        session.* = .{};
        session.id = self.next_session_id;
        self.next_session_id +%= 1;
        @memcpy(session.name_storage[0..name.len], name);
        session.name_len = name.len;
        self.session_count += 1;
        return session;
    }

    pub fn closeSession(self: *Broker, id: u32) !void {
        var index: usize = 0;
        while (index < self.session_count) : (index += 1) {
            if (self.sessions[index].id == id) {
                self.session_count -= 1;
                if (index != self.session_count) self.sessions[index] = self.sessions[self.session_count];
                return;
            }
        }
        return error.UnknownSession;
    }

    /// Replace the current bounded diagnostic snapshot atomically.
    pub fn replaceDiagnostics(self: *Broker, inputs: []const DiagnosticInput) !void {
        if (inputs.len > max_diagnostics) return error.TooManyDiagnostics;
        var staged: [max_diagnostics]Diagnostic = [_]Diagnostic{.{}} ** max_diagnostics;
        for (inputs, 0..) |input, index| try staged[index].set(input);
        for (0..inputs.len) |index| self.diagnostics[index] = staged[index];
        self.diagnostic_count = inputs.len;
    }

    pub fn diagnostic(self: *const Broker, index: usize) ?*const Diagnostic {
        if (index >= self.diagnostic_count) return null;
        return &self.diagnostics[index];
    }
};

fn positionAfter(left: Position, right: Position) bool {
    return left.line > right.line or
        (left.line == right.line and left.character > right.character);
}

test "broker bounds sessions and tracks request ids without transport" {
    var broker: Broker = .{};
    try std.testing.expectEqual(TransportAvailability.unavailable, transportAvailability());
    const session = try broker.openSession("typescript");
    session.state = .initializing;
    const first = try session.beginRequest("initialize");
    const second = try session.beginRequest("textDocument/hover");
    try std.testing.expectEqual(@as(u64, 1), first.integer);
    try std.testing.expectEqual(@as(u64, 2), second.integer);
    try std.testing.expectEqualStrings("initialize", session.pendingMethod(0).?);
    try session.completeRequest(first);
    try std.testing.expectEqual(@as(usize, 1), session.pending_count);
}

test "diagnostic replacement validates before changing snapshot" {
    var broker: Broker = .{};
    const valid = [_]DiagnosticInput{.{
        .uri = "file:///workspace/main.zig",
        .range = .{
            .start = .{ .line = 2, .character = 4 },
            .end = .{ .line = 2, .character = 8 },
        },
        .severity = .@"error",
        .message = "expected expression",
    }};
    try broker.replaceDiagnostics(&valid);
    try std.testing.expectEqualStrings("expected expression", broker.diagnostic(0).?.message());

    const invalid = [_]DiagnosticInput{.{
        .uri = "file:///workspace/main.zig",
        .range = .{
            .start = .{ .line = 3, .character = 0 },
            .end = .{ .line = 2, .character = 0 },
        },
        .severity = .warning,
        .message = "bad range",
    }};
    try std.testing.expectError(error.InvalidDiagnosticRange, broker.replaceDiagnostics(&invalid));
    try std.testing.expectEqualStrings("expected expression", broker.diagnostic(0).?.message());
}
