const std = @import("std");

pub const DecodeError = error{
    InvalidNumericCharacterEntity,
    UnterminatedEntity,
};

const EntityDecode = struct {
    consumed: usize,
    bytes: [4]u8,
    len: usize,
};

pub fn decodeInPlaceIfEntity(noalias buf: []u8, strict: bool) DecodeError!usize {
    const first = std.mem.indexOfScalar(u8, buf, '&') orelse return buf.len;
    var src: usize = first;
    var dst: usize = first;

    while (src < buf.len) {
        if (buf[src] != '&') {
            if (dst != src) buf[dst] = buf[src];
            src += 1;
            dst += 1;
            continue;
        }

        const decoded = try decodeEntity(buf, src, strict);
        if (decoded) |d| {
            std.mem.copyForwards(u8, buf[dst .. dst + d.len], d.bytes[0..d.len]);
            src += d.consumed;
            dst += d.len;
            continue;
        }

        if (dst != src) buf[dst] = '&';
        src += 1;
        dst += 1;
    }

    return dst;
}

pub fn decodeAndNormalizeInPlace(noalias buf: []u8, strict: bool) DecodeError!usize {
    const first = std.mem.indexOfScalar(u8, buf, '&');
    if (first == null) {
        return normalizeWhitespaceInPlace(buf);
    }

    var src: usize = 0;
    var dst: usize = 0;
    var in_ws = false;

    while (src < buf.len) {
        if (buf[src] != '&') {
            emitNormalized(&dst, &in_ws, buf[src], buf);
            src += 1;
            continue;
        }

        const decoded = try decodeEntity(buf, src, strict);
        if (decoded) |d| {
            var j: usize = 0;
            while (j < d.len) : (j += 1) {
                emitNormalized(&dst, &in_ws, d.bytes[j], buf);
            }
            src += d.consumed;
            continue;
        }

        emitNormalized(&dst, &in_ws, '&', buf);
        src += 1;
    }

    return dst;
}

pub fn validateEntities(noalias buf: []const u8, strict: bool) DecodeError!void {
    var src = std.mem.indexOfScalar(u8, buf, '&') orelse return;
    while (src < buf.len) {
        if (buf[src] != '&') {
            src += 1;
            continue;
        }

        const decoded = try decodeEntity(buf, src, strict);
        if (decoded) |d| {
            src += d.consumed;
        } else {
            src += 1;
        }
    }
}

fn decodeEntity(noalias buf: []const u8, start: usize, strict: bool) DecodeError!?EntityDecode {
    const semi = std.mem.indexOfScalarPos(u8, buf, start + 1, ';') orelse {
        if (strict) return error.UnterminatedEntity;
        return null;
    };

    const body = buf[start + 1 .. semi];
    if (body.len == 0) {
        if (strict) return error.InvalidNumericCharacterEntity;
        return null;
    }

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
            .consumed = semi - start + 1,
            .bytes = .{ c, 0, 0, 0 },
            .len = 1,
        };
    }

    if (body[0] == '#') {
        const cp = parseNumericEntity(body[1..]) catch |e| {
            if (strict) return e;
            return null;
        };

        var out: [4]u8 = undefined;
        const written = std.unicode.utf8Encode(cp, &out) catch {
            if (strict) return error.InvalidNumericCharacterEntity;
            return null;
        };

        return .{
            .consumed = semi - start + 1,
            .bytes = out,
            .len = written,
        };
    }

    if (strict) return error.InvalidNumericCharacterEntity;
    return null;
}

fn emitNormalized(noalias dst: *usize, noalias in_ws: *bool, c: u8, noalias out: []u8) void {
    const ws = c == ' ' or c == '\t' or c == '\n' or c == '\r';
    if (ws) {
        if (!in_ws.*) {
            out[dst.*] = ' ';
            dst.* += 1;
            in_ws.* = true;
        }
        return;
    }

    out[dst.*] = c;
    dst.* += 1;
    in_ws.* = false;
}

pub fn normalizeWhitespaceInPlace(noalias buf: []u8) usize {
    var src: usize = 0;
    var dst: usize = 0;
    var in_ws = false;

    while (src < buf.len) : (src += 1) {
        const c = buf[src];
        const ws = c == ' ' or c == '\t' or c == '\n' or c == '\r';
        if (ws) {
            if (!in_ws) {
                buf[dst] = ' ';
                dst += 1;
                in_ws = true;
            }
            continue;
        }

        in_ws = false;
        buf[dst] = c;
        dst += 1;
    }

    return dst;
}

fn parseNumericEntity(text: []const u8) DecodeError!u21 {
    if (text.len == 0) return error.InvalidNumericCharacterEntity;

    const is_hex = text[0] == 'x' or text[0] == 'X';
    const digits = if (is_hex) text[1..] else text;
    if (digits.len == 0) return error.InvalidNumericCharacterEntity;

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
        if (d == 255) return error.InvalidNumericCharacterEntity;
        if (is_hex) {
            value = value * 16 + d;
        } else {
            value = value * 10 + d;
        }
        if (value > 0x10FFFF) return error.InvalidNumericCharacterEntity;
    }

    if (value >= 0xD800 and value <= 0xDFFF) return error.InvalidNumericCharacterEntity;
    return @intCast(value);
}

test "decodeInPlaceIfEntity leaves plain text untouched" {
    var buf = "plain text".*;
    const len = try decodeInPlaceIfEntity(&buf, true);
    try std.testing.expectEqual(@as(usize, 10), len);
    try std.testing.expectEqualStrings("plain text", buf[0..len]);
}

test "decodeInPlaceIfEntity decodes named and numeric entities" {
    var buf = "&amp;&#65;&#x42;".*;
    const len = try decodeInPlaceIfEntity(&buf, true);
    try std.testing.expectEqualStrings("&AB", buf[0..len]);
}

test "decodeAndNormalizeInPlace combines both operations" {
    var buf = " a\n&amp;\t b ".*;
    const len = try decodeAndNormalizeInPlace(&buf, true);
    try std.testing.expectEqualStrings(" a & b ", buf[0..len]);
}

test "normalizeWhitespaceInPlace coalesces repeated XML whitespace" {
    var buf = "\t a \r\n b  c ".*;
    const len = normalizeWhitespaceInPlace(&buf);
    try std.testing.expectEqualStrings(" a b c ", buf[0..len]);
}

test "non-strict decode leaves malformed and unknown entities literal" {
    var unknown = "&bogus; &amp".*;
    const len_unknown = try decodeInPlaceIfEntity(&unknown, false);
    try std.testing.expectEqualStrings("&bogus; &amp", unknown[0..len_unknown]);

    var apost_quot = "&apos;&quot;".*;
    const len_aq = try decodeInPlaceIfEntity(&apost_quot, true);
    try std.testing.expectEqualStrings("'\"", apost_quot[0..len_aq]);
}

test "validateEntities rejects malformed strict input" {
    try std.testing.expectError(error.UnterminatedEntity, validateEntities("&amp", true));
    try std.testing.expectError(error.InvalidNumericCharacterEntity, validateEntities("&#x110000;", true));
    try std.testing.expectError(error.InvalidNumericCharacterEntity, validateEntities("&#;", true));
    try std.testing.expectError(error.InvalidNumericCharacterEntity, validateEntities("&#xD800;", true));
}
