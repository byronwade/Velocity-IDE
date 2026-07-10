//! Velocity design tokens.
//! Precise, app-first palette — a neutral graphite foundation (cool, not warm)
//! with hairline borders and a single restrained indigo accent for primary
//! actions, focus, and selection. Tuned for a quiet, Linear-like desktop feel.
//! Original palette; no third-party brand assets or proprietary fonts.

const native_sdk = @import("native_sdk");
const canvas = native_sdk.canvas;
const Color = canvas.Color;

pub const ThemePreference = enum { dark, light, high_contrast };

/// Dark canvas: neutral graphite near-black with gently lifted surfaces and a
/// restrained indigo accent. Reads precise and app-like, never warm/decorative.
pub const dark_colors = canvas.ColorTokens{
    .background = Color.rgb8(14, 14, 17),
    .surface = Color.rgb8(21, 21, 25),
    .surface_subtle = Color.rgb8(30, 30, 35),
    .surface_pressed = Color.rgba8(255, 255, 255, 18),
    .text = Color.rgb8(236, 237, 241),
    .text_muted = Color.rgb8(138, 139, 150),
    .border = Color.rgba8(255, 255, 255, 20),
    .accent = Color.rgb8(94, 106, 210),
    .accent_text = Color.rgb8(247, 248, 252),
    .destructive = Color.rgb8(233, 90, 78),
    .destructive_text = Color.rgb8(250, 250, 252),
    .success = Color.rgb8(74, 190, 140),
    .success_text = Color.rgb8(14, 14, 17),
    .warning = Color.rgb8(224, 158, 82),
    .warning_text = Color.rgb8(22, 18, 12),
    .info = Color.rgb8(120, 148, 240),
    .info_text = Color.rgb8(14, 14, 17),
    .focus_ring = Color.rgb8(124, 136, 235),
    .shadow = Color.rgba8(0, 0, 0, 180),
    .scrim = Color.rgba8(6, 6, 9, 184),
    .disabled = Color.rgb8(44, 44, 50),
};

/// Light canvas: neutral off-white with graphite text, a cool hairline, and
/// the same indigo accent for continuity with the dark theme.
pub const light_colors = canvas.ColorTokens{
    .background = Color.rgb8(251, 251, 252),
    .surface = Color.rgb8(255, 255, 255),
    .surface_subtle = Color.rgb8(244, 244, 246),
    .surface_pressed = Color.rgb8(229, 229, 233),
    .text = Color.rgb8(24, 24, 28),
    .text_muted = Color.rgb8(112, 113, 122),
    .border = Color.rgb8(228, 228, 232),
    .accent = Color.rgb8(78, 90, 196),
    .accent_text = Color.rgb8(251, 251, 252),
    .destructive = Color.rgb8(204, 64, 52),
    .destructive_text = Color.rgb8(255, 255, 255),
    .success = Color.rgb8(24, 146, 100),
    .success_text = Color.rgb8(255, 255, 255),
    .warning = Color.rgb8(184, 120, 36),
    .warning_text = Color.rgb8(255, 255, 255),
    .info = Color.rgb8(48, 92, 208),
    .info_text = Color.rgb8(255, 255, 255),
    .focus_ring = Color.rgb8(108, 120, 224),
    .shadow = Color.rgba8(20, 22, 40, 26),
    .scrim = Color.rgba8(18, 20, 32, 44),
    .disabled = Color.rgb8(238, 238, 241),
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

    // Compact desktop-IDE density. Radii stay tight so the workbench never
    // reads bubbly: ~4px compact controls, ~6px fields/menus, ~8px floating
    // surfaces (cards use radius.lg, dialogs radius.xl). Nothing in the
    // chrome exceeds 8px.
    out.radius.sm = 4;
    out.radius.md = 6;
    out.radius.lg = 8;
    out.radius.xl = 8;

    // Legibility-first, quiet hierarchy: UI body ~13px, compact labels ~12px,
    // restrained section headings (no oversized display type in the shell).
    // Hierarchy comes from weight, opacity, and spacing — not giant text.
    out.typography.body_size = 13;
    out.typography.label_size = 12;
    out.typography.button_size = 13;
    out.typography.title_size = 16;
    out.typography.heading_size = 20;
    out.typography.display_size = 30;

    // One compact control-height register: sm 26 / default 30 / lg 34, so a
    // toolbar row of same-size controls lands on a single tight height.
    out.metrics.control_height_sm = 26;
    out.metrics.control_height = 30;
    out.metrics.control_height_lg = 34;

    out.pixel_snap = .{ .geometry = true, .text = true, .scale = 1 };
    return out;
}
