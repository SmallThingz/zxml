const std = @import("std");
const builtin = @import("builtin");
const tables = @import("tables.zig");

pub inline fn findByte(noalias haystack: []const u8, start: usize, needle: u8) ?usize {
    return findByteDispatch(haystack, start, needle);
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

pub fn findTagEndRespectQuotes(input: []const u8, start: usize) ?TagEnd {
    var i = start;
    var quote: u8 = 0;

    while (i < input.len) : (i += 1) {
        const c = input[i];
        if (quote != 0) {
            if (c == quote) quote = 0;
            continue;
        }

        if (c == '\'' or c == '"') {
            quote = c;
            continue;
        }

        if (c == '>') {
            const attr_end = trimRightSlashAndWs(input, start, i);
            const self_close = attr_end > start and input[attr_end - 1] == '/';
            return .{
                .gt_index = i,
                .attr_end = if (self_close) attr_end - 1 else attr_end,
                .self_close = self_close,
            };
        }
    }

    return null;
}

inline fn findByteDispatch(hay: []const u8, start: usize, needle: u8) ?usize {
    if (start >= hay.len) return null;
    const rem = hay.len - start;

    if (comptime builtin.cpu.arch == .x86_64 and std.Target.x86.featureSetHas(builtin.cpu.features, .avx2)) {
        if (rem < 64) return std.mem.indexOfScalarPos(u8, hay, start, needle);
        return findByteVec(32, hay, start, needle);
    }
    if (comptime builtin.cpu.arch == .x86_64 and std.Target.x86.featureSetHas(builtin.cpu.features, .sse2)) {
        if (rem < 32) return std.mem.indexOfScalarPos(u8, hay, start, needle);
        return findByteVec(16, hay, start, needle);
    }
    if (comptime builtin.cpu.arch == .aarch64) {
        if (rem < 32) return std.mem.indexOfScalarPos(u8, hay, start, needle);
        return findByteVec(16, hay, start, needle);
    }
    return std.mem.indexOfScalarPos(u8, hay, start, needle);
}

inline fn findByteVec(comptime lanes: comptime_int, hay: []const u8, start: usize, needle: u8) ?usize {
    const Vec = @Vector(lanes, u8);
    const needle_vec: Vec = @splat(needle);

    var i = start;
    while (i + lanes <= hay.len) : (i += lanes) {
        const chunk: [lanes]u8 = hay[i..][0..lanes].*;
        const vec: Vec = chunk;
        const mask = vec == needle_vec;
        if (@reduce(.Or, mask)) {
            var j: usize = 0;
            while (j < lanes) : (j += 1) {
                if (chunk[j] == needle) return i + j;
            }
        }
    }

    return std.mem.indexOfScalarPos(u8, hay, i, needle);
}

fn trimRightSlashAndWs(input: []const u8, start: usize, end_exclusive: usize) usize {
    var j = end_exclusive;
    while (j > start and (input[j - 1] == ' ' or input[j - 1] == '\t' or input[j - 1] == '\n' or input[j - 1] == '\r')) {
        j -= 1;
    }
    return j;
}

pub const TagEnd = struct {
    gt_index: usize,
    attr_end: usize,
    self_close: bool,
};
