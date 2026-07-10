//! Minimal stdio "language server" used by spike.sh to prove the
//! broker transport end-to-end without a real LSP install.
//!
//! Speaks Content-Length framing on stdin/stdout (reusing the broker's
//! bounded decoder/encoder):
//!   * `initialize`               -> canned InitializeResult, echoing the id
//!   * `textDocument/didOpen`     -> publishDiagnostics notification
//!                                   echoing the document uri
//!   * `shutdown`                 -> null result
//!   * `exit`                     -> process exit 0
//!   * any other request with id  -> -32601 MethodNotFound
//!
//! Build: zig build-exe fake_lsp.zig

const std = @import("std");
const posix = std.posix;
const broker = @import("lsp_broker.zig");

var out_frame_buf: [64 * 1024]u8 = undefined;
var out_payload_buf: [32 * 1024]u8 = undefined;

fn send(payload: []const u8) void {
    const frame = broker.encodeFrame(&out_frame_buf, payload) catch return;
    broker.writeAllFd(posix.STDOUT_FILENO, frame) catch std.process.exit(1);
}

fn idText(buf: []u8, id: std.json.Value) ![]const u8 {
    return switch (id) {
        .integer => |v| try std.fmt.bufPrint(buf, "{d}", .{v}),
        .string => |s| blk: {
            var escaped_buf: [128]u8 = undefined;
            const escaped = try broker.jsonEscape(&escaped_buf, s);
            break :blk try std.fmt.bufPrint(buf, "\"{s}\"", .{escaped});
        },
        else => "null",
    };
}

fn handle(gpa: std.mem.Allocator, payload: []const u8) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, payload, .{}) catch return;
    defer parsed.deinit();
    const root = switch (parsed.value) {
        .object => |o| o,
        else => return,
    };
    const method_value = root.get("method") orelse return; // responses: ignore
    const method = switch (method_value) {
        .string => |s| s,
        else => return,
    };
    const id_value = root.get("id");

    if (std.mem.eql(u8, method, "initialize")) {
        var id_buf: [160]u8 = undefined;
        const id = try idText(&id_buf, id_value orelse .null);
        const response = try std.fmt.bufPrint(
            &out_payload_buf,
            "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":{{\"capabilities\":{{\"textDocumentSync\":1,\"hoverProvider\":true}},\"serverInfo\":{{\"name\":\"fake-lsp\",\"version\":\"0.0.1\"}}}}}}",
            .{id},
        );
        send(response);
    } else if (std.mem.eql(u8, method, "textDocument/didOpen")) {
        var uri: []const u8 = "file:///unknown";
        if (root.get("params")) |params| {
            if (params == .object) {
                if (params.object.get("textDocument")) |doc| {
                    if (doc == .object) {
                        if (doc.object.get("uri")) |u| {
                            if (u == .string) uri = u.string;
                        }
                    }
                }
            }
        }
        var uri_buf: [2048]u8 = undefined;
        const escaped_uri = try broker.jsonEscape(&uri_buf, uri);
        const notification = try std.fmt.bufPrint(
            &out_payload_buf,
            "{{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{{\"uri\":\"{s}\",\"diagnostics\":[{{\"range\":{{\"start\":{{\"line\":0,\"character\":0}},\"end\":{{\"line\":0,\"character\":4}}}},\"severity\":2,\"message\":\"fake-lsp saw didOpen ({d} payload bytes)\"}}]}}}}",
            .{ escaped_uri, payload.len },
        );
        send(notification);
    } else if (std.mem.eql(u8, method, "shutdown")) {
        var id_buf: [160]u8 = undefined;
        const id = try idText(&id_buf, id_value orelse .null);
        const response = try std.fmt.bufPrint(
            &out_payload_buf,
            "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"result\":null}}",
            .{id},
        );
        send(response);
    } else if (std.mem.eql(u8, method, "exit")) {
        std.process.exit(0);
    } else if (id_value != null) {
        var id_buf: [160]u8 = undefined;
        const id = try idText(&id_buf, id_value.?);
        const response = try std.fmt.bufPrint(
            &out_payload_buf,
            "{{\"jsonrpc\":\"2.0\",\"id\":{s},\"error\":{{\"code\":-32601,\"message\":\"method not found\"}}}}",
            .{id},
        );
        send(response);
    }
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const decode_buf = try gpa.alloc(u8, broker.FrameDecoder.recommended_buffer_bytes);
    defer gpa.free(decode_buf);
    var decoder = broker.FrameDecoder.init(decode_buf);
    var read_buf: [16 * 1024]u8 = undefined;

    while (true) {
        var n: usize = 0;
        while (true) {
            const rc = posix.system.read(posix.STDIN_FILENO, &read_buf, read_buf.len);
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    n = @intCast(rc);
                    break;
                },
                .INTR => continue,
                else => return,
            }
        }
        if (n == 0) return; // broker died / closed our stdin
        decoder.feed(read_buf[0..n]) catch {
            decoder.reset();
            continue;
        };
        while (decoder.next()) |item| switch (item) {
            .frame => |payload| try handle(gpa, payload),
            else => {},
        };
    }
}
