//! In-process startup and interaction marks.
//! Durations use the Native SDK monotonic clock; wall time is never used.

const std = @import("std");
const native_sdk = @import("native_sdk");

pub const Measurement = struct {
    value_ns: u64 = 0,
    available: bool = false,

    pub fn measured(value_ns: u64) Measurement {
        return .{ .value_ns = value_ns, .available = true };
    }
};

pub const Marks = struct {
    boot_to_first_observed_nonblank_ns: Measurement = .{},
    sdk_first_frame_latency_ns: Measurement = .{},
    boot_to_first_chrome_callback_ns: Measurement = .{},
    command_palette_request_to_present_ns: Measurement = .{},
    terminal_panel_request_to_present_ns: Measurement = .{},
};

pub const Timer = struct {
    clock: native_sdk.Clock = .system,
    boot_ns: u64 = 0,
    marks: Marks = .{},
    palette_pending_ns: ?u64 = null,
    terminal_pending_ns: ?u64 = null,

    pub fn init(clock: native_sdk.Clock, boot_ns: u64) Timer {
        return .{ .clock = clock, .boot_ns = boot_ns };
    }

    pub fn markChromeCallback(self: *Timer) void {
        if (self.marks.boot_to_first_chrome_callback_ns.available) return;
        self.marks.boot_to_first_chrome_callback_ns = elapsed(self.boot_ns, self.clock.monotonicNanoseconds());
    }

    pub fn requestCommandPalette(self: *Timer) void {
        self.palette_pending_ns = readableNow(self.clock);
    }

    pub fn requestTerminalPanel(self: *Timer) void {
        self.terminal_pending_ns = readableNow(self.clock);
    }

    pub fn observeFrame(
        self: *Timer,
        frame: native_sdk.GpuFrame,
        palette_present: bool,
        terminal_present: bool,
    ) void {
        if (frame.nonblank and !self.marks.boot_to_first_observed_nonblank_ns.available) {
            self.marks.boot_to_first_observed_nonblank_ns = elapsed(self.boot_ns, frame.timestamp_ns);
        }
        if (frame.first_frame_latency_ns > 0 and !self.marks.sdk_first_frame_latency_ns.available) {
            self.marks.sdk_first_frame_latency_ns = Measurement.measured(frame.first_frame_latency_ns);
        }
        if (palette_present) {
            resolvePending(&self.palette_pending_ns, &self.marks.command_palette_request_to_present_ns, frame.timestamp_ns);
        }
        if (terminal_present) {
            resolvePending(&self.terminal_pending_ns, &self.marks.terminal_panel_request_to_present_ns, frame.timestamp_ns);
        }
    }
};

fn readableNow(clock: native_sdk.Clock) ?u64 {
    const now = clock.monotonicNanoseconds();
    return if (now == 0) null else now;
}

fn elapsed(start_ns: u64, end_ns: u64) Measurement {
    if (start_ns == 0 or end_ns < start_ns) return .{};
    return Measurement.measured(end_ns - start_ns);
}

fn resolvePending(pending: *?u64, destination: *Measurement, frame_ns: u64) void {
    const start_ns = pending.* orelse return;
    if (frame_ns == 0 or frame_ns < start_ns) return;
    destination.* = Measurement.measured(frame_ns - start_ns);
    pending.* = null;
}

test "TestClock resolves interaction marks on a later presented frame" {
    var test_clock: native_sdk.TestClock = .{};
    test_clock.advanceMs(10);
    var timer = Timer.init(test_clock.clock(), test_clock.clock().monotonicNanoseconds());

    timer.requestCommandPalette();
    timer.requestTerminalPanel();
    test_clock.advanceMs(7);
    timer.observeFrame(.{
        .timestamp_ns = test_clock.clock().monotonicNanoseconds(),
        .first_frame_latency_ns = 3 * std.time.ns_per_ms,
        .nonblank = true,
    }, true, true);

    try std.testing.expectEqual(@as(u64, 7 * std.time.ns_per_ms), timer.marks.command_palette_request_to_present_ns.value_ns);
    try std.testing.expectEqual(@as(u64, 7 * std.time.ns_per_ms), timer.marks.terminal_panel_request_to_present_ns.value_ns);
    try std.testing.expectEqual(@as(u64, 7 * std.time.ns_per_ms), timer.marks.boot_to_first_observed_nonblank_ns.value_ns);
    try std.testing.expectEqual(@as(u64, 3 * std.time.ns_per_ms), timer.marks.sdk_first_frame_latency_ns.value_ns);
}

test "unsupported zero monotonic clock remains unavailable" {
    var test_clock: native_sdk.TestClock = .{};
    var timer = Timer.init(test_clock.clock(), 0);
    timer.requestCommandPalette();
    timer.markChromeCallback();
    timer.observeFrame(.{ .timestamp_ns = 0, .nonblank = true }, true, false);

    try std.testing.expect(!timer.marks.boot_to_first_chrome_callback_ns.available);
    try std.testing.expect(!timer.marks.boot_to_first_observed_nonblank_ns.available);
    try std.testing.expect(!timer.marks.command_palette_request_to_present_ns.available);
}
