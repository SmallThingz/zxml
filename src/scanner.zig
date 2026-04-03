const std = @import("std");
const tables = @import("tables.zig");

pub inline fn findByte(noalias haystack: []const u8, start: usize, needle: u8) ?usize {
    if (haystack.len -| start < 32) {
        var i = start;
        while (i < haystack.len) : (i += 1) {
            if (haystack[i] == needle) return i;
        }
        return null;
    }
    return std.mem.indexOfScalarPos(u8, haystack, start, needle);
}

pub inline fn findNameEnd(noalias input: []const u8, start: usize) usize {
    var i = start;
    while (i < input.len and tables.isNameChar(input[i])) : (i += 1) {}
    return i;
}

pub inline fn findAttrUnquotedEnd(noalias input: []const u8, start: usize) usize {
    var i = start;
    while (i < input.len and tables.isAttrUnquotedValueChar(input[i])) : (i += 1) {}
    return i;
}

pub const TextRun = struct {
    lt_index: usize,
    has_non_whitespace: bool,
};

pub fn scanTextRun(hay: []const u8, start: usize) TextRun {
    // Scan until the next `<` while cheaply tracking whether the span contains
    // anything other than XML whitespace, which lets the parser skip
    // whitespace-only text nodes in the hot path.
    if (start >= hay.len) return .{ .lt_index = hay.len, .has_non_whitespace = false };

    var i = start;
    var has_non_whitespace = false;
    const remaining = hay.len - start;

    if (remaining < 64) {
        while (i < hay.len and hay[i] != '<') : (i += 1) {
            if (!tables.WhitespaceTable[hay[i]]) has_non_whitespace = true;
        }
        return .{ .lt_index = i, .has_non_whitespace = has_non_whitespace };
    }

    if (!@inComptime()) {
        if (std.simd.suggestVectorLength(u8)) |block_len| {
            const Block = @Vector(block_len, u8);
            const lt_mask: Block = @splat('<');
            const sp_mask: Block = @splat(' ');
            const nl_mask: Block = @splat('\n');
            const cr_mask: Block = @splat('\r');
            const tab_mask: Block = @splat('\t');

            while (i + block_len <= hay.len) : (i += block_len) {
                const block: Block = hay[i..][0..block_len].*;
                const lt_hits = block == lt_mask;
                if (@reduce(.Or, lt_hits)) {
                    const first_lt = std.simd.firstTrue(lt_hits).?;
                    var j: usize = 0;
                    while (j < first_lt) : (j += 1) {
                        if (!tables.WhitespaceTable[hay[i + j]]) {
                            return .{ .lt_index = i + first_lt, .has_non_whitespace = true };
                        }
                    }
                    return .{ .lt_index = i + first_lt, .has_non_whitespace = has_non_whitespace };
                }

                const ws_hits = (block == sp_mask) |
                    (block == nl_mask) |
                    (block == cr_mask) |
                    (block == tab_mask);
                if (!@reduce(.And, ws_hits)) has_non_whitespace = true;
            }
        }
    }

    while (i < hay.len and hay[i] != '<') : (i += 1) {
        if (!tables.WhitespaceTable[hay[i]]) has_non_whitespace = true;
    }
    return .{ .lt_index = i, .has_non_whitespace = has_non_whitespace };
}

pub fn findSequence(noalias haystack: []const u8, start: usize, noalias needle: []const u8) ?usize {
    if (start >= haystack.len) return null;
    if (needle.len == 0) return start;
    if (needle.len == 1) return findByte(haystack, start, needle[0]);

    if (needle.len == 2) {
        var i = start;
        while (true) {
            const p = findByte(haystack, i, needle[0]) orelse return null;
            if (p + 1 < haystack.len and haystack[p + 1] == needle[1]) return p;
            i = p + 1;
        }
    }

    if (needle.len == 3) {
        var i = start;
        while (true) {
            const p = findByte(haystack, i, needle[0]) orelse return null;
            if (p + 2 < haystack.len and haystack[p + 1] == needle[1] and haystack[p + 2] == needle[2]) return p;
            i = p + 1;
        }
    }

    return std.mem.indexOfPos(u8, haystack, start, needle);
}

test "findByte and findSequence locate delimiters" {
    try std.testing.expectEqual(@as(?usize, 3), findByte("abc<def", 0, '<'));
    try std.testing.expectEqual(@as(?usize, null), findByte("abc", 9, '<'));
    try std.testing.expectEqual(@as(?usize, 3), findSequence("abc?def", 0, "?"));
    try std.testing.expectEqual(@as(?usize, 3), findSequence("abc?>def", 0, "?>"));
    try std.testing.expectEqual(@as(?usize, 3), findSequence("abc]]>def", 0, "]]>"));
    try std.testing.expectEqual(@as(?usize, 3), findSequence("abcqrstdef", 0, "qrst"));
    try std.testing.expectEqual(@as(?usize, null), findSequence("abcdef", 0, "?>"));
    try std.testing.expectEqual(@as(?usize, null), findSequence("abcdef", 9, "x"));
}

test "name and attribute scanners stop at the right boundary" {
    try std.testing.expectEqual(@as(usize, 6), findNameEnd("node-1 x", 0));
    try std.testing.expectEqual(@as(usize, 6), findAttrUnquotedEnd("value/>", 0));
    try std.testing.expectEqual(@as(usize, 0), findNameEnd(" x", 0));
    try std.testing.expectEqual(@as(usize, 0), findAttrUnquotedEnd(" value", 0));
}

test "scanTextRun tracks non-whitespace text" {
    const ws = scanTextRun("  \n\t<r/>", 0);
    try std.testing.expectEqual(@as(usize, 4), ws.lt_index);
    try std.testing.expect(!ws.has_non_whitespace);

    const txt = scanTextRun(" hi<r/>", 0);
    try std.testing.expectEqual(@as(usize, 3), txt.lt_index);
    try std.testing.expect(txt.has_non_whitespace);

    const end = scanTextRun("abc", 3);
    try std.testing.expectEqual(@as(usize, 3), end.lt_index);
    try std.testing.expect(!end.has_non_whitespace);
}
