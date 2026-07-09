//! Performance snapshot with explicit per-field availability.

const feature_profiler = @import("feature_profiler.zig");
const memory_sampler = @import("memory_sampler.zig");
const process_governor = @import("../processes/process_governor.zig");
const process_sampler = @import("process_sampler.zig");
const startup_timer = @import("startup_timer.zig");

pub const Metric = struct {
    value: u64 = 0,
    available: bool = false,

    pub fn measured(value: u64) Metric {
        return .{ .value = value, .available = true };
    }
};

pub const PerfSnapshot = struct {
    // External process launch timing requires an out-of-process harness.
    external_launch_to_window_ns: Metric = .{},
    // In-process boot origin to the first nonblank frame observed by on_frame.
    boot_to_first_observed_nonblank_ns: Metric = .{},
    // Native SDK surface-creation to first presented frame.
    sdk_first_frame_latency_ns: Metric = .{},
    // Chrome geometry callback, not proof that a window was visible.
    boot_to_first_chrome_callback_ns: Metric = .{},
    command_palette_request_to_present_ns: Metric = .{},
    terminal_panel_request_to_present_ns: Metric = .{},
    terminal_process_start_ns: Metric = .{},
    rss_bytes: Metric = .{},
    plugins_loaded: Metric = Metric.measured(0),
    features_registered: Metric = .{},
    features_enabled: Metric = .{},
    features_loaded: Metric = .{},
    governor_process_total: Metric = .{},
    governor_process_leaked: Metric = .{},
    governor_terminal_owned: Metric = .{},
    governor_task_owned: Metric = .{},
    governor_lsp_owned: Metric = .{},
    plugin_process_total: Metric = .{},
};

pub fn snapshot(
    marks: startup_timer.Marks,
    governor: *const process_governor.Governor,
) PerfSnapshot {
    const processes = process_sampler.sample(governor);
    const features = feature_profiler.sample();
    const memory = memory_sampler.sample();
    return .{
        .boot_to_first_observed_nonblank_ns = fromMeasurement(marks.boot_to_first_observed_nonblank_ns),
        .sdk_first_frame_latency_ns = fromMeasurement(marks.sdk_first_frame_latency_ns),
        .boot_to_first_chrome_callback_ns = fromMeasurement(marks.boot_to_first_chrome_callback_ns),
        .command_palette_request_to_present_ns = fromMeasurement(marks.command_palette_request_to_present_ns),
        .terminal_panel_request_to_present_ns = fromMeasurement(marks.terminal_panel_request_to_present_ns),
        .rss_bytes = if (memory.available) Metric.measured(memory.rss_bytes) else .{},
        .plugins_loaded = Metric.measured(0),
        .features_registered = Metric.measured(features.registered),
        .features_enabled = Metric.measured(features.enabled),
        .features_loaded = Metric.measured(features.loaded),
        .governor_process_total = Metric.measured(processes.total),
        .governor_process_leaked = Metric.measured(processes.leaked),
        .governor_terminal_owned = Metric.measured(processes.terminal_owned),
        .governor_task_owned = Metric.measured(processes.task_owned),
        .governor_lsp_owned = Metric.measured(processes.lsp_owned),
    };
}

fn fromMeasurement(value: startup_timer.Measurement) Metric {
    return if (value.available) Metric.measured(value.value_ns) else .{};
}

test "snapshot distinguishes measured zero from unavailable" {
    var governor: process_governor.Governor = .{};
    const result = snapshot(.{}, &governor);

    try @import("std").testing.expect(result.governor_process_total.available);
    try @import("std").testing.expectEqual(@as(u64, 0), result.governor_process_total.value);
    try @import("std").testing.expect(result.plugins_loaded.available);
    try @import("std").testing.expect(!result.rss_bytes.available);
    try @import("std").testing.expect(!result.plugin_process_total.available);
}
