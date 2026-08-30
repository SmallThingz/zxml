const std = @import("std");
const builtin = @import("builtin");
const tables = @import("tables.zig");

const byte_scan_vector_len: comptime_int = switch (builtin.cpu.arch) {
    .x86, .x86_64 => if (std.Target.x86.featureSetHas(builtin.cpu.features, .avx2)) 32 else 16,
    else => 16,
};

pub inline fn findByte(noalias haystack: []const u8, start: usize, needle: u8) ?usize {
    if (start >= haystack.len) {
        @branchHint(.unlikely);
        return null;
    }
    const probe_end = start + @min(haystack.len - start, 32);
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
    if (probe_end == haystack.len) return null;
    return std.mem.indexOfScalarPos(u8, haystack, probe_end, needle);
}

pub const BytePairPresence = struct {
    first: bool = false,
    second: bool = false,
};

pub inline fn bytePairPresence(noalias haystack: []const u8, comptime first: u8, comptime second: u8) BytePairPresence {
    comptime std.debug.assert(first != second);
    const Vec = @Vector(byte_scan_vector_len, u8);
    const first_vec: Vec = @splat(first);
    const second_vec: Vec = @splat(second);

    var result: BytePairPresence = .{};
    var i: usize = 0;
    while (i + @sizeOf(Vec) <= haystack.len) : (i += @sizeOf(Vec)) {
        const bytes: Vec = haystack[i..][0..@sizeOf(Vec)].*;
        result.first = result.first or @reduce(.Or, bytes == first_vec);
        result.second = result.second or @reduce(.Or, bytes == second_vec);
        if (result.first and result.second) return result;
    }
    for (haystack[i..]) |c| {
        result.first = result.first or c == first;
        result.second = result.second or c == second;
    }
    return result;
}

pub const QuotedValueScan = struct {
    end: usize,
    has_lt: bool = false,
    has_ampersand: bool = false,
};

/// Finds a quoted attribute value's closing quote while collecting the two
/// strict-mode sentinels that otherwise require a second pass over the value.
pub inline fn scanQuotedValueSpecials(noalias hay: []const u8, start: usize, quote: u8) QuotedValueScan {
    std.debug.assert(quote == '\'' or quote == '"');
    if (start >= hay.len) return .{ .end = hay.len };

    var result: QuotedValueScan = .{ .end = hay.len };
    const probe_end = start + @min(hay.len - start, 32);
    var i = start;
    while (i + 8 <= probe_end) : (i += 8) {
        inline for (0..8) |n| {
            const c = hay[i + n];
            if (c == quote) {
                result.end = i + n;
                return result;
            }
            result.has_lt = result.has_lt or c == '<';
            result.has_ampersand = result.has_ampersand or c == '&';
        }
    }
    while (i < probe_end) : (i += 1) {
        const c = hay[i];
        if (c == quote) {
            result.end = i;
            return result;
        }
        result.has_lt = result.has_lt or c == '<';
        result.has_ampersand = result.has_ampersand or c == '&';
    }
    if (probe_end == hay.len) return result;

    const Vec = @Vector(byte_scan_vector_len, u8);
    const quote_vec: Vec = @splat(quote);
    const lt_vec: Vec = @splat('<');
    const amp_vec: Vec = @splat('&');
    i = probe_end;
    while (i + @sizeOf(Vec) <= hay.len) : (i += @sizeOf(Vec)) {
        const bytes: Vec = hay[i..][0..@sizeOf(Vec)].*;
        if (@reduce(.Or, bytes == quote_vec)) {
            const end = i + @sizeOf(Vec);
            while (i < end) : (i += 1) {
                const c = hay[i];
                if (c == quote) {
                    result.end = i;
                    return result;
                }
                result.has_lt = result.has_lt or c == '<';
                result.has_ampersand = result.has_ampersand or c == '&';
            }
            unreachable;
        }
        result.has_lt = result.has_lt or @reduce(.Or, bytes == lt_vec);
        result.has_ampersand = result.has_ampersand or @reduce(.Or, bytes == amp_vec);
    }
    while (i < hay.len) : (i += 1) {
        const c = hay[i];
        if (c == quote) {
            result.end = i;
            return result;
        }
        result.has_lt = result.has_lt or c == '<';
        result.has_ampersand = result.has_ampersand or c == '&';
    }
    return result;
}

pub const NameScan = struct {
    end: usize,
    key: u64,
    needs_unicode_validation: bool = false,
};

pub const NameEndScan = struct {
    end: usize,
    needs_unicode_validation: bool,
};

pub inline fn prefixKey(input: []const u8) u64 {
    return switch (input.len) {
        0 => 0,
        1 => @as(u64, input[0]),
        2 => @as(u64, input[0]) |
            (@as(u64, input[1]) << 8),
        3 => @as(u64, input[0]) |
            (@as(u64, input[1]) << 8) |
            (@as(u64, input[2]) << 16),
        4 => @as(u64, std.mem.readInt(u32, input[0..4], .little)),
        5 => @as(u64, std.mem.readInt(u32, input[0..4], .little)) |
            (@as(u64, input[4]) << 32),
        6 => @as(u64, std.mem.readInt(u32, input[0..4], .little)) |
            (@as(u64, input[4]) << 32) |
            (@as(u64, input[5]) << 40),
        7 => @as(u64, std.mem.readInt(u32, input[0..4], .little)) |
            (@as(u64, input[4]) << 32) |
            (@as(u64, input[5]) << 40) |
            (@as(u64, input[6]) << 48),
        else => std.mem.readInt(u64, input[0..8], .little),
    };
}

pub inline fn scanNameAndKey(input: []const u8, start: usize) NameScan {
    var i = start;
    var key: u64 = 0;
    var high_bits: u8 = 0;
    inline for (0..8) |n| {
        if (i >= input.len or !tables.NameCharTable[input[i]]) return .{
            .end = i,
            .key = key,
            .needs_unicode_validation = (high_bits & 0x80) != 0,
        };
        const c = input[i];
        high_bits |= c;
        key |= @as(u64, c) << @intCast(n * 8);
        i += 1;
    }
    const tail = scanNameEnd(input, i);
    return .{
        .end = tail.end,
        .key = key,
        .needs_unicode_validation = (high_bits & 0x80) != 0 or tail.needs_unicode_validation,
    };
}

pub inline fn scanNameAndKeyAfterStart(input: []const u8, start: usize) NameScan {
    std.debug.assert(start < input.len and tables.NameCharTable[input[start]]);
    var i = start + 1;
    var key: u64 = input[start];
    var high_bits: u8 = input[start];
    inline for (1..8) |n| {
        if (i >= input.len or !tables.NameCharTable[input[i]]) return .{
            .end = i,
            .key = key,
            .needs_unicode_validation = (high_bits & 0x80) != 0,
        };
        const c = input[i];
        high_bits |= c;
        key |= @as(u64, c) << @intCast(n * 8);
        i += 1;
    }
    const tail = scanNameEnd(input, i);
    return .{
        .end = tail.end,
        .key = key,
        .needs_unicode_validation = (high_bits & 0x80) != 0 or tail.needs_unicode_validation,
    };
}

pub inline fn scanNameEndAfterStart(noalias input: []const u8, start: usize) NameEndScan {
    std.debug.assert(start < input.len and tables.NameCharTable[input[start]]);
    const tail = scanNameEnd(input, start + 1);
    return .{
        .end = tail.end,
        .needs_unicode_validation = input[start] >= 0x80 or tail.needs_unicode_validation,
    };
}

pub inline fn findNameEndAfterStart(noalias input: []const u8, start: usize) usize {
    std.debug.assert(start < input.len and tables.NameCharTable[input[start]]);
    return findNameEnd(input, start + 1);
}

pub inline fn scanNameEnd(noalias input: []const u8, start: usize) NameEndScan {
    var i = start;
    var high_bits: u8 = 0;
    while (i + 8 <= input.len) : (i += 8) {
        const c0 = input[i];
        if (!tables.NameCharTable[c0]) return .{ .end = i, .needs_unicode_validation = (high_bits & 0x80) != 0 };
        const c1 = input[i + 1];
        if (!tables.NameCharTable[c1]) return .{ .end = i + 1, .needs_unicode_validation = ((high_bits | c0) & 0x80) != 0 };
        const c2 = input[i + 2];
        if (!tables.NameCharTable[c2]) return .{ .end = i + 2, .needs_unicode_validation = ((high_bits | c0 | c1) & 0x80) != 0 };
        const c3 = input[i + 3];
        if (!tables.NameCharTable[c3]) return .{ .end = i + 3, .needs_unicode_validation = ((high_bits | c0 | c1 | c2) & 0x80) != 0 };
        const c4 = input[i + 4];
        if (!tables.NameCharTable[c4]) return .{ .end = i + 4, .needs_unicode_validation = ((high_bits | c0 | c1 | c2 | c3) & 0x80) != 0 };
        const c5 = input[i + 5];
        if (!tables.NameCharTable[c5]) return .{ .end = i + 5, .needs_unicode_validation = ((high_bits | c0 | c1 | c2 | c3 | c4) & 0x80) != 0 };
        const c6 = input[i + 6];
        if (!tables.NameCharTable[c6]) return .{ .end = i + 6, .needs_unicode_validation = ((high_bits | c0 | c1 | c2 | c3 | c4 | c5) & 0x80) != 0 };
        const c7 = input[i + 7];
        if (!tables.NameCharTable[c7]) return .{ .end = i + 7, .needs_unicode_validation = ((high_bits | c0 | c1 | c2 | c3 | c4 | c5 | c6) & 0x80) != 0 };
        high_bits |= c0 | c1 | c2 | c3 | c4 | c5 | c6 | c7;
    }
    while (i < input.len and tables.NameCharTable[input[i]]) : (i += 1) {
        high_bits |= input[i];
    }
    return .{ .end = i, .needs_unicode_validation = (high_bits & 0x80) != 0 };
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

pub const TextSpecialRun = struct {
    lt_index: usize,
    has_close_bracket: bool = false,
    has_ampersand: bool = false,
};

/// Scans character data once for its end and the two strict-mode sentinels.
/// The short scalar probe keeps tiny text nodes cheap; long runs use SIMD.
pub inline fn scanTextSpecials(noalias hay: []const u8, start: usize) TextSpecialRun {
    if (start >= hay.len) return .{ .lt_index = hay.len };

    var result: TextSpecialRun = .{ .lt_index = hay.len };
    const probe_end = start + @min(hay.len - start, 32);
    var i = start;
    while (i + 8 <= probe_end) : (i += 8) {
        inline for (0..8) |n| {
            const c = hay[i + n];
            if (c == '<') {
                result.lt_index = i + n;
                return result;
            }
            result.has_close_bracket = result.has_close_bracket or c == ']';
            result.has_ampersand = result.has_ampersand or c == '&';
        }
    }
    while (i < probe_end) : (i += 1) {
        const c = hay[i];
        if (c == '<') {
            result.lt_index = i;
            return result;
        }
        result.has_close_bracket = result.has_close_bracket or c == ']';
        result.has_ampersand = result.has_ampersand or c == '&';
    }
    if (probe_end == hay.len) return result;

    const Vec = @Vector(byte_scan_vector_len, u8);
    const lt_vec: Vec = @splat('<');
    const close_vec: Vec = @splat(']');
    const amp_vec: Vec = @splat('&');
    i = probe_end;
    while (i + @sizeOf(Vec) <= hay.len) : (i += @sizeOf(Vec)) {
        const bytes: Vec = hay[i..][0..@sizeOf(Vec)].*;
        if (@reduce(.Or, bytes == lt_vec)) {
            const end = i + @sizeOf(Vec);
            while (i < end) : (i += 1) {
                const c = hay[i];
                if (c == '<') {
                    result.lt_index = i;
                    return result;
                }
                result.has_close_bracket = result.has_close_bracket or c == ']';
                result.has_ampersand = result.has_ampersand or c == '&';
            }
            unreachable;
        }
        result.has_close_bracket = result.has_close_bracket or @reduce(.Or, bytes == close_vec);
        result.has_ampersand = result.has_ampersand or @reduce(.Or, bytes == amp_vec);
    }
    while (i < hay.len) : (i += 1) {
        const c = hay[i];
        if (c == '<') {
            result.lt_index = i;
            return result;
        }
        result.has_close_bracket = result.has_close_bracket or c == ']';
        result.has_ampersand = result.has_ampersand or c == '&';
    }
    return result;
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

pub fn scanTextRunStrict(hay: []const u8, start: usize) TextRun {
    if (start >= hay.len) return .{ .lt_index = hay.len, .has_non_whitespace = false };
    if (!tables.WhitespaceTable[hay[start]]) {
        return .{
            .lt_index = findByte(hay, start, '<') orelse hay.len,
            .has_non_whitespace = true,
        };
    }
    return scanWhitespaceTextRun(hay, start);
}

noinline fn scanWhitespaceTextRun(hay: []const u8, start: usize) TextRun {
    const next = skipWhitespace(hay, start);
    if (next >= hay.len) return .{ .lt_index = hay.len, .has_non_whitespace = false };
    if (hay[next] == '<') return .{ .lt_index = next, .has_non_whitespace = false };
    return .{
        .lt_index = findByte(hay, next, '<') orelse hay.len,
        .has_non_whitespace = true,
    };
}

pub fn findSequence(noalias haystack: []const u8, start: usize, noalias needle: []const u8) ?usize {
    if (needle.len == 0) return if (start <= haystack.len) start else null;
    if (start >= haystack.len) return null;
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

pub inline fn isDoctype(input: []const u8, start: usize) bool {
    return start <= input.len and input.len - start >= 9 and
        input[start] == '<' and
        input[start + 1] == '!' and
        ((input[start + 2] | 0x20) == 'd') and
        ((input[start + 3] | 0x20) == 'o') and
        ((input[start + 4] | 0x20) == 'c') and
        ((input[start + 5] | 0x20) == 't') and
        ((input[start + 6] | 0x20) == 'y') and
        ((input[start + 7] | 0x20) == 'p') and
        ((input[start + 8] | 0x20) == 'e');
}

pub inline fn isDoctypeExact(input: []const u8, start: usize) bool {
    return start <= input.len and input.len - start >= 9 and
        std.mem.eql(u8, input[start .. start + 9], "<!DOCTYPE");
}

/// Finds the terminal `>` of a doctype while ignoring quoted text and the
/// internal subset. `start` points immediately after `<!DOCTYPE`.
pub fn findDoctypeEnd(input: []const u8, start: usize) ?usize {
    var i = start;
    var bracket_depth: usize = 0;
    var quote: u8 = 0;
    while (i < input.len) : (i += 1) {
        const c = input[i];
        if (quote != 0) {
            if (c == quote) quote = 0;
            continue;
        }
        if (i + 3 < input.len and std.mem.eql(u8, input[i .. i + 4], "<!--")) {
            const end = findSequence(input, i + 4, "-->") orelse return null;
            i = end + 2;
            continue;
        }
        if (i + 1 < input.len and input[i] == '<' and input[i + 1] == '?') {
            const end = findSequence(input, i + 2, "?>") orelse return null;
            i = end + 1;
            continue;
        }
        if (c == '\'' or c == '"') {
            quote = c;
            continue;
        }
        if (c == '[') {
            bracket_depth += 1;
            continue;
        }
        if (c == ']') {
            bracket_depth -|= 1;
            continue;
        }
        if (c == '>' and bracket_depth == 0) return i;
    }
    return null;
}

test "findByte and findSequence locate delimiters" {
    try std.testing.expectEqual(@as(?usize, 3), findByte("abc<def", 0, '<'));
    try std.testing.expectEqual(@as(?usize, null), findByte("abc", 9, '<'));
    try std.testing.expectEqual(@as(?usize, null), findByte("abc", std.math.maxInt(usize), '<'));
    try std.testing.expectEqual(@as(?usize, 3), findSequence("abc?def", 0, "?"));
    try std.testing.expectEqual(@as(?usize, 3), findSequence("abc?>def", 0, "?>"));
    try std.testing.expectEqual(@as(?usize, 3), findSequence("abc]]>def", 0, "]]>"));
    try std.testing.expectEqual(@as(?usize, 3), findSequence("abcqrstdef", 0, "qrst"));
    try std.testing.expectEqual(@as(?usize, null), findSequence("abcdef", 0, "?>"));
    try std.testing.expectEqual(@as(?usize, null), findSequence("abcdef", 9, "x"));
    try std.testing.expectEqual(@as(?usize, 6), findSequence("abcdef", 6, ""));
    try std.testing.expectEqual(@as(?usize, null), findSequence("abcdef", 7, ""));
}

test "scanQuotedValueSpecials finds quote and strict sentinels in one pass" {
    const plain = scanQuotedValueSpecials("alpha'ignored<&", 0, '\'');
    try std.testing.expectEqual(@as(usize, 5), plain.end);
    try std.testing.expect(!plain.has_lt);
    try std.testing.expect(!plain.has_ampersand);

    const special = scanQuotedValueSpecials("a<&amp;'tail", 0, '\'');
    try std.testing.expectEqual(@as(usize, 7), special.end);
    try std.testing.expect(special.has_lt);
    try std.testing.expect(special.has_ampersand);

    var long: [160]u8 = @splat('x');
    long[70] = '&';
    long[100] = '<';
    long[140] = '"';
    const vector = scanQuotedValueSpecials(&long, 0, '"');
    try std.testing.expectEqual(@as(usize, 140), vector.end);
    try std.testing.expect(vector.has_lt);
    try std.testing.expect(vector.has_ampersand);

    const missing = scanQuotedValueSpecials("abc&def", 0, '"');
    try std.testing.expectEqual(@as(usize, 7), missing.end);
    try std.testing.expect(missing.has_ampersand);
}

test "scanTextSpecials finds markup and strict sentinels in short and vector runs" {
    const plain = scanTextSpecials("alpha<beta", 0);
    try std.testing.expectEqual(@as(usize, 5), plain.lt_index);
    try std.testing.expect(!plain.has_close_bracket);
    try std.testing.expect(!plain.has_ampersand);

    const special = scanTextSpecials("abc]def&amp;<tail", 0);
    try std.testing.expectEqual(@as(usize, 12), special.lt_index);
    try std.testing.expect(special.has_close_bracket);
    try std.testing.expect(special.has_ampersand);

    var long: [160]u8 = @splat('x');
    long[70] = ']';
    long[96] = '&';
    long[140] = '<';
    const vector = scanTextSpecials(&long, 0);
    try std.testing.expectEqual(@as(usize, 140), vector.lt_index);
    try std.testing.expect(vector.has_close_bracket);
    try std.testing.expect(vector.has_ampersand);
}

test "bytePairPresence finds either sentinel in short and vector-sized inputs" {
    const none = bytePairPresence("alpha123", '<', '&');
    try std.testing.expect(!none.first);
    try std.testing.expect(!none.second);

    const both = bytePairPresence("a&b<c", '<', '&');
    try std.testing.expect(both.first);
    try std.testing.expect(both.second);

    var long = [_]u8{'x'} ** (byte_scan_vector_len * 2 + 3);
    long[byte_scan_vector_len - 1] = ']';
    long[byte_scan_vector_len * 2 + 1] = '&';
    const vector = bytePairPresence(&long, ']', '&');
    try std.testing.expect(vector.first);
    try std.testing.expect(vector.second);
}

test "doctype scanner ignores quotes comments processing instructions and internal subsets" {
    const src = "<!DOCTYPE r [<!ENTITY x 'a>b'><!-- ] > --><?pi ] >?>]><r/>";
    try std.testing.expect(isDoctype(src, 0));
    try std.testing.expect(isDoctypeExact(src, 0));
    try std.testing.expect(!isDoctypeExact("<!doctype r>", 0));
    const end = findDoctypeEnd(src, 9) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 53), end);
    try std.testing.expectEqual(@as(?usize, null), findDoctypeEnd("<!DOCTYPE r [", 9));
    try std.testing.expectEqual(@as(?usize, null), findDoctypeEnd("<!DOCTYPE r [<!--", 9));
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
