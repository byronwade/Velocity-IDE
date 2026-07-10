//! Canonical language registry: one bounded comptime table mapping files to
//! everything the shell knows about a language — display name, LSP
//! languageId, comment syntax, bracket pairs, indent hints, and (future)
//! formatter / language-server candidates. Editor chrome, transforms, and
//! the LSP client all read this table so no subsystem grows its own
//! extension switch. Adding a language is one table entry.

const std = @import("std");

pub const LanguageSpec = struct {
    /// LSP languageId (didOpen) and stable internal key.
    id: []const u8,
    /// Status-bar display name (exact strings are asserted by tests).
    display_name: []const u8,
    extensions: []const []const u8 = &.{},
    /// Exact basenames (Makefile, Dockerfile, ...) matched before extensions.
    filenames: []const []const u8 = &.{},
    line_comment: []const u8 = "// ",
    block_comment_open: []const u8 = "",
    block_comment_close: []const u8 = "",
    bracket_pairs: []const [2]u8 = &.{ .{ '(', ')' }, .{ '[', ']' }, .{ '{', '}' } },
    indent_size_hint: u8 = 2,
    /// argv[0] candidates, first available wins. Consulted on demand only.
    formatter_candidates: []const []const u8 = &.{},
    server_candidates: []const []const u8 = &.{},
};

pub const plain_text = LanguageSpec{
    .id = "plaintext",
    .display_name = "Plain Text",
    .line_comment = "",
    .bracket_pairs = &.{},
};

/// Priority languages per the roadmap (Zig, JS/TS, JSON, HTML, CSS,
/// Markdown) plus the extensions the shell already recognized.
pub const languages = [_]LanguageSpec{
    .{
        .id = "zig",
        .display_name = "Zig",
        .extensions = &.{".zig"},
        .indent_size_hint = 4,
        .formatter_candidates = &.{"zig"},
        .server_candidates = &.{"zls"},
    },
    .{
        .id = "typescriptreact",
        .display_name = "TypeScript React",
        .extensions = &.{".tsx"},
        .server_candidates = &.{"typescript-language-server"},
    },
    .{
        .id = "typescript",
        .display_name = "TypeScript",
        .extensions = &.{".ts"},
        .server_candidates = &.{"typescript-language-server"},
    },
    .{
        .id = "javascriptreact",
        .display_name = "JavaScript React",
        .extensions = &.{".jsx"},
        .server_candidates = &.{"typescript-language-server"},
    },
    .{
        .id = "javascript",
        .display_name = "JavaScript",
        .extensions = &.{ ".js", ".mjs", ".cjs" },
        .server_candidates = &.{"typescript-language-server"},
    },
    .{
        .id = "json",
        .display_name = "JSON",
        .extensions = &.{ ".json", ".jsonc" },
        .line_comment = "",
    },
    .{
        .id = "markdown",
        .display_name = "Markdown",
        .extensions = &.{ ".md", ".markdown" },
        .line_comment = "",
        .block_comment_open = "<!-- ",
        .block_comment_close = " -->",
        .bracket_pairs = &.{},
    },
    .{
        .id = "css",
        .display_name = "CSS",
        .extensions = &.{".css"},
        .line_comment = "",
        .block_comment_open = "/* ",
        .block_comment_close = " */",
    },
    .{
        .id = "html",
        .display_name = "HTML",
        .extensions = &.{ ".html", ".htm", ".xml", ".svg" },
        .line_comment = "",
        .block_comment_open = "<!-- ",
        .block_comment_close = " -->",
    },
    .{
        .id = "rust",
        .display_name = "Rust",
        .extensions = &.{".rs"},
        .indent_size_hint = 4,
        .server_candidates = &.{"rust-analyzer"},
    },
    .{
        .id = "python",
        .display_name = "Python",
        .extensions = &.{".py"},
        .line_comment = "# ",
        .indent_size_hint = 4,
    },
    .{
        .id = "go",
        .display_name = "Go",
        .extensions = &.{".go"},
        .indent_size_hint = 4,
        .formatter_candidates = &.{"gofmt"},
        .server_candidates = &.{"gopls"},
    },
    .{
        .id = "shellscript",
        .display_name = "Shell Script",
        .extensions = &.{ ".sh", ".bash" },
        .line_comment = "# ",
    },
    .{
        .id = "yaml",
        .display_name = "YAML",
        .extensions = &.{ ".yaml", ".yml" },
        .line_comment = "# ",
    },
    .{
        .id = "toml",
        .display_name = "TOML",
        .extensions = &.{".toml"},
        .line_comment = "# ",
    },
    .{
        .id = "makefile",
        .display_name = "Makefile",
        .filenames = &.{ "Makefile", "makefile", "GNUmakefile" },
        .line_comment = "# ",
        .indent_size_hint = 4,
    },
    .{
        .id = "dockerfile",
        .display_name = "Dockerfile",
        .filenames = &.{"Dockerfile"},
        .line_comment = "# ",
    },
};

fn baseName(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |i| return path[i + 1 ..];
    return path;
}

/// Filename match first, then longest-extension match, else plain text.
pub fn specForPath(path: []const u8) *const LanguageSpec {
    const name = baseName(path);
    for (&languages) |*spec| {
        for (spec.filenames) |filename| {
            if (std.mem.eql(u8, name, filename)) return spec;
        }
    }
    for (&languages) |*spec| {
        for (spec.extensions) |ext| {
            if (std.mem.endsWith(u8, name, ext)) return spec;
        }
    }
    return &plain_text;
}

pub fn displayNameForPath(path: []const u8) []const u8 {
    return specForPath(path).display_name;
}

/// Line-comment prefix for toggle-comment; falls back to the block-comment
/// opener for languages without line comments, then to C-style.
pub fn commentPrefixForPath(path: []const u8) []const u8 {
    const spec = specForPath(path);
    if (spec.line_comment.len > 0) return spec.line_comment;
    if (spec.block_comment_open.len > 0) return spec.block_comment_open;
    return "// ";
}

test "extension lookup preserves the shell's display names" {
    try std.testing.expectEqualStrings("TypeScript React", displayNameForPath("src/components/Chart.tsx"));
    try std.testing.expectEqualStrings("TypeScript", displayNameForPath("src/lib/db.ts"));
    try std.testing.expectEqualStrings("JavaScript React", displayNameForPath("app.jsx"));
    try std.testing.expectEqualStrings("JavaScript", displayNameForPath("index.js"));
    try std.testing.expectEqualStrings("JSON", displayNameForPath("package.json"));
    try std.testing.expectEqualStrings("Markdown", displayNameForPath("README.md"));
    try std.testing.expectEqualStrings("CSS", displayNameForPath("style.css"));
    try std.testing.expectEqualStrings("HTML", displayNameForPath("index.html"));
    try std.testing.expectEqualStrings("Zig", displayNameForPath("src/main.zig"));
    try std.testing.expectEqualStrings("Rust", displayNameForPath("lib.rs"));
    try std.testing.expectEqualStrings("Python", displayNameForPath("tool.py"));
    try std.testing.expectEqualStrings("Go", displayNameForPath("main.go"));
    try std.testing.expectEqualStrings("Plain Text", displayNameForPath("LICENSE"));
    try std.testing.expectEqualStrings("Plain Text", displayNameForPath("notes.txt"));
}

test "filename entries win over extensions and default" {
    try std.testing.expectEqualStrings("Makefile", displayNameForPath("Makefile"));
    try std.testing.expectEqualStrings("Makefile", displayNameForPath("sub/dir/Makefile"));
    try std.testing.expectEqualStrings("Dockerfile", displayNameForPath("Dockerfile"));
}

test "lsp language ids and server candidates are wired for the first slice" {
    const ts = specForPath("a.ts");
    try std.testing.expectEqualStrings("typescript", ts.id);
    try std.testing.expectEqualStrings("typescript-language-server", ts.server_candidates[0]);
    const zig_spec = specForPath("a.zig");
    try std.testing.expectEqualStrings("zig", zig_spec.id);
    try std.testing.expectEqualStrings("zls", zig_spec.server_candidates[0]);
    try std.testing.expectEqual(@as(usize, 0), specForPath("x.txt").server_candidates.len);
}

test "comment prefixes match transform expectations" {
    try std.testing.expectEqualStrings("// ", commentPrefixForPath("main.zig"));
    try std.testing.expectEqualStrings("// ", commentPrefixForPath("app.tsx"));
    try std.testing.expectEqualStrings("# ", commentPrefixForPath("tool.py"));
    try std.testing.expectEqualStrings("# ", commentPrefixForPath("conf.yaml"));
    try std.testing.expectEqualStrings("# ", commentPrefixForPath("Cargo.toml"));
    try std.testing.expectEqualStrings("<!-- ", commentPrefixForPath("index.html"));
    try std.testing.expectEqualStrings("<!-- ", commentPrefixForPath("icon.svg"));
    // No line-comment concept: JSON and plain text fall back to C-style,
    // matching the transform's historical default.
    try std.testing.expectEqualStrings("// ", commentPrefixForPath("package.json"));
    try std.testing.expectEqualStrings("// ", commentPrefixForPath("notes.txt"));
}
