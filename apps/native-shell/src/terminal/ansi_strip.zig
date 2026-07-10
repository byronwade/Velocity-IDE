//! Bounded, incremental ANSI escape-sequence stripper for the interactive
//! terminal panel.
//!
//! The terminal panel is a plain text view: it cannot render colors,
//! cursor addressing, or alternate screens (an honest v1 limitation). Raw
//! PTY output therefore has its escape sequences REMOVED before the bytes
//! reach the bounded scrollback ring — never interpreted, never buffered
//! unbounded, and never able to corrupt the ring: the stripper is a fixed
//! state machine whose only memory is one enum plus one counter, so
//! hostile or torn input degrades to visible printable garbage at worst.
//!
//! Handled:
//!   * CSI  (ESC '[' params/intermediates final)  — colors, cursor moves,
//!     erases, DEC private modes (`ESC [ ? 2004 h`), etc.
//!   * OSC  (ESC ']' ... BEL or ESC '\')          — titles, hyperlinks.
//!   * Other ESC sequences (charset designation `ESC ( B`, keypad modes,
//!     `ESC =`/`ESC >`; DCS/SOS/PM/APC are consumed like OSC).
//!   * C0 controls other than \n, \r, \t (BEL, backspace, ...) and DEL
//!     are dropped in ground state.
//!
//! Sequences may split across `data` events: the state persists between
//! `strip` calls. A sequence longer than `max_sequence_bytes` (corrupt or
//! hostile stream) force-resets to ground so output can never be eaten
//! forever.

const std = @import("std");

/// A legitimate OSC (window title, OSC 8 hyperlink) stays well under
/// this; anything longer is treated as a corrupt stream and abandoned.
pub const max_sequence_bytes: usize = 2048;

pub const State = enum {
    /// Plain output; printable bytes pass through.
    ground,
    /// Saw ESC; deciding the sequence kind (intermediates 0x20-0x2F keep
    /// us here until a final byte).
    esc,
    /// Inside CSI: parameter/intermediate bytes until a final 0x40-0x7E.
    csi,
    /// Inside an OSC/DCS/SOS/PM/APC string: consumed until BEL or ST.
    osc,
    /// Saw ESC inside the string: '\\' completes ST, anything else is
    /// still string content.
    osc_esc,
};

pub const Stripper = struct {
    state: State = .ground,
    /// Bytes consumed by the current sequence (bound enforcement).
    seq_len: usize = 0,
    /// Sequences abandoned because they exceeded `max_sequence_bytes`.
    /// Honest counter; the abandoned tail passes through ground filtering.
    overlong_sequences: u32 = 0,

    pub fn reset(self: *Stripper) void {
        self.state = .ground;
        self.seq_len = 0;
    }

    /// Filter one chunk. `out` must be at least `input.len` bytes (the
    /// output never grows). Returns the filtered slice into `out`.
    /// State persists across calls so split sequences strip correctly.
    pub fn strip(self: *Stripper, input: []const u8, out: []u8) []const u8 {
        std.debug.assert(out.len >= input.len);
        var n: usize = 0;
        for (input) |byte| {
            switch (self.state) {
                .ground => switch (byte) {
                    0x1b => self.enter(.esc),
                    '\n', '\r', '\t' => {
                        out[n] = byte;
                        n += 1;
                    },
                    // Remaining C0 controls (BEL, BS, VT, FF, ...) and DEL
                    // would render as garbage in a text view; drop them.
                    0x00...0x08, 0x0b...0x0c, 0x0e...0x1a, 0x1c...0x1f, 0x7f => {},
                    else => {
                        out[n] = byte;
                        n += 1;
                    },
                },
                .esc => {
                    if (!self.advance()) continue;
                    switch (byte) {
                        '[' => self.state = .csi,
                        // OSC and the other string introducers (DCS 'P',
                        // SOS 'X', PM '^', APC '_') all consume a string
                        // terminated by BEL or ST.
                        ']', 'P', 'X', '^', '_' => self.state = .osc,
                        0x1b => self.enter(.esc), // restart
                        // Intermediate bytes (e.g. the '(' of `ESC ( B`)
                        // keep the sequence open until a final byte.
                        0x20...0x2f => {},
                        // Any final byte (0x30-0x7E) ends a two/three-byte
                        // sequence; anything else is malformed — either
                        // way the sequence is over.
                        else => self.state = .ground,
                    }
                },
                .csi => {
                    if (!self.advance()) continue;
                    switch (byte) {
                        // Parameter and intermediate bytes.
                        0x20...0x3f => {},
                        // Final byte completes the sequence.
                        0x40...0x7e => self.state = .ground,
                        0x1b => self.enter(.esc),
                        // C0 inside CSI: real terminals execute it; keep
                        // line structure intact, drop the rest.
                        '\n', '\r', '\t' => {
                            out[n] = byte;
                            n += 1;
                        },
                        // Malformed (high-bit or other control) — abandon.
                        else => self.state = .ground,
                    }
                },
                .osc => {
                    if (!self.advance()) continue;
                    switch (byte) {
                        0x07 => self.state = .ground, // BEL terminator
                        0x1b => self.state = .osc_esc,
                        else => {},
                    }
                },
                .osc_esc => {
                    if (!self.advance()) continue;
                    switch (byte) {
                        '\\' => self.state = .ground, // ST (ESC \)
                        0x07 => self.state = .ground,
                        0x1b => {}, // still awaiting the ST backslash
                        else => self.state = .osc,
                    }
                },
            }
        }
        return out[0..n];
    }

    fn enter(self: *Stripper, state: State) void {
        self.state = state;
        self.seq_len = 0;
    }

    /// Count one sequence byte; on overflow abandon the sequence and
    /// report that the byte was NOT consumed by a sequence (it will be
    /// re-examined by ground on the next iteration? No — simpler: the
    /// byte is dropped with the sequence; only FUTURE bytes see ground).
    /// Returns false when the sequence was abandoned this byte.
    fn advance(self: *Stripper) bool {
        self.seq_len += 1;
        if (self.seq_len > max_sequence_bytes) {
            self.state = .ground;
            self.seq_len = 0;
            self.overlong_sequences += 1;
            return false;
        }
        return true;
    }
};

// ================================================================ tests

const testing = std.testing;

fn stripAll(input: []const u8, out: []u8) []const u8 {
    var stripper: Stripper = .{};
    return stripper.strip(input, out);
}

test "plain text passes through untouched" {
    var out: [128]u8 = undefined;
    try testing.expectEqualStrings("hello world\n", stripAll("hello world\n", &out));
    try testing.expectEqualStrings("tabs\tand\rreturns\n", stripAll("tabs\tand\rreturns\n", &out));
    try testing.expectEqualStrings("", stripAll("", &out));
}

test "SGR color sequences are removed" {
    var out: [128]u8 = undefined;
    try testing.expectEqualStrings(
        "error: bad\n",
        stripAll("\x1b[31merror:\x1b[0m bad\n", &out),
    );
    try testing.expectEqualStrings(
        "bold",
        stripAll("\x1b[1;38;5;208mbold\x1b[m", &out),
    );
}

test "cursor movement and erase sequences are removed" {
    var out: [128]u8 = undefined;
    try testing.expectEqualStrings("ab", stripAll("a\x1b[2J\x1b[H\x1b[10;20Hb", &out));
    try testing.expectEqualStrings("x", stripAll("\x1b[K\x1b[2K\x1b[1Ax", &out));
}

test "DEC private modes (bracketed paste) are removed" {
    var out: [128]u8 = undefined;
    try testing.expectEqualStrings("$ ", stripAll("\x1b[?2004h$ \x1b[?2004l", &out));
    try testing.expectEqualStrings("", stripAll("\x1b[?1049h\x1b[?25l", &out));
}

test "OSC title with BEL and with ST terminators" {
    var out: [128]u8 = undefined;
    try testing.expectEqualStrings("after", stripAll("\x1b]0;user@host: ~\x07after", &out));
    try testing.expectEqualStrings("after", stripAll("\x1b]2;title\x1b\\after", &out));
    // OSC 8 hyperlink wrapper vanishes, the link text stays.
    try testing.expectEqualStrings(
        "link",
        stripAll("\x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\", &out),
    );
}

test "charset designation and keypad mode sequences are removed" {
    var out: [128]u8 = undefined;
    try testing.expectEqualStrings("ok", stripAll("\x1b(Bok", &out));
    try testing.expectEqualStrings("ok", stripAll("\x1b=o\x1b>k", &out));
}

test "C0 controls other than newline, return, tab are dropped in ground" {
    var out: [128]u8 = undefined;
    try testing.expectEqualStrings("ab", stripAll("a\x07\x08b", &out)); // BEL, BS
    try testing.expectEqualStrings("ab\n", stripAll("a\x00\x01\x7fb\n", &out));
}

test "sequences split across chunks strip correctly" {
    var stripper: Stripper = .{};
    var out: [128]u8 = undefined;
    // CSI split mid-parameters.
    try testing.expectEqualStrings("a", stripper.strip("a\x1b[3", &out));
    try testing.expectEqualStrings("b", stripper.strip("1mb", &out));
    // OSC split before the terminator.
    try testing.expectEqualStrings("", stripper.strip("\x1b]0;half tit", &out));
    try testing.expectEqualStrings("c", stripper.strip("le\x07c", &out));
    // ESC as the last byte of a chunk.
    try testing.expectEqualStrings("d", stripper.strip("d\x1b", &out));
    try testing.expectEqualStrings("", stripper.strip("[0m", &out));
    try testing.expectEqual(State.ground, stripper.state);
}

test "newlines inside a torn CSI keep line structure" {
    var out: [128]u8 = undefined;
    try testing.expectEqualStrings("a\nb", stripAll("a\x1b[3\n1mb", &out));
}

test "overlong sequence is abandoned, never eats output forever" {
    var stripper: Stripper = .{};
    const junk_len = max_sequence_bytes + 64;
    var input: [junk_len + 8]u8 = undefined;
    input[0] = 0x1b;
    input[1] = ']';
    @memset(input[2 .. 2 + junk_len], 'x'); // unterminated OSC string
    @memcpy(input[2 + junk_len ..][0..6], "\nhello");
    var out: [input.len]u8 = undefined;
    const result = stripper.strip(input[0 .. 2 + junk_len + 6], &out);
    try testing.expectEqual(State.ground, stripper.state);
    try testing.expect(stripper.overlong_sequences == 1);
    // The post-abandon bytes flow through ground; the newline+text survive.
    try testing.expect(std.mem.endsWith(u8, result, "\nhello"));
}

test "high-bit bytes (UTF-8) pass through in ground and abort a CSI" {
    var out: [128]u8 = undefined;
    try testing.expectEqualStrings("héllo", stripAll("héllo", &out));
    // A malformed CSI interrupted by a high-bit byte abandons the
    // sequence; the byte itself is consumed with it.
    const result = stripAll("\x1b[3\xffplain", &out);
    try testing.expectEqualStrings("plain", result);
}

test "stripper state resets cleanly" {
    var stripper: Stripper = .{};
    var out: [16]u8 = undefined;
    _ = stripper.strip("\x1b]stuck", &out);
    try testing.expectEqual(State.osc, stripper.state);
    stripper.reset();
    try testing.expectEqualStrings("ok", stripper.strip("ok", &out));
}
