//! Velocity design tokens.
//! Inspired by modern agent-first / developer-dashboard precision (dark-first,
//! hairline borders, monochrome foundation) — original palette, no third-party
//! brand assets or proprietary fonts.

const native_sdk = @import("native_sdk");
const canvas = native_sdk.canvas;
const Color = canvas.Color;

pub const ThemePreference = enum { dark, light, high_contrast };

/// Dark canvas: #050505 / surfaces #0A0A0A / #111111 / #161616
pub const dark_colors = canvas.ColorTokens{
    .background = Color.rgb8(5, 5, 5),
    .surface = Color.rgb8(10, 10, 10),
    .surface_subtle = Color.rgb8(17, 17, 17),
    .surface_pressed = Color.rgba8(255, 255, 255, 28),
    .text = Color.rgb8(245, 245, 245),
    .text_muted = Color.rgb8(115, 115, 115),
    .border = Color.rgba8(255, 255, 255, 20),
    .accent = Color.rgb8(245, 245, 245),
    .accent_text = Color.rgb8(10, 10, 10),
    .destructive = Color.rgb8(239, 68, 68),
    .destructive_text = Color.rgb8(250, 250, 250),
    .success = Color.rgb8(34, 197, 94),
    .success_text = Color.rgb8(9, 9, 11),
    .warning = Color.rgb8(245, 158, 11),
    .warning_text = Color.rgb8(9, 9, 11),
    .info = Color.rgb8(59, 130, 246),
    .info_text = Color.rgb8(9, 9, 11),
    .focus_ring = Color.rgb8(161, 161, 161),
    .shadow = Color.rgba8(0, 0, 0, 160),
    .scrim = Color.rgba8(0, 0, 0, 140),
    .disabled = Color.rgb8(38, 38, 38),
};

pub const light_colors = canvas.ColorTokens{
    .background = Color.rgb8(250, 250, 250),
    .surface = Color.rgb8(255, 255, 255),
    .surface_subtle = Color.rgb8(245, 245, 245),
    .surface_pressed = Color.rgb8(229, 229, 229),
    .text = Color.rgb8(10, 10, 10),
    .text_muted = Color.rgb8(115, 115, 115),
    .border = Color.rgb8(229, 229, 229),
    .accent = Color.rgb8(23, 23, 23),
    .accent_text = Color.rgb8(250, 250, 250),
    .destructive = Color.rgb8(239, 68, 68),
    .destructive_text = Color.rgb8(250, 250, 250),
    .success = Color.rgb8(22, 163, 74),
    .success_text = Color.rgb8(250, 250, 250),
    .warning = Color.rgb8(217, 119, 6),
    .warning_text = Color.rgb8(250, 250, 250),
    .info = Color.rgb8(37, 99, 235),
    .info_text = Color.rgb8(250, 250, 250),
    .focus_ring = Color.rgb8(161, 161, 161),
    .shadow = Color.rgba8(0, 0, 0, 26),
    .scrim = Color.rgba8(0, 0, 0, 40),
    .disabled = Color.rgb8(245, 245, 245),
};

pub fn tokens(preference: ThemePreference, high_contrast: bool, reduce_motion: bool) canvas.DesignTokens {
    const scheme: native_sdk.ColorScheme = switch (preference) {
        .light => .light,
        .dark, .high_contrast => .dark,
    };
    var out = canvas.DesignTokens.theme(.{
        .color_scheme = switch (scheme) {
            .light => .light,
            .dark => .dark,
        },
        .contrast = if (high_contrast or preference == .high_contrast) .high else .standard,
        .reduce_motion = reduce_motion,
    });
    if (!(high_contrast or preference == .high_contrast)) {
        out.colors = switch (preference) {
            .light => light_colors,
            .dark, .high_contrast => dark_colors,
        };
    }
    // Compact IDE density
    out.radius = .{ .sm = 4, .md = 6, .lg = 8, .xl = 12 };
    out.pixel_snap = .{ .geometry = true, .text = true, .scale = 1 };
    return out;
}
