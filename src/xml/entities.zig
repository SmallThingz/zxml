const std = @import("std");

pub const DecodeError = error{
    InvalidNumericCharacterEntity,
    UnterminatedEntity,
};

pub fn decodeInPlace(buf: []u8, strict: bool) DecodeError!usize {
    var src: usize = 0;
    var dst: usize = 0;

    while (src < buf.len) {
        if (buf[src] != '&') {
            buf[dst] = buf[src];
            src += 1;
            dst += 1;
            continue;
        }

        const semi = std.mem.indexOfScalarPos(u8, buf, src + 1, ';') orelse {
            if (strict) return error.UnterminatedEntity;
            buf[dst] = buf[src];
            src += 1;
            dst += 1;
            continue;
        };

        const body = buf[src + 1 .. semi];
        if (body.len == 0) {
            if (strict) return error.InvalidNumericCharacterEntity;
            buf[dst] = buf[src];
            src += 1;
            dst += 1;
            continue;
        }

        if (decodeNamed(body)) |c| {
            buf[dst] = c;
            dst += 1;
            src = semi + 1;
            continue;
        }

        if (body[0] == '#') {
            const cp = parseNumericEntity(body[1..]) catch |e| {
                if (strict) return e;
                buf[dst] = buf[src];
                src += 1;
                dst += 1;
                continue;
            };

            const written = std.unicode.utf8Encode(cp, buf[dst..]) catch {
                if (strict) return error.InvalidNumericCharacterEntity;
                buf[dst] = buf[src];
                src += 1;
                dst += 1;
                continue;
            };
            dst += written;
            src = semi + 1;
            continue;
        }

        if (strict) return error.InvalidNumericCharacterEntity;
        buf[dst] = buf[src];
        src += 1;
        dst += 1;
    }

    return dst;
}

pub fn normalizeWhitespaceInPlace(buf: []u8) usize {
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

fn decodeNamed(body: []const u8) ?u8 {
    if (std.mem.eql(u8, body, "amp")) return '&';
    if (std.mem.eql(u8, body, "lt")) return '<';
    if (std.mem.eql(u8, body, "gt")) return '>';
    if (std.mem.eql(u8, body, "apos")) return '\'';
    if (std.mem.eql(u8, body, "quot")) return '"';
    return null;
}

fn parseNumericEntity(text: []const u8) DecodeError!u21 {
    if (text.len == 0) return error.InvalidNumericCharacterEntity;

    const is_hex = text[0] == 'x' or text[0] == 'X';
    const digits = if (is_hex) text[1..] else text;
    if (digits.len == 0) return error.InvalidNumericCharacterEntity;

    var value: u32 = 0;
    for (digits) |c| {
        const d = if (is_hex) hexVal(c) else decVal(c);
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

fn decVal(c: u8) u8 {
    if (c >= '0' and c <= '9') return c - '0';
    return 255;
}

fn hexVal(c: u8) u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return 255;
}
