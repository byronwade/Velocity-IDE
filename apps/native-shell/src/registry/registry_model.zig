//! Registry preview model (stub). No network.

pub const RegistryItem = struct {
    id: []const u8,
    name: []const u8,
    publisher: []const u8,
    version: []const u8,
    trust_label: []const u8,
    safety_label: []const u8,
    performance_score: u8,
};

pub const preview_items = [_]RegistryItem{
    .{ .id = "velocity.core-files", .name = "Core Files", .publisher = "velocity", .version = "0.1.0", .trust_label = "trusted-core", .safety_label = "safe", .performance_score = 98 },
    .{ .id = "velocity.theme-pack", .name = "Theme Pack", .publisher = "velocity", .version = "0.1.0", .trust_label = "trusted-core", .safety_label = "safe", .performance_score = 99 },
};
