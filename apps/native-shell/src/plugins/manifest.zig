//! Plugin manifest draft types (stub). Full runtime lands later.

pub const PluginRuntime = enum { native, legacy_vsix };

pub const PluginManifest = struct {
    id: []const u8,
    name: []const u8,
    publisher: []const u8,
    version: []const u8,
    engine: []const u8 = "velocity@0.1",
    runtime: PluginRuntime = .native,
    activation: []const u8 = "onDemand",
    contributes: []const u8 = "",
    permissions: []const []const u8 = &.{},
    signature: []const u8 = "",
    repository: []const u8 = "",
    license: []const u8 = "MIT",
    performance_budget_ms: u32 = 50,
};
