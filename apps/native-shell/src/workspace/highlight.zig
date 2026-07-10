//! Bounded, language-agnostic syntax tokenizer for the read-only editor view.
//!
//! The Native SDK's editable `<textarea>` cannot render monospace or colored
//! text, and markup colors are literal-only (never bound to model data). So the
//! highlighted editor is a read view: each line is lowered to a row of
//! monospace `<text>` runs whose color is chosen per token by a category
//! `<if>` chain in the markup. This module turns source text into those
//! per-token categories.
//!
//! Everything here is bounded: tokens are slices into the caller's source
//! buffer (no copies), the caller supplies fixed output storage, and the line
//! tokenizer never scans past the line it is given. Callers cap the number of
//! lines and tokens they materialize.

const std = @import("std");

/// A syntax category. Each maps to one design-token color in the markup:
/// keyword→accent, string→success, comment→text_muted, number→warning,
/// type_name→info, plain→text.
pub const Kind = enum(u8) {
    plain,
    keyword,
    string,
    comment,
    number,
    type_name,
};

/// One highlighted run. `text` is a slice of the source line (stable until the
/// document changes, at which point the caller re-tokenizes). `id` is assigned
/// by the caller for stable markup `for` keys.
pub const Token = struct {
    id: u32 = 0,
    text: []const u8 = "",
    kind: Kind = .plain,
};

/// One projected source line for the read view: a gutter label (line number),
/// the raw line text (a slice of the document), and a line-level color category.
///
/// Per-token coloring is not expressible in the Native SDK's declarative markup
/// (a `for` cannot iterate a scoped item's slice field, spans cannot be
/// `for`-generated, and colors are literal-only), so the read view colors whole
/// lines: full-line comments are dimmed, everything else is default text. The
/// per-token `Token`/`tokenizeLine` API below is retained for future use if the
/// SDK gains data-driven spans.
pub const Line = struct {
    id: u32 = 0,
    gutter: []const u8 = "",
    text: []const u8 = "",
    kind: Kind = .plain,
};

/// Classify a whole source line for read-view coloring. `in_block` carries
/// `/* ... */` state across lines. Returns `.comment` when the line is entirely
/// a comment (a `//`/`#` line comment, or any line inside a block comment),
/// otherwise `.plain`. Mixed code+trailing-comment lines stay `.plain`.
pub fn classifyLine(line: []const u8, in_block: *bool) Kind {
    if (in_block.*) {
        // Still inside a block comment; look for the closing */.
        var j: usize = 0;
        while (j + 1 < line.len) : (j += 1) {
            if (line[j] == '*' and line[j + 1] == '/') {
                in_block.* = false;
                break;
            }
        }
        return .comment;
    }
    var i: usize = 0;
    while (i < line.len and (line[i] == ' ' or line[i] == '\t' or line[i] == '\r')) i += 1;
    if (i >= line.len) return .plain;
    if (line[i] == '#') return .comment;
    if (i + 1 < line.len and line[i] == '/' and line[i + 1] == '/') return .comment;
    if (i + 1 < line.len and line[i] == '/' and line[i + 1] == '*') {
        // Opens a block comment; consume this line and set carry unless it
        // also closes on this same line.
        in_block.* = true;
        var j: usize = i + 2;
        while (j + 1 < line.len) : (j += 1) {
            if (line[j] == '*' and line[j + 1] == '/') {
                in_block.* = false;
                break;
            }
        }
        return .comment;
    }
    return .plain;
}

/// A blank placeholder so empty lines still occupy a row of height.
pub const blank_run: []const u8 = " ";

/// Common keywords across the languages Velocity is likely to open (JS/TS,
/// Zig, Rust, Go, Python, C-family). A shared set keeps the tokenizer language
/// agnostic without a per-language grammar.
pub const keywords = [_][]const u8{
    "const",  "let",      "var",       "function", "fn",       "return",
    "if",     "else",     "for",       "while",    "do",       "switch",
    "case",   "default",  "break",     "continue", "import",   "export",
    "from",   "as",       "class",     "struct",   "enum",     "union",
    "interface", "type",  "trait",     "impl",     "pub",      "priv",
    "async",  "await",    "try",       "catch",    "finally",  "throw",
    "new",    "delete",   "this",      "self",     "super",    "def",
    "lambda", "and",      "or",        "not",      "in",       "is",
    "true",   "false",    "null",      "nil",      "none",     "undefined",
    "void",   "match",    "where",     "with",     "yield",    "static",
    "public", "private",  "protected", "final",    "abstract", "extends",
    "implements", "package", "use",    "mod",      "namespace", "typedef",
    "comptime", "inline", "defer",     "errdefer", "test",     "unreachable",
    "orelse", "catch",    "and",       "or",
};

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isIdentStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_' or c == '$' or c == '@';
}

fn isIdentChar(c: u8) bool {
    return isIdentStart(c) or isDigit(c);
}

fn isUpper(c: u8) bool {
    return c >= 'A' and c <= 'Z';
}

fn isKeyword(word: []const u8) bool {
    for (keywords) |kw| {
        if (std.mem.eql(u8, word, kw)) return true;
    }
    return false;
}

/// Tokenize one source `line` into `out`, assigning ids from `base_id`. The
/// `in_block` flag carries a `/* ... */` block-comment state across lines and
/// is updated in place. Returns the number of tokens written (bounded by
/// `out.len`; any tail beyond capacity is dropped, keeping the pass bounded).
/// Concatenating the returned tokens' `text` reproduces the consumed prefix of
/// the line in order.
pub fn tokenizeLine(line: []const u8, in_block: *bool, out: []Token, base_id: u32) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < line.len and n < out.len) {
        const start = i;

        if (in_block.*) {
            while (i < line.len) {
                if (i + 1 < line.len and line[i] == '*' and line[i + 1] == '/') {
                    i += 2;
                    in_block.* = false;
                    break;
                }
                i += 1;
            }
            out[n] = .{ .id = base_id + @as(u32, @intCast(n)), .text = line[start..i], .kind = .comment };
            n += 1;
            continue;
        }

        const c = line[i];

        // Whitespace run.
        if (c == ' ' or c == '\t' or c == '\r') {
            while (i < line.len and (line[i] == ' ' or line[i] == '\t' or line[i] == '\r')) i += 1;
            out[n] = .{ .id = base_id + @as(u32, @intCast(n)), .text = line[start..i], .kind = .plain };
            n += 1;
            continue;
        }

        // Line comments: // and #.
        if ((c == '/' and i + 1 < line.len and line[i + 1] == '/') or c == '#') {
            i = line.len;
            out[n] = .{ .id = base_id + @as(u32, @intCast(n)), .text = line[start..i], .kind = .comment };
            n += 1;
            continue;
        }

        // Block comment start: /* ... (may close on this line or carry over).
        if (c == '/' and i + 1 < line.len and line[i + 1] == '*') {
            in_block.* = true;
            i += 2;
            while (i < line.len) {
                if (i + 1 < line.len and line[i] == '*' and line[i + 1] == '/') {
                    i += 2;
                    in_block.* = false;
                    break;
                }
                i += 1;
            }
            out[n] = .{ .id = base_id + @as(u32, @intCast(n)), .text = line[start..i], .kind = .comment };
            n += 1;
            continue;
        }

        // Strings: ", ', ` — honor backslash escapes; end at the quote or EOL.
        if (c == '"' or c == '\'' or c == '`') {
            const quote = c;
            i += 1;
            while (i < line.len) {
                if (line[i] == '\\') {
                    i = @min(i + 2, line.len);
                    continue;
                }
                if (line[i] == quote) {
                    i += 1;
                    break;
                }
                i += 1;
            }
            out[n] = .{ .id = base_id + @as(u32, @intCast(n)), .text = line[start..i], .kind = .string };
            n += 1;
            continue;
        }

        // Numbers (incl. hex/float chars once started).
        if (isDigit(c)) {
            while (i < line.len and (isDigit(line[i]) or line[i] == '.' or line[i] == '_' or
                (line[i] >= 'a' and line[i] <= 'f') or (line[i] >= 'A' and line[i] <= 'F') or
                line[i] == 'x' or line[i] == 'X' or line[i] == 'o' or line[i] == 'b')) i += 1;
            out[n] = .{ .id = base_id + @as(u32, @intCast(n)), .text = line[start..i], .kind = .number };
            n += 1;
            continue;
        }

        // Identifiers / keywords / types.
        if (isIdentStart(c)) {
            while (i < line.len and isIdentChar(line[i])) i += 1;
            const word = line[start..i];
            const kind: Kind = if (isKeyword(word))
                .keyword
            else if (word.len > 0 and isUpper(word[0]))
                .type_name
            else
                .plain;
            out[n] = .{ .id = base_id + @as(u32, @intCast(n)), .text = word, .kind = kind };
            n += 1;
            continue;
        }

        // Punctuation: one character as plain.
        i += 1;
        out[n] = .{ .id = base_id + @as(u32, @intCast(n)), .text = line[start..i], .kind = .plain };
        n += 1;
    }
    return n;
}

test "tokenizes a keyword, string, and comment" {
    var buf: [16]Token = undefined;
    var in_block = false;
    const n = tokenizeLine("const x = \"hi\"; // note", &in_block, &buf, 0);
    try std.testing.expect(n >= 5);
    try std.testing.expectEqual(Kind.keyword, buf[0].kind);
    try std.testing.expectEqualStrings("const", buf[0].text);
    var saw_string = false;
    var saw_comment = false;
    for (buf[0..n]) |t| {
        if (t.kind == .string) saw_string = true;
        if (t.kind == .comment) saw_comment = true;
    }
    try std.testing.expect(saw_string);
    try std.testing.expect(saw_comment);
    try std.testing.expect(!in_block);
}

test "block comment carries across lines" {
    var buf: [8]Token = undefined;
    var in_block = false;
    _ = tokenizeLine("/* start", &in_block, &buf, 0);
    try std.testing.expect(in_block);
    const n2 = tokenizeLine("still comment */ x", &in_block, &buf, 0);
    try std.testing.expect(!in_block);
    try std.testing.expectEqual(Kind.comment, buf[0].kind);
    try std.testing.expect(n2 >= 2);
}
