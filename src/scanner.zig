const std = @import("std");
const tables = @import("tables.zig");

pub inline fn findByte(noalias haystack: []const u8, start: usize, needle: u8) ?usize {
    const probe_end = @min(haystack.len, start + 32);
    var i = start;
    while (i + 8 <= probe_end) : (i += 8) {
        if (haystack[i] == needle) return i;
        if (haystack[i + 1] == needle) return i + 1;
        if (haystack[i + 2] == needle) return i + 2;
        if (haystack[i + 3] == needle) return i + 3;
        if (haystack[i + 4] == needle) return i + 4;
        if (haystack[i + 5] == needle) return i + 5;
        if (haystack[i + 6] == needle) return i + 6;
        if (haystack[i + 7] == needle) return i + 7;
    }
    while (i < probe_end) : (i += 1) {
        if (haystack[i] == needle) return i;
    }
    if (probe_end == haystack.len) {
        return null;
    }
    return std.mem.indexOfScalarPos(u8, haystack, probe_end, needle);
}

pub inline fn findNameEnd(noalias input: []const u8, start: usize) usize {
    var i = start;
    while (i + 8 <= input.len) : (i += 8) {
        if (!tables.NameCharTable[input[i]]) return i;
        if (!tables.NameCharTable[input[i + 1]]) return i + 1;
        if (!tables.NameCharTable[input[i + 2]]) return i + 2;
        if (!tables.NameCharTable[input[i + 3]]) return i + 3;
        if (!tables.NameCharTable[input[i + 4]]) return i + 4;
        if (!tables.NameCharTable[input[i + 5]]) return i + 5;
        if (!tables.NameCharTable[input[i + 6]]) return i + 6;
        if (!tables.NameCharTable[input[i + 7]]) return i + 7;
    }
    while (i < input.len and tables.NameCharTable[input[i]]) : (i += 1) {}
    return i;
}

pub inline fn findAttrUnquotedEnd(noalias input: []const u8, start: usize) usize {
    var i = start;
    while (i + 8 <= input.len) : (i += 8) {
        if (!tables.AttrUnquotedValueCharTable[input[i]]) return i;
        if (!tables.AttrUnquotedValueCharTable[input[i + 1]]) return i + 1;
        if (!tables.AttrUnquotedValueCharTable[input[i + 2]]) return i + 2;
        if (!tables.AttrUnquotedValueCharTable[input[i + 3]]) return i + 3;
        if (!tables.AttrUnquotedValueCharTable[input[i + 4]]) return i + 4;
        if (!tables.AttrUnquotedValueCharTable[input[i + 5]]) return i + 5;
        if (!tables.AttrUnquotedValueCharTable[input[i + 6]]) return i + 6;
        if (!tables.AttrUnquotedValueCharTable[input[i + 7]]) return i + 7;
    }
    while (i < input.len and tables.AttrUnquotedValueCharTable[input[i]]) : (i += 1) {}
    return i;
}

pub inline fn skipWhitespace(noalias input: []const u8, start: usize) usize {
    var i = start;
    while (i + 8 <= input.len) : (i += 8) {
        if (!tables.WhitespaceTable[input[i]]) return i;
        if (!tables.WhitespaceTable[input[i + 1]]) return i + 1;
        if (!tables.WhitespaceTable[input[i + 2]]) return i + 2;
        if (!tables.WhitespaceTable[input[i + 3]]) return i + 3;
        if (!tables.WhitespaceTable[input[i + 4]]) return i + 4;
        if (!tables.WhitespaceTable[input[i + 5]]) return i + 5;
        if (!tables.WhitespaceTable[input[i + 6]]) return i + 6;
        if (!tables.WhitespaceTable[input[i + 7]]) return i + 7;
    }
    while (i < input.len and tables.WhitespaceTable[input[i]]) : (i += 1) {}
    return i;
}

pub const TextRun = struct {
    lt_index: usize,
    has_non_whitespace: bool,
};

pub fn scanTextRun(hay: []const u8, start: usize) TextRun {
    if (start >= hay.len) return .{ .lt_index = hay.len, .has_non_whitespace = false };
    if (!tables.WhitespaceTable[hay[start]]) {
        return .{
            .lt_index = findByte(hay, start, '<') orelse hay.len,
            .has_non_whitespace = true,
        };
    }

    const lt_index = findByte(hay, start, '<') orelse hay.len;
    var i = start + 1;
    while (i < lt_index) : (i += 1) {
        if (!tables.WhitespaceTable[hay[i]]) {
            return .{ .lt_index = lt_index, .has_non_whitespace = true };
        }
    }
    return .{ .lt_index = lt_index, .has_non_whitespace = false };
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
    try std.testing.expectEqual(@as(usize, 4), skipWhitespace(" \n\t\tx", 0));
    try std.testing.expectEqual(@as(usize, 0), skipWhitespace("x", 0));
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
