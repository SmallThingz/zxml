const std = @import("std");
const common = @import("common.zig");
const entities = @import("entities.zig");
const scanner = @import("scanner.zig");
const tables = @import("tables.zig");

pub const IndexInt = common.IndexInt;
pub const Span = common.Span;

pub const ValueState = enum(u8) {
    none = 0,
    decoded = '=',
    raw_unquoted = '/',
    raw_single_quoted = '\'',
    raw_double_quoted = '"',

    pub inline fn isDecoded(self: @This()) bool {
        return self == .decoded;
    }
};

pub const RawAttribute = struct {
    name: Span,
    value: Span,
    value_state: ValueState = .none,

    pub inline fn hasValue(self: @This()) bool {
        return self.value_state != .none;
    }
};

/// Raw XML attribute tokenizer. Full-validation callers instantiate `validated=true`;
/// permissive callers stay bounded and skip malformed bytes instead of crashing.
pub fn RawIterator(comptime validated: bool) type {
    return struct {
        source: []const u8,
        i: usize,
        end: usize,

        pub inline fn init(source: []const u8, span: Span) @This() {
            return .{ .source = source, .i = span.start, .end = span.end };
        }

        pub fn next(self: *@This()) ?RawAttribute {
            var i = self.i;
            while (i < self.end and tables.isWhitespace(self.source[i])) : (i += 1) {}
            while (i < self.end and !tables.isNameStart(self.source[i])) {
                if (comptime validated) {
                    self.i = self.end;
                    return null;
                }
                i += 1;
                while (i < self.end and tables.isWhitespace(self.source[i])) : (i += 1) {}
            }
            if (i >= self.end) {
                self.i = self.end;
                return null;
            }

            const name_start = i;
            i = scanner.findNameEnd(self.source[0..self.end], i);
            const name_end = i;
            while (i < self.end and tables.isWhitespace(self.source[i])) : (i += 1) {}

            var value_start = i;
            var value_end = i;
            var value_state: ValueState = .none;
            if (i < self.end and self.source[i] == '=') {
                value_state = .raw_unquoted;
                i += 1;
                while (i < self.end and tables.isWhitespace(self.source[i])) : (i += 1) {}
                if (i < self.end) {
                    const quote = self.source[i];
                    if (quote == '\'' or quote == '"') {
                        value_state = if (quote == '\'') .raw_single_quoted else .raw_double_quoted;
                        value_start = i + 1;
                        value_end = scanner.findByte(self.source[0..self.end], value_start, quote) orelse self.end;
                        i = if (value_end < self.end) value_end + 1 else self.end;
                    } else if (comptime !validated) {
                        value_start = i;
                        value_end = @min(scanner.findAttrUnquotedEnd(self.source[0..self.end], i), self.end);
                        i = value_end;
                    }
                }
            }
            self.i = i;
            return .{
                .name = .{ .start = @intCast(name_start), .end = @intCast(name_end) },
                .value = .{ .start = @intCast(value_start), .end = @intCast(value_end) },
                .value_state = value_state,
            };
        }
    };
}

inline fn looksCompact(source: []const u8, name_end: usize) bool {
    if (name_end >= source.len) return false;
    const c = source[name_end];
    return c != '>' and c != '/' and !tables.isWhitespace(c);
}

/// Compact attribute list iterator for destructive documents. The byte between
/// a name and value is also the value-materialization state.
const CompactIterator = struct {
    source: []const u8,
    cursor: usize,

    inline fn stateFromOperator(c: u8) ?ValueState {
        return switch (c) {
            '=' => .decoded,
            '/' => .raw_unquoted,
            '\'' => .raw_single_quoted,
            '"' => .raw_double_quoted,
            else => null,
        };
    }

    fn next(self: *@This()) ?RawAttribute {
        if (self.cursor >= self.source.len or self.source[self.cursor] == '>') return null;
        const name_start = self.cursor;
        while (self.cursor < self.source.len) : (self.cursor += 1) {
            const c = self.source[self.cursor];
            if (stateFromOperator(c) != null or c == 0 or c == '>') break;
        }
        const name_end = self.cursor;
        if (name_end == name_start or self.cursor >= self.source.len or self.source[self.cursor] == '>') return null;

        const value_state = stateFromOperator(self.source[self.cursor]) orelse .none;
        var value_start = self.cursor;
        var value_end = self.cursor;
        if (value_state != .none) {
            self.cursor += 1;
            value_start = self.cursor;
            while (self.cursor < self.source.len and self.source[self.cursor] != 0) : (self.cursor += 1) {}
            value_end = self.cursor;
        }
        if (self.cursor < self.source.len and self.source[self.cursor] == 0) self.cursor += 1;
        return .{
            .name = .{ .start = @intCast(name_start), .end = @intCast(name_end) },
            .value = .{ .start = @intCast(value_start), .end = @intCast(value_end) },
            .value_state = value_state,
        };
    }
};

/// Parse a tag's raw XML attributes once, decode every shrinkable value in
/// place, and compact the result leftward. The compact form is
/// `name[marker value]NUL ... >`; `=` marks decoded bytes while `/`, `'`, and
/// `"` preserve raw unquoted/single/double-quoted values that require an owned
/// decode fallback. Literal NUL in permissive malformed input leaves the tag on
/// the bounded raw scanner because NUL is the compact-list separator.
pub fn materializeAttributes(
    comptime validated: bool,
    source: []u8,
    name_end: usize,
    entity_map: ?*const std.StringHashMap([]u8),
) bool {
    if (name_end >= source.len) return false;
    if (looksCompact(source, name_end)) return true;
    if (!tables.isWhitespace(source[name_end])) return false;

    const tail = scanner.scanStartTagEnd(source, name_end) orelse return false;
    const attr_end = if (tail.self_closing and tail.end > name_end) tail.end - 1 else tail.end;
    if (std.mem.indexOfScalar(u8, source[name_end..attr_end], 0) != null) return false;

    // A permissive DTD may contain XML-invalid NUL bytes. Never put such a
    // replacement into the NUL-delimited compact representation; preserve raw
    // values and let requested decoding use the owned fallback instead.
    var decode_in_place = true;
    if (entity_map) |map| {
        var values = map.valueIterator();
        while (values.next()) |value| {
            if (std.mem.indexOfScalar(u8, value.*, 0) != null) {
                decode_in_place = false;
                break;
            }
        }
    }

    var raw = RawIterator(validated).init(source, .{ .start = @intCast(name_end), .end = @intCast(attr_end) });
    var write = name_end;
    while (raw.next()) |item| {
        const name = item.name.slice(source);
        std.mem.copyForwards(u8, source[write .. write + name.len], name);
        write += name.len;

        if (item.hasValue()) {
            var state = item.value_state;
            var value_len: usize = @intCast(item.value.len());
            if (decode_in_place) {
                const decoded = entities.decodeInPlaceWithEntityMap(item.value.sliceMut(source), validated, entity_map) catch null;
                if (decoded) |result| {
                    if (result.complete) {
                        state = .decoded;
                        value_len = result.len;
                    }
                }
            }

            source[write] = @intFromEnum(state);
            write += 1;
            const value_start: usize = @intCast(item.value.start);
            std.mem.copyForwards(u8, source[write .. write + value_len], source[value_start .. value_start + value_len]);
            write += value_len;
        }

        source[write] = 0;
        write += 1;
    }
    if (write >= source.len) return false;
    source[write] = '>';
    return true;
}

/// Generated DOM attribute iterator. Destructive documents materialize once;
/// non-destructive documents remain on the raw source tokenizer forever.
pub fn Iterator(comptime non_destructive: bool, comptime validated: bool) type {
    return struct {
        source: []const u8,
        raw: RawIterator(validated),
        compact: CompactIterator,
        use_compact: bool = false,

        pub fn initElement(source_input: if (non_destructive) []const u8 else []u8, name_end_idx: IndexInt) @This() {
            const source: []const u8 = source_input;
            const name_end: usize = @intCast(name_end_idx);
            if (comptime !non_destructive) {
                if (looksCompact(source, name_end)) {
                    return .{
                        .source = source,
                        .raw = RawIterator(validated).init(source, .{}),
                        .compact = .{ .source = source, .cursor = name_end },
                        .use_compact = true,
                    };
                }
            }

            const tail = scanner.scanStartTagEnd(source, name_end) orelse return .{
                .source = source,
                .raw = RawIterator(validated).init(source, .{}),
                .compact = .{ .source = source, .cursor = source.len },
            };
            const end = if (tail.self_closing and tail.end > name_end) tail.end - 1 else tail.end;
            return .{
                .source = source,
                .raw = RawIterator(validated).init(source, .{ .start = @intCast(name_end), .end = @intCast(end) }),
                .compact = .{ .source = source, .cursor = source.len },
            };
        }

        pub fn next(self: *@This()) ?RawAttribute {
            return if (self.use_compact) self.compact.next() else self.raw.next();
        }
    };
}

test "destructive materialization decodes and compacts once" {
    var source = "<r a='&amp;' b=\"two\"/>".*;
    const name_end: IndexInt = 2;
    try std.testing.expect(materializeAttributes(false, &source, name_end, null));

    var first = Iterator(false, false).initElement(&source, name_end);
    const a = first.next() orelse return error.TestUnexpectedResult;
    const b = first.next() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("a", a.name.slice(&source));
    try std.testing.expectEqualStrings("&", a.value.slice(&source));
    try std.testing.expect(a.value_state.isDecoded());
    try std.testing.expectEqualStrings("b", b.name.slice(&source));
    try std.testing.expectEqualStrings("two", b.value.slice(&source));
    try std.testing.expect(b.value_state.isDecoded());
    try std.testing.expect(first.next() == null);

    const compacted = source;
    try std.testing.expect(materializeAttributes(false, &source, name_end, null));
    try std.testing.expectEqualSlices(u8, &compacted, &source);
}

test "non destructive iterator never mutates source" {
    const source = "<r a='1' b=\"two\"/>";
    var it = Iterator(true, false).initElement(source, 2);
    try std.testing.expectEqualStrings("1", (it.next() orelse return error.TestUnexpectedResult).value.slice(source));
    try std.testing.expectEqualStrings("two", (it.next() orelse return error.TestUnexpectedResult).value.slice(source));
    try std.testing.expectEqualStrings("<r a='1' b=\"two\"/>", source);
}

test "destructive materialization declines malformed literal NUL" {
    var source = [_]u8{ '<', 'r', ' ', 'a', '=', '\'', 'x', 0, 'y', '\'', '/', '>' };
    const before = source;
    try std.testing.expect(!materializeAttributes(false, &source, 2, null));
    try std.testing.expectEqualSlices(u8, &before, &source);
}
