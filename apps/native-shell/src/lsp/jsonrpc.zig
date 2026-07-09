//! Transport-independent, bounded JSON-RPC 2.0 framing primitives.
//! No stream, pipe, socket, or child-process transport is provided here.

const std = @import("std");

pub const max_header_bytes: usize = 1024;
pub const max_payload_bytes: usize = 1024 * 1024;
pub const max_string_id_bytes: usize = 64;

pub const RequestId = union(enum) {
    integer: u64,
    string: []const u8,

    pub fn validate(self: RequestId) !void {
        switch (self) {
            .integer => {},
            .string => |value| {
                if (value.len == 0 or value.len > max_string_id_bytes) {
                    return error.InvalidRequestId;
                }
            },
        }
    }
};

pub const DecodedFrame = struct {
    payload: []const u8,
    consumed: usize,
};

/// Decode one LSP-style `Content-Length` frame from a caller-owned byte slice.
/// Returned payload memory borrows `input`; incomplete input is not retained.
pub fn decodeFrame(input: []const u8) !DecodedFrame {
    const separator = "\r\n\r\n";
    const header_end = std.mem.indexOf(u8, input, separator) orelse {
        if (input.len > max_header_bytes) return error.HeaderTooLarge;
        return error.NeedMoreData;
    };
    if (header_end > max_header_bytes) return error.HeaderTooLarge;

    var content_length: ?usize = null;
    var lines = std.mem.splitSequence(u8, input[0..header_end], "\r\n");
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.InvalidHeader;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (std.ascii.eqlIgnoreCase(name, "Content-Length")) {
            if (content_length != null) return error.DuplicateContentLength;
            content_length = std.fmt.parseInt(usize, value, 10) catch return error.InvalidContentLength;
        }
    }

    const payload_len = content_length orelse return error.MissingContentLength;
    if (payload_len > max_payload_bytes) return error.PayloadTooLarge;
    const payload_start = header_end + separator.len;
    const frame_end = std.math.add(usize, payload_start, payload_len) catch return error.PayloadTooLarge;
    if (input.len < frame_end) return error.NeedMoreData;
    return .{
        .payload = input[payload_start..frame_end],
        .consumed = frame_end,
    };
}

/// Write one complete frame into caller-owned bounded storage.
pub fn encodeFrame(output: []u8, payload: []const u8) ![]const u8 {
    if (payload.len > max_payload_bytes) return error.PayloadTooLarge;
    var header: [64]u8 = undefined;
    const prefix = std.fmt.bufPrint(&header, "Content-Length: {d}\r\n\r\n", .{payload.len}) catch
        return error.OutputTooSmall;
    const total = std.math.add(usize, prefix.len, payload.len) catch return error.OutputTooSmall;
    if (output.len < total) return error.OutputTooSmall;
    @memcpy(output[0..prefix.len], prefix);
    @memcpy(output[prefix.len..total], payload);
    return output[0..total];
}

pub const RequestIdSequence = struct {
    next: u64 = 1,

    pub fn take(self: *RequestIdSequence) !RequestId {
        if (self.next == 0 or self.next == std.math.maxInt(u64)) return error.RequestIdExhausted;
        const value = self.next;
        self.next += 1;
        return .{ .integer = value };
    }
};

test "JSON-RPC frame round trips and leaves following bytes" {
    const payload = "{\"jsonrpc\":\"2.0\",\"id\":1}";
    var storage: [256]u8 = undefined;
    const encoded = try encodeFrame(&storage, payload);
    storage[encoded.len] = 'x';
    const decoded = try decodeFrame(storage[0 .. encoded.len + 1]);
    try std.testing.expectEqualStrings(payload, decoded.payload);
    try std.testing.expectEqual(encoded.len, decoded.consumed);
}

test "JSON-RPC framing is bounded and reports incomplete input" {
    try std.testing.expectError(error.NeedMoreData, decodeFrame("Content-Length: 5\r\n\r\nabc"));
    try std.testing.expectError(error.MissingContentLength, decodeFrame("X-Test: yes\r\n\r\n{}"));

    var tiny: [4]u8 = undefined;
    try std.testing.expectError(error.OutputTooSmall, encodeFrame(&tiny, "{}"));
}

test "request ids are monotonic and string ids are bounded" {
    var sequence: RequestIdSequence = .{};
    const first = try sequence.take();
    const second = try sequence.take();
    try std.testing.expectEqual(@as(u64, 1), first.integer);
    try std.testing.expectEqual(@as(u64, 2), second.integer);
    try (RequestId{ .string = "client-id" }).validate();
    try std.testing.expectError(error.InvalidRequestId, (RequestId{ .string = "" }).validate());
}
