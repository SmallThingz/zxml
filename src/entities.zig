const std = @import("std");
const tables = @import("tables.zig");

pub const DecodeError = error{
    InvalidNumericCharacterEntity,
    UnterminatedEntity,
};

const EntityDecode = struct {
    bytes: [4]u8,
    len: usize,
};

const EntityToken = struct {
    consumed: usize,
    body: []const u8,
};

pub fn decodeAlloc(alloc: std.mem.Allocator, input: []const u8, strict: bool) (std.mem.Allocator.Error || DecodeError)![]u8 {
    return decodeAllocWithEntityMap(alloc, input, strict, null);
}

pub fn decodeAllocWithEntityMap(
    alloc: std.mem.Allocator,
    input: []const u8,
    strict: bool,
    entity_map: ?*const std.StringHashMap([]u8),
) (std.mem.Allocator.Error || DecodeError)![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(alloc);
    try appendDecodedWithEntityMap(&out, alloc, input, strict, entity_map);
    return out.toOwnedSlice(alloc);
}

pub fn appendDecoded(
    out: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    input: []const u8,
    strict: bool,
) (std.mem.Allocator.Error || DecodeError)!void {
    return appendDecodedWithEntityMap(out, alloc, input, strict, null);
}

pub fn appendDecodedWithEntityMap(
    out: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    input: []const u8,
    strict: bool,
    entity_map: ?*const std.StringHashMap([]u8),
) (std.mem.Allocator.Error || DecodeError)!void {
    const first = std.mem.indexOfScalar(u8, input, '&') orelse {
        try out.appendSlice(alloc, input);
        return;
    };

    try out.appendSlice(alloc, input[0..first]);
    var src = first;
    while (src < input.len) {
        if (input[src] != '&') {
            const next = std.mem.indexOfScalarPos(u8, input, src, '&') orelse input.len;
            try out.appendSlice(alloc, input[src..next]);
            src = next;
            continue;
        }

        const token = parseEntityToken(input, src) catch |err| switch (err) {
            error.UnterminatedEntity => {
                if (strict) return error.UnterminatedEntity;
                try out.append(alloc, '&');
                src += 1;
                continue;
            },
            error.InvalidNumericCharacterEntity => {
                if (strict) return error.InvalidNumericCharacterEntity;
                try out.append(alloc, '&');
                src += 1;
                continue;
            },
        };

        if (try tryAppendDecodedEntityBody(out, alloc, token.body, strict, entity_map)) {
            src += token.consumed;
            continue;
        }

        if (strict) return error.InvalidNumericCharacterEntity;
        try out.append(alloc, '&');
        src += 1;
    }
}

pub fn validateStructuralEntities(noalias buf: []const u8) DecodeError!void {
    var src = std.mem.indexOfScalar(u8, buf, '&') orelse return;
    while (src < buf.len) {
        if (buf[src] != '&') {
            src += 1;
            continue;
        }

        const semi = std.mem.indexOfScalarPos(u8, buf, src + 1, ';') orelse return error.UnterminatedEntity;
        const body = buf[src + 1 .. semi];
        if (body.len == 0) return error.InvalidNumericCharacterEntity;

        if (body[0] == '#') {
            _ = try decodeEntityBody(body, true) orelse return error.InvalidNumericCharacterEntity;
        } else {
            if (!tables.isNameStart(body[0])) return error.InvalidNumericCharacterEntity;
            for (body[1..]) |c| {
                if (!tables.isNameChar(c)) return error.InvalidNumericCharacterEntity;
            }
        }

        src = semi + 1;
    }
}

fn tryAppendDecodedEntityBody(
    out: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    body: []const u8,
    strict: bool,
    entity_map: ?*const std.StringHashMap([]u8),
) (std.mem.Allocator.Error || DecodeError)!bool {
    if (try decodeEntityBody(body, strict)) |decoded| {
        try out.appendSlice(alloc, decoded.bytes[0..decoded.len]);
        return true;
    }

    if (entity_map) |map| {
        if (map.get(body)) |value| {
            try out.appendSlice(alloc, value);
            return true;
        }
    }

    return false;
}

fn parseEntityToken(noalias buf: []const u8, start: usize) DecodeError!EntityToken {
    const semi = std.mem.indexOfScalarPos(u8, buf, start + 1, ';') orelse {
        return error.UnterminatedEntity;
    };

    const body = buf[start + 1 .. semi];
    if (body.len == 0) return error.InvalidNumericCharacterEntity;

    return .{
        .consumed = semi - start + 1,
        .body = body,
    };
}

fn decodeEntityBody(body: []const u8, strict: bool) DecodeError!?EntityDecode {
    const named: ?u8 = if (std.mem.eql(u8, body, "amp"))
        '&'
    else if (std.mem.eql(u8, body, "lt"))
        '<'
    else if (std.mem.eql(u8, body, "gt"))
        '>'
    else if (std.mem.eql(u8, body, "apos"))
        '\''
    else if (std.mem.eql(u8, body, "quot"))
        '"'
    else
        null;
    if (named) |c| {
        return .{
            .bytes = .{ c, 0, 0, 0 },
            .len = 1,
        };
    }

    if (body[0] == '#') {
        const cp: u21 = blk: {
            const text = body[1..];
            if (text.len == 0) {
                if (strict) return error.InvalidNumericCharacterEntity;
                return null;
            }

            const is_hex = text[0] == 'x' or text[0] == 'X';
            const digits = if (is_hex) text[1..] else text;
            if (digits.len == 0) {
                if (strict) return error.InvalidNumericCharacterEntity;
                return null;
            }

            var value: u32 = 0;
            for (digits) |c| {
                const d: u8 = if (is_hex)
                    if (c >= '0' and c <= '9')
                        c - '0'
                    else if (c >= 'a' and c <= 'f')
                        c - 'a' + 10
                    else if (c >= 'A' and c <= 'F')
                        c - 'A' + 10
                    else
                        255
                else if (c >= '0' and c <= '9')
                    c - '0'
                else
                    255;

                if (d == 255) {
                    if (strict) return error.InvalidNumericCharacterEntity;
                    return null;
                }
                value = if (is_hex) value * 16 + d else value * 10 + d;
                if (value > 0x10FFFF) {
                    if (strict) return error.InvalidNumericCharacterEntity;
                    return null;
                }
            }

            if (value >= 0xD800 and value <= 0xDFFF) {
                if (strict) return error.InvalidNumericCharacterEntity;
                return null;
            }
            break :blk @intCast(value);
        };

        var out_bytes: [4]u8 = undefined;
        const written = std.unicode.utf8Encode(cp, &out_bytes) catch {
            if (strict) return error.InvalidNumericCharacterEntity;
            return null;
        };

        return .{
            .bytes = out_bytes,
            .len = written,
        };
    }

    return null;
}

test "decodeAlloc decodes without mutating the source slice" {
    const alloc = std.testing.allocator;
    const input = "&amp;&#65;&#x42;";
    const decoded = try decodeAlloc(alloc, input, true);
    defer alloc.free(decoded);

    try std.testing.expectEqualStrings("&AB", decoded);
    try std.testing.expectEqualStrings("&amp;&#65;&#x42;", input);
}

test "non-strict decode leaves malformed and unknown entities literal" {
    const alloc = std.testing.allocator;

    const unknown = try decodeAlloc(alloc, "&bogus; &amp", false);
    defer alloc.free(unknown);
    try std.testing.expectEqualStrings("&bogus; &amp", unknown);

    const apost_quot = try decodeAlloc(alloc, "&apos;&quot;", true);
    defer alloc.free(apost_quot);
    try std.testing.expectEqualStrings("'\"", apost_quot);
}

test "validateStructuralEntities allows custom named entities but rejects malformed refs" {
    try validateStructuralEntities("&safe;");
    try std.testing.expectError(error.UnterminatedEntity, validateStructuralEntities("&amp"));
    try std.testing.expectError(error.InvalidNumericCharacterEntity, validateStructuralEntities("&#x110000;"));
    try std.testing.expectError(error.InvalidNumericCharacterEntity, validateStructuralEntities("&1bad;"));
}

test "decodeAllocWithEntityMap expands mapped named entities" {
    const alloc = std.testing.allocator;
    var map = std.StringHashMap([]u8).init(alloc);
    defer {
        var it = map.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            alloc.free(entry.value_ptr.*);
        }
        map.deinit();
    }

    const key = try alloc.dupe(u8, "safe");
    const value = try alloc.dupe(u8, "SAFE");
    try map.put(key, value);

    const decoded = try decodeAllocWithEntityMap(alloc, "&safe;&amp;", true, &map);
    defer alloc.free(decoded);
    try std.testing.expectEqualStrings("SAFE&", decoded);
}

test "strict decode rejects unknown named entities without a DTD map" {
    const alloc = std.testing.allocator;
    try std.testing.expectError(error.InvalidNumericCharacterEntity, decodeAlloc(alloc, "&bogus;", true));
}
