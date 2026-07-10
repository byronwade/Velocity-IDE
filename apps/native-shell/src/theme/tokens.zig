//! Velocity design tokens.
//! Monochrome, editor-first palette — a neutral graphite foundation (near-equal
//! RGB, no warm or cold cast) with hairline borders and a single **electric
//! blue** brand signal used for the primary action, focus, and selection.
//! Everything else stays grayscale so the blue always reads as the one point of
//! emphasis. Original palette; no third-party brand assets or proprietary fonts.

const native_sdk = @import("native_sdk");
const canvas = native_sdk.canvas;
const Color = canvas.Color;

pub const ThemePreference = enum { dark, light, high_contrast };

/// Dark canvas: neutral graphite near-black with gently lifted surfaces for a
/// sense of depth. The one saturated hue is electric blue, reserved for the
/// primary action, focus ring, selection, and informational accents.
pub const dark_colors = canvas.ColorTokens{
    .background = Color.rgb8(13, 14, 16),
    .surface = Color.rgb8(19, 21, 24),
    .surface_subtle = Color.rgb8(27, 30, 34),
    .surface_pressed = Color.rgba8(255, 255, 255, 20),
    .text = Color.rgb8(234, 236, 240),
    .text_muted = Color.rgb8(139, 145, 154),
    .border = Color.rgba8(255, 255, 255, 23),
    // Electric blue brand signal.
    .accent = Color.rgb8(48, 128, 255),
    .accent_text = Color.rgb8(255, 255, 255),
    .destructive = Color.rgb8(235, 90, 78),
    .destructive_text = Color.rgb8(255, 255, 255),
    .success = Color.rgb8(64, 190, 132),
    .success_text = Color.rgb8(13, 14, 16),
    .warning = Color.rgb8(224, 158, 82),
    .warning_text = Color.rgb8(20, 16, 10),
    .info = Color.rgb8(90, 162, 255),
    .info_text = Color.rgb8(13, 14, 16),
    .focus_ring = Color.rgb8(90, 162, 255),
    .shadow = Color.rgba8(0, 0, 0, 180),
    .scrim = Color.rgba8(6, 8, 12, 184),
    .disabled = Color.rgb8(44, 47, 52),
};

/// Light canvas: neutral off-white paper with graphite text. Same electric blue
/// signal, deepened slightly for contrast against the light background.
pub const light_colors = canvas.ColorTokens{
    .background = Color.rgb8(249, 250, 251),
    .surface = Color.rgb8(255, 255, 255),
    .surface_subtle = Color.rgb8(240, 242, 245),
    .surface_pressed = Color.rgb8(226, 230, 236),
    .text = Color.rgb8(23, 26, 31),
    .text_muted = Color.rgb8(105, 112, 122),
    .border = Color.rgb8(223, 226, 231),
    // Electric blue brand signal (deepened for light backgrounds).
    .accent = Color.rgb8(20, 104, 240),
    .accent_text = Color.rgb8(255, 255, 255),
    .destructive = Color.rgb8(210, 58, 48),
    .destructive_text = Color.rgb8(255, 255, 255),
    .success = Color.rgb8(24, 150, 100),
    .success_text = Color.rgb8(255, 255, 255),
    .warning = Color.rgb8(184, 118, 32),
    .warning_text = Color.rgb8(255, 255, 255),
    .info = Color.rgb8(20, 104, 240),
    .info_text = Color.rgb8(255, 255, 255),
    .focus_ring = Color.rgb8(20, 104, 240),
    .shadow = Color.rgba8(20, 28, 42, 26),
    .scrim = Color.rgba8(18, 26, 40, 46),
    .disabled = Color.rgb8(237, 239, 243),
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
    // Precision Workbench radius policy: docked workbench panes are square
    // (they render as background fills with no exterior radius), compact
    // controls take a restrained 3–4 px, fields and menus 5 px, and floating
    // dialogs/overlays 6–8 px. Large radii are deliberately avoided so the
    // permanent chrome reads as one integrated instrument rather than a
    // collection of bubbly cards.
    out.radius = .{ .sm = 3, .md = 5, .lg = 6, .xl = 8 };
    out.pixel_snap = .{ .geometry = true, .text = true, .scale = 1 };
    return out;
}
