//! Velocity design tokens.
//! Warm, clean, editor-first palette — a hand-tuned neutral foundation with a
//! subtle warm undertone (stone/sand rather than cold zinc), hairline borders,
//! monochrome primary, and a single restrained amber signal for focus and
//! selection. Original palette; no third-party brand assets or proprietary
//! fonts.

const native_sdk = @import("native_sdk");
const canvas = native_sdk.canvas;
const Color = canvas.Color;

pub const ThemePreference = enum { dark, light, high_contrast };

/// Dark canvas: warm near-black ("ink") with gently lifted surfaces for a
/// Cursor-like sense of depth, kept warm so it never reads blue or clinical.
pub const dark_colors = canvas.ColorTokens{
    .background = Color.rgb8(13, 12, 11),
    .surface = Color.rgb8(20, 18, 16),
    .surface_subtle = Color.rgb8(28, 25, 23),
    .surface_pressed = Color.rgba8(255, 246, 235, 20),
    .text = Color.rgb8(247, 244, 239),
    .text_muted = Color.rgb8(151, 143, 133),
    .border = Color.rgba8(255, 244, 230, 20),
    .accent = Color.rgb8(246, 243, 238),
    .accent_text = Color.rgb8(20, 17, 14),
    .destructive = Color.rgb8(233, 92, 78),
    .destructive_text = Color.rgb8(252, 248, 244),
    .success = Color.rgb8(78, 190, 130),
    .success_text = Color.rgb8(13, 12, 11),
    .warning = Color.rgb8(224, 158, 82),
    .warning_text = Color.rgb8(24, 18, 12),
    .info = Color.rgb8(126, 164, 244),
    .info_text = Color.rgb8(13, 12, 11),
    .focus_ring = Color.rgb8(219, 170, 108),
    .shadow = Color.rgba8(0, 0, 0, 170),
    .scrim = Color.rgba8(10, 8, 6, 178),
    .disabled = Color.rgb8(48, 44, 40),
};

/// Light canvas: warm paper — an off-white background with warm ink text,
/// soft warm shadows, and the same amber signal for continuity with dark.
pub const light_colors = canvas.ColorTokens{
    .background = Color.rgb8(250, 249, 246),
    .surface = Color.rgb8(255, 255, 253),
    .surface_subtle = Color.rgb8(244, 242, 237),
    .surface_pressed = Color.rgb8(232, 228, 220),
    .text = Color.rgb8(28, 25, 22),
    .text_muted = Color.rgb8(122, 114, 104),
    .border = Color.rgb8(232, 227, 218),
    .accent = Color.rgb8(28, 25, 22),
    .accent_text = Color.rgb8(250, 249, 246),
    .destructive = Color.rgb8(206, 68, 56),
    .destructive_text = Color.rgb8(255, 252, 249),
    .success = Color.rgb8(28, 148, 98),
    .success_text = Color.rgb8(255, 255, 253),
    .warning = Color.rgb8(190, 122, 38),
    .warning_text = Color.rgb8(255, 253, 249),
    .info = Color.rgb8(44, 98, 214),
    .info_text = Color.rgb8(255, 255, 253),
    .focus_ring = Color.rgb8(198, 146, 84),
    .shadow = Color.rgba8(60, 50, 38, 28),
    .scrim = Color.rgba8(40, 32, 24, 44),
    .disabled = Color.rgb8(240, 237, 230),
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
