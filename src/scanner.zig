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

/// Fast path for text runs that are commonly one SIMD chunk or a little
/// longer. Keep the general delimiter finder compact for token-heavy streaming.
pub inline fn findTextEnd(noalias haystack: []const u8, start: usize) ?usize {
    if (start >= haystack.len) return null;
    const Vec = @Vector(byte_scan_vector_len, u8);
    if (haystack.len - start >= @sizeOf(Vec)) {
        const Bits = @Vector(byte_scan_vector_len, u1);
        const Mask = std.meta.Int(.unsigned, byte_scan_vector_len);
        const bytes: Vec = haystack[start..][0..@sizeOf(Vec)].*;
        const lt_vec: Vec = @splat('<');
        const bits: Bits = @select(u1, bytes == lt_vec, @as(Bits, @splat(1)), @as(Bits, @splat(0)));
        const mask: Mask = @bitCast(bits);
        if (mask != 0) return start + @ctz(mask);
        return findByte(haystack, start + @sizeOf(Vec), '<');
    }
    return findByte(haystack, start, '<');
}

pub const SimpleQuotedAttributeScan = struct {
    name_start: usize,
    name_end: usize,
    value_start: usize,
    value_end: usize,
    next: usize,
};

/// Fast recognition of the common turbo attribute spelling ` name="value"`.
/// Returns null for any other spelling so callers can fall back to the full
/// permissive grammar without changing accepted input.
pub inline fn scanSimpleQuotedAttribute(noalias input: []const u8, start: usize) ?SimpleQuotedAttributeScan {
    if (start + 4 >= input.len or input[start] != ' ') return null;
    const name_start = start + 1;
    if (!tables.isNameStart(input[name_start])) return null;
    const name_end = findNameEndAfterStart(input, name_start);
    if (name_end + 2 >= input.len or input[name_end] != '=') return null;
    const quote = input[name_end + 1];
    if (quote != '\'' and quote != '"') return null;
    const value_start = name_end + 2;
    const value_end = findByte(input, value_start, quote) orelse return null;
    return .{
        .name_start = name_start,
        .name_end = name_end,
        .value_start = value_start,
        .value_end = value_end,
        .next = value_end + 1,
    };
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
    const scalar_end = start + @min(hay.len - start, 8);
    var i = start;
    while (i < scalar_end) : (i += 1) {
        const c = hay[i];
        if (c == quote) {
            result.end = i;
            return result;
        }
        result.has_lt = result.has_lt or c == '<';
        result.has_ampersand = result.has_ampersand or c == '&';
    }
    if (i == hay.len) return result;
    if (hay[i] == quote) {
        result.end = i;
        return result;
    }
    result.has_lt = result.has_lt or hay[i] == '<';
    result.has_ampersand = result.has_ampersand or hay[i] == '&';
    i += 1;

    const Vec = @Vector(byte_scan_vector_len, u8);
    const Bits = @Vector(byte_scan_vector_len, u1);
    const Mask = std.meta.Int(.unsigned, byte_scan_vector_len);
    const quote_vec: Vec = @splat(quote);
    const lt_vec: Vec = @splat('<');
    const amp_vec: Vec = @splat('&');
    while (i + @sizeOf(Vec) <= hay.len) : (i += @sizeOf(Vec)) {
        const bytes: Vec = hay[i..][0..@sizeOf(Vec)].*;
        const quote_bits: Bits = @select(u1, bytes == quote_vec, @as(Bits, @splat(1)), @as(Bits, @splat(0)));
        const quote_mask: Mask = @bitCast(quote_bits);
        const lt_bits: Bits = @select(u1, bytes == lt_vec, @as(Bits, @splat(1)), @as(Bits, @splat(0)));
        const lt_mask: Mask = @bitCast(lt_bits);
        const amp_bits: Bits = @select(u1, bytes == amp_vec, @as(Bits, @splat(1)), @as(Bits, @splat(0)));
        const amp_mask: Mask = @bitCast(amp_bits);
        if (quote_mask != 0) {
            const offset: std.math.Log2Int(Mask) = @intCast(@ctz(quote_mask));
            const before = if (offset == 0) @as(Mask, 0) else (@as(Mask, 1) << offset) - 1;
            result.has_lt = result.has_lt or (lt_mask & before) != 0;
            result.has_ampersand = result.has_ampersand or (amp_mask & before) != 0;
            result.end = i + offset;
            return result;
        }
        result.has_lt = result.has_lt or lt_mask != 0;
        result.has_ampersand = result.has_ampersand or amp_mask != 0;
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
    const scalar_end = start + @min(hay.len - start, 8);
    var i = start;
    while (i < scalar_end) : (i += 1) {
        const c = hay[i];
        if (c == '<') {
            result.lt_index = i;
            return result;
        }
        result.has_close_bracket = result.has_close_bracket or c == ']';
        result.has_ampersand = result.has_ampersand or c == '&';
    }
    if (i == hay.len) return result;
    if (hay[i] == '<') {
        result.lt_index = i;
        return result;
    }
    result.has_close_bracket = result.has_close_bracket or hay[i] == ']';
    result.has_ampersand = result.has_ampersand or hay[i] == '&';
    i += 1;

    const Vec = @Vector(byte_scan_vector_len, u8);
    const Bits = @Vector(byte_scan_vector_len, u1);
    const Mask = std.meta.Int(.unsigned, byte_scan_vector_len);
    const lt_vec: Vec = @splat('<');
    const close_vec: Vec = @splat(']');
    const amp_vec: Vec = @splat('&');
    while (i + @sizeOf(Vec) <= hay.len) : (i += @sizeOf(Vec)) {
        const bytes: Vec = hay[i..][0..@sizeOf(Vec)].*;
        const lt_bits: Bits = @select(u1, bytes == lt_vec, @as(Bits, @splat(1)), @as(Bits, @splat(0)));
        const lt_mask: Mask = @bitCast(lt_bits);
        const close_bits: Bits = @select(u1, bytes == close_vec, @as(Bits, @splat(1)), @as(Bits, @splat(0)));
        const close_mask: Mask = @bitCast(close_bits);
        const amp_bits: Bits = @select(u1, bytes == amp_vec, @as(Bits, @splat(1)), @as(Bits, @splat(0)));
        const amp_mask: Mask = @bitCast(amp_bits);
        if (lt_mask != 0) {
            const offset: std.math.Log2Int(Mask) = @intCast(@ctz(lt_mask));
            const before = if (offset == 0) @as(Mask, 0) else (@as(Mask, 1) << offset) - 1;
            result.has_close_bracket = result.has_close_bracket or (close_mask & before) != 0;
            result.has_ampersand = result.has_ampersand or (amp_mask & before) != 0;
            result.lt_index = i + offset;
            return result;
        }
        result.has_close_bracket = result.has_close_bracket or close_mask != 0;
        result.has_ampersand = result.has_ampersand or amp_mask != 0;
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

test "simple quoted attribute fast scan recognizes only its exact turbo grammar" {
    const input = " id=\"12345678\" kind='x'>";
    const first = scanSimpleQuotedAttribute(input, 0) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("id", input[first.name_start..first.name_end]);
    try std.testing.expectEqualStrings("12345678", input[first.value_start..first.value_end]);
    try std.testing.expectEqual(@as(usize, 14), first.next);

    const second = scanSimpleQuotedAttribute(input, first.next) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("kind", input[second.name_start..second.name_end]);
    try std.testing.expectEqualStrings("x", input[second.value_start..second.value_end]);
    try std.testing.expectEqual(@as(usize, 23), second.next);

    inline for (.{
        "id=\"x\"",
        "  id=\"x\"",
        " id =\"x\"",
        " id= \"x\"",
        " id=x",
        " !id=\"x\"",
    }) |other| {
        try std.testing.expectEqual(@as(?SimpleQuotedAttributeScan, null), scanSimpleQuotedAttribute(other, 0));
    }
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

test "strict fused scanners match scalar references across vector boundaries" {
    const Ref = struct {
        fn quoted(input: []const u8, start: usize, quote: u8) QuotedValueScan {
            var out: QuotedValueScan = .{ .end = input.len };
            var i = start;
            while (i < input.len) : (i += 1) {
                const c = input[i];
                if (c == quote) {
                    out.end = i;
                    return out;
                }
                out.has_lt = out.has_lt or c == '<';
                out.has_ampersand = out.has_ampersand or c == '&';
            }
            return out;
        }

        fn text(input: []const u8, start: usize) TextSpecialRun {
            var out: TextSpecialRun = .{ .lt_index = input.len };
            var i = start;
            while (i < input.len) : (i += 1) {
                const c = input[i];
                if (c == '<') {
                    out.lt_index = i;
                    return out;
                }
                out.has_close_bracket = out.has_close_bracket or c == ']';
                out.has_ampersand = out.has_ampersand or c == '&';
            }
            return out;
        }
    };

    var input: [193]u8 = undefined;
    for (0..input.len) |i| {
        input[i] = switch ((i * 29 + 11) % 53) {
            0 => '<',
            1 => '&',
            2 => ']',
            3 => '\'',
            4 => '"',
            else => @intCast('a' + (i % 26)),
        };
    }

    const starts = [_]usize{ 0, 1, 7, 8, 9, 31, 32, 33, 63, 64, 65 };
    for (0..input.len) |len| {
        for (starts) |start| {
            if (start > len) continue;
            const slice = input[0..len];
            const expected_text = Ref.text(slice, start);
            const actual_text = scanTextSpecials(slice, start);
            try std.testing.expectEqual(expected_text.lt_index, actual_text.lt_index);
            try std.testing.expectEqual(expected_text.has_close_bracket, actual_text.has_close_bracket);
            try std.testing.expectEqual(expected_text.has_ampersand, actual_text.has_ampersand);
            try std.testing.expectEqual(findByte(slice, start, '<'), findTextEnd(slice, start));

            inline for (.{ '\'', '"' }) |quote| {
                const expected_quote = Ref.quoted(slice, start, quote);
                const actual_quote = scanQuotedValueSpecials(slice, start, quote);
                try std.testing.expectEqual(expected_quote.end, actual_quote.end);
                try std.testing.expectEqual(expected_quote.has_lt, actual_quote.has_lt);
                try std.testing.expectEqual(expected_quote.has_ampersand, actual_quote.has_ampersand);
            }
        }
    }
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
